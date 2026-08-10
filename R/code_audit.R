#' @title Code Audit -- static reference extraction (31w step 1)
#' @description Deterministic, LLM-free, filesystem-free static analysis of R
#'   code to find where it pulls in *external* scripts/data. This is the first
#'   layer of the code-audit defence (see references/plan/31w): it walks the AST
#'   via base `getParseData()` and reports which external files the code
#'   references by literal path, plus whether it uses dynamic primitives that a
#'   static pass cannot resolve.
#'
#'   Threat model split (31w):
#'   * **Threat A (static)** -- `source("x.R")` / `load("x.rds")` / `readRDS` /
#'     `sourceCpp` with a *literal string path*. Statically extractable -> the
#'     path is returned in `static_paths` for downstream whitelist + review.
#'   * **Threat B (dynamic)** -- `source(var)`, `eval(parse())`, `get(paste0())`,
#'     `do.call()` etc. Undecidable statically (halting problem) -> flagged
#'     `dynamic = TRUE`; the real defence is the sandbox (31n), not this audit.
#'
#'   This function reads NO files and calls NO LLM -- it only parses the code
#'   text. It is safe to run on fully untrusted code (parsing != evaluating).
#' @name code_audit
#' @keywords internal
NULL

# Functions that pull an external script/object into the session by path.
.AUDIT_SOURCE_FNS <- c("source", "sys.source", "load", "readRDS", "readRDS2",
                       "sourceCpp", "Rcpp::sourceCpp")

# Dynamic primitives: their target is only known at runtime, so a static pass
# cannot resolve what they load/execute. Presence => dynamic = TRUE.
.AUDIT_DYNAMIC_FNS <- c("eval", "parse", "get", "get0", "mget", "getAnywhere",
                        "do.call", "match.fun", "Recall", ".Call", ".External",
                        "sys.function", "as.function", "eval.parent",
                        "evalq", "str2lang", "str2expression")

#' Statically extract external-file references from R code.
#'
#' @param code Character (one or more lines) of R source. Untrusted -- parsed,
#'   never evaluated.
#' @return A list:
#'   * `static_paths` -- character vector of literal string paths passed to a
#'     source/load-family call.
#'   * `dynamic` -- TRUE if the code uses a dynamic primitive, calls a
#'     source-family function with no literal string argument (e.g.
#'     `source(var)`), or assigns/references a source-family function as a bare
#'     symbol (possible indirect call) -- i.e. a static pass cannot be sure what
#'     it loads/runs.
#'   * `source_calls` -- which source-family functions were called (for audit).
#'   * `parse_error` -- TRUE if the code did not parse (treated as dynamic:
#'     un-analysable).
#' @keywords internal
.audit_r_code_refs <- function(code) {
  empty <- list(static_paths = character(), dynamic = FALSE,
                source_calls = character(), parse_error = FALSE)
  if (!is.character(code) || !length(code)) return(empty)
  src <- paste(code, collapse = "\n")
  if (!nzchar(trimws(src))) return(empty)

  expr <- tryCatch(parse(text = src, keep.source = TRUE),
                   error = function(e) NULL)
  if (is.null(expr)) {
    # Un-parseable => cannot analyse => treat as dynamic (fail safe).
    return(list(static_paths = character(), dynamic = TRUE,
                source_calls = character(), parse_error = TRUE))
  }
  pd <- tryCatch(utils::getParseData(expr), error = function(e) NULL)
  if (is.null(pd) || !nrow(pd)) return(empty)

  strip_quotes <- function(x) gsub("^['\"]|['\"]$", "", x)

  # All function-call tokens and bare symbols.
  call_names <- pd$text[pd$token == "SYMBOL_FUNCTION_CALL"]
  sym_names  <- pd$text[pd$token == "SYMBOL"]

  source_calls <- intersect(call_names, .AUDIT_SOURCE_FNS)
  dynamic <- FALSE

  # (1) Dynamic primitives called anywhere.
  if (length(intersect(call_names, .AUDIT_DYNAMIC_FNS))) dynamic <- TRUE

  # (2) A source-family function referenced as a BARE SYMBOL (not a call) means
  #     it may be assigned then called indirectly (f <- source; f("x")). The
  #     indirect call site can't be tied to a literal path statically.
  if (length(intersect(sym_names, .AUDIT_SOURCE_FNS))) dynamic <- TRUE

  # (3) For each source-family CALL, find its literal string argument(s). In
  #     getParseData the SYMBOL_FUNCTION_CALL's parent is an `expr` that is a
  #     sibling of the argument `expr`s under a common enclosing `expr` (the whole
  #     call). So walk UP one level from the call symbol to the enclosing call
  #     expr, then collect STR_CONST descendants of that enclosing expr.
  static_paths <- character()
  if (length(source_calls)) {
    fn_rows <- which(pd$token == "SYMBOL_FUNCTION_CALL" &
                       pd$text %in% .AUDIT_SOURCE_FNS)
    children <- split(pd$id, pd$parent)          # parent id -> child ids
    row_by_id <- stats::setNames(seq_len(nrow(pd)), pd$id)
    collect_str <- function(root_id) {
      out <- character(); stack <- as.character(root_id); seen <- character()
      while (length(stack)) {
        cur <- stack[[1L]]; stack <- stack[-1L]
        if (cur %in% seen) next
        seen <- c(seen, cur)
        ri <- row_by_id[[cur]]
        if (!is.null(ri) && identical(pd$token[[ri]], "STR_CONST"))
          out <- c(out, strip_quotes(pd$text[[ri]]))
        kids <- children[[cur]]
        if (!is.null(kids)) stack <- c(stack, as.character(kids))
      }
      out
    }
    for (r in fn_rows) {
      sym_parent <- pd$parent[r]                 # `expr` directly wrapping the symbol
      # enclosing call expr = parent of that expr (grandparent of the symbol)
      gp_row <- row_by_id[[as.character(sym_parent)]]
      call_expr <- if (!is.null(gp_row)) pd$parent[gp_row] else sym_parent
      strs <- collect_str(call_expr)
      if (length(strs)) static_paths <- c(static_paths, strs)
      else dynamic <- TRUE                       # source-family call w/ no literal path
    }
  }

  list(static_paths = unique(static_paths), dynamic = isTRUE(dynamic),
       source_calls = unique(source_calls), parse_error = FALSE)
}
