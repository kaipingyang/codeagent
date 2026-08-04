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
# Global protected-value index (hash set). Populated by register_protected_data();
# consulted by the egress value_match. Process-global (per-session isolation is
# deferred -- see plan #5). Empty => value_match is a no-op.
.data_shield_index <- new.env(parent = emptyenv())

# Run the egress pipeline on model-facing text: row-cap (bulk) THEN value_match
# (targeted protected values). Returns list(text, changed).
#' @keywords internal
.data_shield_process_text <- function(text, max_rows = 0L) {
  if (!is.character(text) || length(text) != 1L) return(list(text = text, changed = FALSE))
  cp <- .data_shield_row_cap(text, max_rows = max_rows)
  if (isTRUE(cp$capped)) return(list(text = cp$text, changed = TRUE))
  vm <- tryCatch(.data_shield_value_scan(text, .data_shield_index),
                 error = function(e) list(hit = FALSE))
  if (isTRUE(vm$hit))
    return(list(text = sprintf(
      "[data_shield] output withheld: contains %d protected data value(s).", vm$n),
      changed = TRUE))
  list(text = text, changed = FALSE)
}

.data_shield_filter_result <- function(result, max_rows = 0L) {
  # ellmer ContentToolResult -> filter its model-facing value text
  if (isTRUE(tryCatch(S7::S7_inherits(result, ellmer::ContentToolResult),
                      error = function(e) FALSE))) {
    val <- tryCatch(as.character(result@value), error = function(e) NULL)
    if (is.character(val) && length(val) == 1L) {
      pr <- .data_shield_process_text(val, max_rows = max_rows)
      if (isTRUE(pr$changed)) result@value <- pr$text
    }
    return(result)
  }
  # raw data.frame / matrix return -> filter its printed form
  if (is.data.frame(result) || is.matrix(result)) {
    txt <- tryCatch(paste(utils::capture.output(print(result)), collapse = "\n"),
                    error = function(e) "")
    pr <- .data_shield_process_text(txt, max_rows = max_rows)
    if (isTRUE(pr$changed)) return(pr$text)
    return(result)
  }
  # single character string
  if (is.character(result) && length(result) == 1L) {
    pr <- .data_shield_process_text(result, max_rows = max_rows)
    if (isTRUE(pr$changed)) return(pr$text)
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

# ---------------------------------------------------------------------------
# P0.5: value_match --- deterministic detection of *registered* protected
# values in egress text. Catches targeted single-value leaks the shape-based
# row-cap lets through (e.g. printing one subject's name/id). We index only
# HIGH-ENTROPY values (unique, long enough, high-cardinality columns, non
# small-int) so common/categorical values don't cause false positives -- those
# are the describe layer's job. Token-hash matching (v0); delimited/multi-word
# values are a known gap (Aho-Corasick is a later enhancement).
# ---------------------------------------------------------------------------

# Normalise a value/token for matching: casefold + canonical numeric form.
#' @keywords internal
.data_shield_normalize <- function(x) {
  x   <- tolower(as.character(x))
  num <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(num) & nzchar(x), format(num, scientific = FALSE, trim = TRUE), x)
}

# Build a value index (hash set env) from a data.frame's sensitive columns.
#' @keywords internal
.data_shield_build_value_index <- function(df, cols = names(df),
                                           min_len = 3L, min_card = 8L) {
  set <- new.env(parent = emptyenv())
  n <- 0L
  for (cn in intersect(cols, names(df))) {
    v <- df[[cn]]
    if (is.null(v)) next
    vals <- unique(v[!is.na(v)])
    if (length(vals) < min_card) next                     # low-cardinality -> skip
    ch <- as.character(vals)
    ch <- ch[nchar(ch) >= min_len]                        # too short -> skip
    ch <- ch[!grepl("^[0-9]{1,2}$", ch)]                  # pure small int -> skip
    for (x in .data_shield_normalize(ch)) {
      assign(x, TRUE, envir = set); n <- n + 1L
    }
  }
  attr(set, "n") <- n
  set
}

# Scan text for indexed protected values (token-hash, v0).
#' @keywords internal
.data_shield_value_scan <- function(text, index) {
  if (!is.environment(index) || !is.character(text) || length(text) != 1L)
    return(list(hit = FALSE, n = 0L, values = character(0)))
  toks <- unique(strsplit(text, "[^[:alnum:].]+", perl = TRUE)[[1L]])
  toks <- gsub("^\\.+|\\.+$", "", toks)                 # strip edge dots (keep 3.14)
  toks <- toks[nchar(toks) >= 3L]
  if (!length(toks)) return(list(hit = FALSE, n = 0L, values = character(0)))
  norm <- .data_shield_normalize(toks)
  hit  <- norm[vapply(norm, function(t) exists(t, envir = index, inherits = FALSE),
                      logical(1))]
  list(hit = length(hit) > 0L, n = length(hit), values = unique(hit))
}

#' Register protected data for the Data Shield value_match
#'
#' @description
#' Index the (high-entropy) values of a data.frame so the Data Shield egress
#' guard withholds them if they surface in a tool result (e.g. a tool that
#' prints one subject's name or id -- something the shape-based row-cap lets
#' through). Only long, high-cardinality, non-small-integer values are indexed;
#' common / low-cardinality / small-integer values are skipped to avoid false
#' positives (those belong to the describe layer, not value_match).
#'
#' Effects are process-global for the session (per-session isolation is a
#' planned follow-up). Call once per protected dataset, then
#' [install_data_shield()] (or `codeagent_client(data_shield=)`).
#'
#' @param df A data.frame (e.g. an uploaded dataset).
#' @param cols Character. Columns to index (default: all).
#' @param min_len,min_card Integer. "Indexable" thresholds: value length and
#'   column cardinality.
#' @return Invisibly, the number of values indexed.
#' @seealso [install_data_shield()], [codeagent_client()]
#' @export
register_protected_data <- function(df, cols = NULL, min_len = 3L, min_card = 8L) {
  if (!is.data.frame(df))
    stop("`df` must be a data.frame.", call. = FALSE)
  cols <- cols %||% names(df)
  idx  <- .data_shield_build_value_index(df, cols = cols,
                                         min_len = min_len, min_card = min_card)
  keys <- ls(idx, all.names = TRUE)
  for (k in keys) assign(k, TRUE, envir = .data_shield_index)
  invisible(length(keys))
}
