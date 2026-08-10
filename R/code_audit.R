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

# Source-file extensions the audit is allowed to read. A referenced path with
# any other extension is out of scope (data blobs, binaries) -> not read.
.AUDIT_READ_EXTS <- c("R", "r", "Rmd", "rmd", "qmd", "cpp", "c", "h", "hpp",
                      "rds", "Rds", "RData", "Rdata", "rda")

# Decide whether a referenced path is safe to read: it must resolve to a real
# location UNDER project_root (symlink-escape resolved by
# .data_shield_resolve_path -> normalizePath) AND carry a source-file
# extension. Returns list(ok, resolved, reason). The whitelist is enforced in
# CODE here, never delegated to the LLM/prompt (31w B2, colleague review).
#' @keywords internal
.audit_path_allowed <- function(path, project_root) {
  root <- tryCatch(normalizePath(project_root, winslash = "/", mustWork = FALSE),
                   error = function(e) project_root)
  resolved <- tryCatch(.data_shield_resolve_path(path, root),
                       error = function(e) NULL)
  if (is.null(resolved))
    return(list(ok = FALSE, resolved = NA_character_, reason = "unresolvable path"))
  if (!.data_shield_path_under(resolved, root))
    return(list(ok = FALSE, resolved = resolved,
                reason = "path outside project root"))
  ext <- tolower(tools::file_ext(resolved))
  if (!nzchar(ext) || !(ext %in% tolower(.AUDIT_READ_EXTS)))
    return(list(ok = FALSE, resolved = resolved,
                reason = sprintf("non-source extension '%s'", ext)))
  if (!file.exists(resolved))
    return(list(ok = FALSE, resolved = resolved, reason = "file does not exist"))
  list(ok = TRUE, resolved = resolved, reason = NA_character_)
}

#' Audit R code for risky external references (deterministic pipeline).
#'
#' Runs the full first-pass audit: AST extraction -> tool-layer path whitelist
#' -> deterministic read of whitelisted source files -> (optionally) feed the
#' read text to the Data Shield reviewer. The reviewer NEVER gets a
#' read/write/shell tool: this function decides what to read (code, not LLM),
#' bounds it to whitelisted in-project source files, and only hands the reviewer
#' vetted text.
#'
#' @param code Character. The R code to audit (untrusted; parsed, not run).
#' @param shield Optional `DataShield` whose reviewer reviews the referenced
#'   file contents. `NULL` -> report references only (no content review).
#' @param project_root Directory the whitelist confines reads to.
#' @param max_bytes Per-file read cap (avoid feeding huge files to the reviewer).
#' @return A list: `static_paths`, `dynamic`, `allowed` (paths read),
#'   `blocked` (list of path+reason not read), `reviews` (per-file reviewer
#'   verdicts when a shield is given), `risk` (overall: "none"/"review"/"block").
#' @keywords internal
.audit_code_impl <- function(code, shield = NULL, project_root = getwd(),
                             max_bytes = 100000L) {
  refs <- .audit_r_code_refs(code)
  allowed <- character(); blocked <- list(); reviews <- list()
  for (p in refs$static_paths) {
    dec <- .audit_path_allowed(p, project_root)
    if (!isTRUE(dec$ok)) {
      blocked[[length(blocked) + 1L]] <- list(path = p, reason = dec$reason)
      next
    }
    allowed <- c(allowed, dec$resolved)
    if (inherits(shield, "DataShield")) {
      content <- tryCatch({
        con <- file(dec$resolved, "r"); on.exit(close(con), add = TRUE)
        paste(readLines(con, warn = FALSE, n = -1L), collapse = "\n")
      }, error = function(e) NULL)
      if (is.character(content) && nzchar(content)) {
        content <- substr(content, 1L, max_bytes)
        v <- tryCatch(
          shield$review_code(content,
                             context = list(tool_name = paste0("audit:", basename(dec$resolved)),
                                            capability = "read")),
          error = function(e) list(error = TRUE, reason = "reviewer unavailable"))
        reviews[[length(reviews) + 1L]] <- c(list(path = dec$resolved), v)
      }
    }
  }
  # Overall risk: any blocked path or any reviewer-flagged file -> escalate;
  # dynamic code that can't be resolved -> at least "review".
  flagged <- any(vapply(reviews, function(v)
    is.list(v) && !isTRUE(v$error) && !identical(v$risk %||% "none", "none"),
    logical(1)))
  risk <- if (length(blocked) || flagged) "block"
          else if (isTRUE(refs$dynamic) || length(reviews)) "review"
          else "none"
  list(static_paths = refs$static_paths, dynamic = refs$dynamic,
       allowed = allowed, blocked = blocked, reviews = reviews, risk = risk)
}

#' Build the AuditCode tool (pluggable static code-safety auditor)
#'
#' Wraps the deterministic audit pipeline ([.audit_code_impl()]) as an
#' `ellmer::tool()` the main-loop model can call to check whether a block of R
#' code safely references external scripts/data before running it. The tool
#' NEVER gives the model (or the reviewer) a read/write/shell capability: it
#' deterministically extracts referenced paths (AST), enforces an in-project
#' source-file whitelist in code, reads only whitelisted files, and (with a
#' shield) hands the vetted text to the reviewer.
#'
#' Opt-in: not registered by default. Host wires it in (e.g. when running with
#' the sandbox disabled) so the model can self-audit external references.
#'
#' @param shield Optional `DataShield` whose reviewer reviews referenced file
#'   contents (`NULL` = report references only).
#' @param project_root Directory the read whitelist is confined to.
#' @return An `ellmer::tool()`.
#' @export
audit_code_tool <- function(shield = NULL, project_root = getwd()) {
  force(shield); force(project_root)
  ellmer::tool(
    name = "AuditCode",
    fun = function(code, `_intent` = NULL) {
      res <- tryCatch(
        .audit_code_impl(code, shield = shield, project_root = project_root),
        error = function(e) list(risk = "review", dynamic = TRUE,
                                 static_paths = character(), allowed = character(),
                                 blocked = list(), reviews = list(),
                                 error = conditionMessage(e)))
      # Human/LLM-facing summary. No file contents are echoed back -- only
      # metadata (which refs, which blocked + why, overall risk).
      blocked_txt <- if (length(res$blocked))
        paste(vapply(res$blocked, function(b)
          sprintf("  - %s (%s)", b$path, b$reason), character(1)), collapse = "\n")
        else "  (none)"
      review_txt <- if (length(res$reviews))
        paste(vapply(res$reviews, function(v)
          sprintf("  - %s: risk=%s", basename(v$path %||% "?"),
                  v$risk %||% (if (isTRUE(v$error)) "reviewer_error" else "?")),
          character(1)), collapse = "\n")
        else "  (none reviewed)"
      summary <- paste0(
        "AuditCode risk: ", res$risk,
        "\ndynamic (static-unresolvable) primitives: ", isTRUE(res$dynamic),
        "\nstatic external refs: ",
        if (length(res$static_paths)) paste(res$static_paths, collapse = ", ") else "(none)",
        "\nblocked (outside project / non-source / missing):\n", blocked_txt,
        "\nreviewer verdicts:\n", review_txt)
      .tool_result2(summary, kind = "text", icon = "shield-check",
                    title = sprintf("AuditCode -- risk: %s", res$risk),
                    payload = list(text = summary, lang = "text"))
    },
    description = paste0(
      "Statically audit R code for risky external references before running it. ",
      "Reports which external scripts/data it source()/load()s by literal path, ",
      "flags dynamic primitives (eval/parse/get/do.call) a static pass can't ",
      "resolve, and -- when a data shield is active -- reviews the contents of ",
      "whitelisted in-project source files. Reads no files outside the project ",
      "and never executes the code."),
    arguments = list(
      code = ellmer::type_string("The R code to audit (not executed)."),
      `_intent` = ellmer::type_string(
        "Why this code is being audited.", required = FALSE)),
    annotations = ellmer::tool_annotations(
      title = "Audit code", read_only_hint = TRUE, destructive_hint = FALSE)
  )
}
