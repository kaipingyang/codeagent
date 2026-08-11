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

  # (3) For each source-family CALL, resolve ONLY its FIRST (path) argument, and
  #     treat it as a static path ONLY when that argument is a single string
  #     LITERAL. Anything else in the path position -- a variable, a nested call
  #     (file.path/paste0), a concatenation, a conditional -- is
  #     statically unresolvable => dynamic=TRUE, no path extracted. String
  #     literals in OTHER argument positions (encoding=, local=, ...) are ignored
  #     (kiro round-2 #6: the old pass collected every STR_CONST under the call,
  #     so source(file.path(b,"x.R")) mis-reported "x.R" as static and
  #     source("ok.R", encoding="UTF-8") mis-reported "UTF-8" as a path).
  static_paths <- character()
  if (length(source_calls)) {
    fn_rows <- which(pd$token == "SYMBOL_FUNCTION_CALL" &
                       pd$text %in% .AUDIT_SOURCE_FNS)
    children <- split(seq_len(nrow(pd)), pd$parent)   # parent id -> child ROW indices
    id_to_row <- stats::setNames(seq_len(nrow(pd)), pd$id)
    for (r in fn_rows) {
      sym_id      <- pd$id[r]
      sym_par_id  <- pd$parent[r]                      # `expr` wrapping the symbol
      spr         <- id_to_row[[as.character(sym_par_id)]]
      call_id     <- if (!is.null(spr)) pd$parent[spr] else sym_par_id  # enclosing call expr
      kid_rows    <- children[[as.character(call_id)]]
      if (is.null(kid_rows)) { dynamic <- TRUE; next }
      # Direct children of the call expr, in source order. Structure is:
      #   expr(fn-name)  '('  <arg1>  ','  <arg2> ... ')'
      # Find the FIRST argument node = the first child after '(' that is not the
      # function-name expr and not punctuation.
      kid_rows <- kid_rows[order(pd$id[kid_rows])]
      toks     <- pd$token[kid_rows]
      # First argument node = first child that is NOT the function-name expr
      # (id == sym_par_id, the expr wrapping our SYMBOL_FUNCTION_CALL) and not
      # punctuation / named-arg tags. Structure: expr(fn) '(' <arg1> ',' ...
      arg1_row <- NA_integer_
      for (k in seq_along(kid_rows)) {
        row_k <- kid_rows[[k]]
        if (identical(pd$id[[row_k]], sym_par_id)) next          # the fn-name expr
        tk <- toks[[k]]
        if (tk %in% c("'('", "','", "')'", "SYMBOL_SUB", "EQ_SUB")) next
        arg1_row <- row_k; break
      }
      if (is.na(arg1_row)) { dynamic <- TRUE; next }
      # arg1 is a single string literal iff it is itself STR_CONST, OR it is an
      # `expr` whose ONLY meaningful child is a STR_CONST (the parser wraps a bare
      # literal argument in an expr node). A nested call puts a
      # SYMBOL_FUNCTION_CALL under that expr -> not a literal -> dynamic.
      if (identical(pd$token[[arg1_row]], "STR_CONST")) {
        static_paths <- c(static_paths, strip_quotes(pd$text[[arg1_row]]))
      } else if (identical(pd$token[[arg1_row]], "expr")) {
        sub_rows <- children[[as.character(pd$id[[arg1_row]])]]
        sub_tok  <- if (!is.null(sub_rows)) pd$token[sub_rows] else character()
        str_kids <- sub_rows[sub_tok == "STR_CONST"]
        has_call <- any(sub_tok %in% c("SYMBOL_FUNCTION_CALL", "SYMBOL"))
        if (length(str_kids) == 1L && !has_call)
          static_paths <- c(static_paths, strip_quotes(pd$text[[str_kids[[1]]]]))
        else
          dynamic <- TRUE                              # nested call / symbol / concat
      } else {
        dynamic <- TRUE                                # SYMBOL variable etc.
      }
    }
  }

  list(static_paths = unique(static_paths), dynamic = isTRUE(dynamic),
       source_calls = unique(source_calls), parse_error = FALSE)
}

# Source-file extensions the audit is allowed to read AS TEXT. Binary R data
# blobs (rds/RData/rda) are intentionally EXCLUDED (kiro round-2 #13): they are
# not text, readLines() on them is unpredictable, and load()/readRDS() of an
# untrusted blob is itself the RCE risk -- auditing their bytes as text gives no
# safety signal. A referenced .rds path is reported blocked ("binary, not
# text-audited") rather than read.
.AUDIT_READ_EXTS <- c("R", "r", "Rmd", "rmd", "qmd", "cpp", "c", "h", "hpp")

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
  # Must be a REGULAR file, not a directory/pipe/device (kiro round-3): a
  # directory named "not-a-file.R" passes file.exists() but read()s to nothing,
  # which was silently swallowed to risk=none. Reject non-regular targets.
  if (dir.exists(resolved) || !isTRUE(file.info(resolved)$isdir == FALSE))
    return(list(ok = FALSE, resolved = resolved, reason = "not a regular file"))
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
                             max_bytes = 100000L, max_files = 20L) {
  refs <- .audit_r_code_refs(code)
  allowed <- character(); blocked <- list(); reviews <- list()
  n_read <- 0L
  for (p in refs$static_paths) {
    # Cap the number of files read (kiro round-3): a source-heavy snippet could
    # otherwise fan out to unbounded reads. Excess refs are recorded as blocked.
    if (n_read >= max_files) {
      blocked[[length(blocked) + 1L]] <- list(path = p, reason = "max_files cap reached")
      next
    }
    dec <- .audit_path_allowed(p, project_root)
    if (!isTRUE(dec$ok)) {
      blocked[[length(blocked) + 1L]] <- list(path = p, reason = dec$reason)
      next
    }
    n_read <- n_read + 1L
    allowed <- c(allowed, dec$resolved)
    if (inherits(shield, "DataShield")) {
      read_failed <- FALSE
      content <- tryCatch({
        con <- file(dec$resolved, "rb"); on.exit(close(con), add = TRUE)  # rb: bounded binary read
        # TOCTOU guard (kiro round-2 #13 + round-3): re-resolve the opened path
        # and confirm it still matches the vetted target under project_root.
        recheck <- tryCatch(normalizePath(dec$resolved, winslash = "/", mustWork = TRUE),
                            error = function(e) NA_character_)
        if (is.na(recheck) || !identical(recheck, dec$resolved) ||
            !.data_shield_path_under(recheck, normalizePath(project_root, winslash = "/", mustWork = FALSE)))
          stop("path changed after validation (TOCTOU)")
        readChar(con, nchars = max_bytes, useBytes = TRUE)
      }, error = function(e) { read_failed <<- TRUE; NULL })
      # A read/TOCTOU failure must NOT be silently dropped to risk=none (kiro
      # round-3): record it as blocked so the overall risk escalates to block.
      if (isTRUE(read_failed)) {
        blocked[[length(blocked) + 1L]] <- list(path = dec$resolved,
                                                reason = "read/TOCTOU check failed (fail-closed)")
      } else if (is.character(content) && nzchar(content)) {
        v <- tryCatch(
          shield$review_code_public(content,
                             context = list(tool_name = paste0("audit:", basename(dec$resolved)),
                                            capability = "read")),
          error = function(e) list(error = TRUE, reason = "reviewer unavailable"))
        # Async reviewer returns a promise. This pipeline is synchronous and
        # cannot await it here, so an unresolved promise is treated fail-closed:
        # record a block rather than let unreviewed content pass as risk=none
        # (kiro round-3). A host that needs async review should await upstream.
        if (promises::is.promise(v)) {
          blocked[[length(blocked) + 1L]] <- list(path = dec$resolved,
                                                  reason = "reviewer is async; not awaited (fail-closed)")
        } else {
          reviews[[length(reviews) + 1L]] <- c(list(path = dec$resolved), v)
        }
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
