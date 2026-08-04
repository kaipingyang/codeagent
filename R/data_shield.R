#' Data Shield --- pluggable strict data-safety valve (P0 core)
#'
#' @description
#' Opt-in guard that stops raw row-level data from reaching the LLM via the two
#' inbound edges: (1) prompt-side auto-injection (ambient context) and (2) tool
#' results. Off by default (`data_shield = NULL`).
#'
#' This file contains the P0 core: a content-agnostic, shape-based **egress
#' row-cap** for tool results (edge 2). It does NOT inspect code or block
#' `print`; it looks only at the *shape* of a tool's returned text and truncates
#' output that has the signature of a bulk row-level data dump, passing scalars,
#' messages, model summaries, plots and errors through untouched.
#'
#' @name data_shield
#' @keywords internal
NULL

# Does `text` look like a bulk row-level data dump (vs a scalar/message/summary)?
# Heuristic (v0, to be threat-tested): TRUE when the output has a data.frame /
# tibble print signature, OR is a rectangular table with more than `max_rows`
# data rows. Deliberately conservative -- errs toward FALSE (pass) so harmless
# output is never blocked; small/targeted leaks are value_match's job (P0.5).
.data_shield_is_bulk_tabular <- function(text, max_rows = 10L) {
  if (!is.character(text) || length(text) != 1L || !nzchar(text)) return(FALSE)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  if (length(lines) <= max_rows + 1L) return(FALSE)   # too short to be a bulk dump

  # tibble / data.frame print signatures
  if (any(grepl("^#\\s*A tibble:\\s*[0-9,]+\\s*[x\u00d7]\\s*[0-9]+", lines))) return(TRUE)
  if (any(grepl("\\[[0-9,]+ rows? x [0-9]+ columns?\\]", lines)))            return(TRUE)

  # Rectangular: majority of the (non-blank) lines have >= 2 columns separated
  # by runs of whitespace or by commas, AND column count is consistent-ish.
  nb <- lines[nzchar(trimws(lines))]
  if (length(nb) <= max_rows + 1L) return(FALSE)
  ncols <- vapply(nb, function(l) {
    ws  <- length(strsplit(trimws(l), "\\s{2,}|\\t")[[1L]])
    csv <- length(strsplit(l, ",", fixed = TRUE)[[1L]])
    max(ws, csv)
  }, integer(1))
  multi <- mean(ncols >= 2L) >= 0.7            # >=70% of rows are multi-column
  bulk  <- sum(ncols >= 2L) > max_rows          # more than max_rows such rows
  isTRUE(multi && bulk)
}

# Row-cap a single tool-result text: if it looks like a bulk data dump, replace
# it with a shape summary (optionally keeping the first `max_rows` lines).
# `max_rows = 0` => shape-only. Returns list(text, capped, n_lines).
.data_shield_row_cap <- function(text, max_rows = 0L) {
  if (!.data_shield_is_bulk_tabular(text, max_rows = max(max_rows, 1L)))
    return(list(text = text, capped = FALSE))
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  n     <- length(lines)
  head_lines <- if (max_rows > 0L) paste(utils::head(lines, max_rows), collapse = "\n") else ""
  note <- sprintf(
    "[data_shield] tabular output withheld: %d lines look like row-level data.%s",
    n,
    if (max_rows > 0L) sprintf(" First %d line(s) shown; rest omitted.", max_rows) else
      " Use a schema/summary tool instead of dumping rows.")
  list(text = if (nzchar(head_lines)) paste0(head_lines, "\n", note) else note,
       capped = TRUE, n_lines = n)
}

# ---------------------------------------------------------------------------
# P0 wiring: wrap every tool so its result passes through the egress row-cap.
# on_tool_result is a read-only notification in ellmer (cannot rewrite the
# result), so we wrap the tool functions themselves (universal: native / btw /
# MCP / host tools). Off unless a client sets `data_shield`.
# ---------------------------------------------------------------------------

# Apply the egress row-cap to a single tool return value (edge 2). Handles the
# three shapes a tool can return: an ellmer ContentToolResult, a raw data.frame/
# matrix, or a character string. Everything else passes through untouched.
#' @keywords internal
.data_shield_filter_result <- function(result, max_rows = 0L) {
  # ellmer ContentToolResult -> cap its model-facing value text
  if (isTRUE(tryCatch(S7::S7_inherits(result, ellmer::ContentToolResult),
                      error = function(e) FALSE))) {
    val <- tryCatch(as.character(result@value), error = function(e) NULL)
    if (is.character(val) && length(val) == 1L) {
      cp <- .data_shield_row_cap(val, max_rows = max_rows)
      if (isTRUE(cp$capped)) result@value <- cp$text
    }
    return(result)
  }
  # raw data.frame / matrix return -> cap its printed form
  if (is.data.frame(result) || is.matrix(result)) {
    txt <- tryCatch(paste(utils::capture.output(print(result)), collapse = "\n"),
                    error = function(e) "")
    cp <- .data_shield_row_cap(txt, max_rows = max_rows)
    if (isTRUE(cp$capped)) return(cp$text)
    return(result)
  }
  # single character string
  if (is.character(result) && length(result) == 1L) {
    cp <- .data_shield_row_cap(result, max_rows = max_rows)
    if (isTRUE(cp$capped)) return(cp$text)
  }
  result
}

# Wrap one ToolDef in place: replace its underlying function (S7_data) with one
# that runs the original then filters the result. Preserves name / description /
# arguments / annotations. Idempotent (marks the wrapper).
#' @keywords internal
.data_shield_wrap_tool <- function(tool, max_rows = 0L) {
  orig <- tryCatch(S7::S7_data(tool), error = function(e) NULL)
  if (!is.function(orig)) return(tool)
  if (isTRUE(attr(orig, "data_shield_wrapped"))) return(tool)   # already wrapped
  wrapped <- function(...) .data_shield_filter_result(orig(...), max_rows = max_rows)
  attr(wrapped, "data_shield_wrapped") <- TRUE
  tryCatch({ S7::S7_data(tool) <- wrapped }, error = function(e) NULL)
  tool
}

# Per-chat guard so we wrap each chat's tools only once.
.data_shield_installed <- new.env(parent = emptyenv())

#' Install the Data Shield egress guard on a Chat (P0)
#'
#' @description
#' Opt-in strict data-safety guard. Wraps every tool currently registered on
#' `chat` so that bulk row-level data in a tool's result is truncated to a shape
#' summary before it reaches the model (edge 2 of the two inbound edges; see the
#' `data-shield` vignette). Off by default; call once **after** all tools are
#' registered. Content-agnostic and shape-based -- it does not inspect code or
#' block `print`.
#'
#' @param chat An `ellmer::Chat`.
#' @param max_rows Integer. Rows to keep before truncating a bulk tabular result
#'   (`0` = shape summary only).
#' @return Invisibly, `chat`.
#' @seealso [codeagent_client()]
#' @export
install_data_shield <- function(chat, max_rows = 0L) {
  key <- tryCatch(rlang::obj_address(chat), error = function(e) NULL) %||% "default"
  if (isTRUE(.data_shield_installed[[key]])) return(invisible(chat))
  tools <- tryCatch(chat$get_tools(), error = function(e) list())
  if (length(tools)) {
    wrapped <- lapply(tools, function(t) .data_shield_wrap_tool(t, max_rows = max_rows))
    tryCatch(chat$set_tools(wrapped), error = function(e) NULL)
  }
  .data_shield_installed[[key]] <- TRUE
  invisible(chat)
}

# Resolve max_rows from a `data_shield` setting (NULL=off, TRUE=on, list=config).
#' @keywords internal
.data_shield_max_rows <- function(data_shield) {
  if (is.list(data_shield)) as.integer(data_shield$max_rows %||% 0L) else 0L
}
