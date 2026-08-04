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
