#' @title Search Tools
#' @description Glob, Grep, LS -- file/content search.
#' @name tools_search
#' @keywords internal
NULL

#' Create the Glob tool
#'
#' @return An `ellmer::tool()` object.
#' @export
glob_tool <- function() {
  ellmer::tool(
    name = "Glob",
    fun = function(pattern, path = NULL, `_intent` = NULL) {
      base <- if (!is.null(path)) path else getwd()
      tryCatch({
        # Use portable ** implementation when the pattern contains **.
        # Sys.glob() handles simple patterns (no **) reliably on all platforms.
        files <- if (grepl("**", pattern, fixed = TRUE)) {
          .glob_with_starstar(base, pattern)
        } else {
          Sys.glob(file.path(base, pattern))
        }
        if (length(files) == 0L) return("No files matched.")
        result <- paste(files, collapse = "\n")
        result <- truncate_tool_result(result, "Glob")
        n <- length(files)
        .tool_result2(
          result,
          kind     = "text",
          icon     = "search",
          title    = sprintf("Glob <code>%s</code> (%d file%s)",
                             htmltools::htmlEscape(pattern), n,
                             if (n == 1L) "" else "s"),
          markdown = paste0("```\n", result, "\n```"),
          payload  = list(text = result)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Find files matching a glob pattern (e.g. '**/*.R', 'tests/*.test.R'). ",
      "Returns matching file paths sorted by modification time."
    ),
    arguments = list(
      pattern = ellmer::type_string(
        "Glob pattern to match files against.", required = TRUE),
      path    = ellmer::type_string(
        "Base directory to search in. Defaults to working directory.",
        required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of what files are being searched for.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "Glob",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Grep tool
# ---------------------------------------------------------------------------

#' Create the Grep tool
#'
#' Uses `rg` (ripgrep) if available, falls back to base R `grep`.
#'
#' @return An `ellmer::tool()` object.
#' @export
grep_tool <- function() {
  ellmer::tool(
    name = "Grep",
    fun = function(pattern, path = NULL, glob = NULL,
                   output_mode = "content", `-i` = FALSE, `-n` = TRUE,
                   head_limit = 250L, offset = 0L, multiline = FALSE,
                   `_intent` = NULL) {
      base  <- if (!is.null(path)) path else getwd()
      limit <- as.integer(head_limit)
      off   <- as.integer(offset)

      # Build ripgrep / fallback output
      rg_path <- Sys.which("rg")
      if (nzchar(rg_path)) {
        # Choose rg flag based on output_mode
        mode_flag <- switch(output_mode,
          files_with_matches = "-l",
          count              = "--count",
          NULL  # content mode: no extra flag
        )
        args <- c(
          mode_flag,
          if (isTRUE(`-i`)) "-i",
          if (identical(output_mode, "content") && isTRUE(`-n`)) "-n",
          if (isTRUE(multiline)) c("-U", "--multiline-dotall"),
          if (!is.null(glob)) c("--glob", glob),
          "--color=never",
          pattern, base
        )
        out <- tryCatch(
          system2(rg_path, args, stdout = TRUE, stderr = FALSE),
          error = function(e) character(0)
        )
      } else {
        # Fallback: list files + base grep
        files <- list.files(base, recursive = TRUE, full.names = TRUE)
        if (!is.null(glob))
          files <- files[grepl(utils::glob2rx(glob), basename(files))]

        out <- character(0)
        for (f in files) {
          lines <- tryCatch(readLines(f, warn = FALSE),
                            error = function(e) character(0))
          hits  <- grep(pattern, lines, value = FALSE,
                        ignore.case = isTRUE(`-i`))
          if (length(hits)) {
            out <- c(out, switch(output_mode,
              files_with_matches = f,
              count              = paste0(f, ":", length(hits)),
              # content (default): filepath:linenum:content or filepath:content
              paste0(if (isTRUE(`-n`)) paste0(f, ":", hits, ":") else paste0(f, ":"),
                     lines[hits])
            ))
          }
        }
        # Deduplicate for files_with_matches fallback
        if (identical(output_mode, "files_with_matches"))
          out <- unique(out)
      }

      # Apply offset + limit
      if (off > 0L) out <- if (length(out) > off) out[(off + 1L):length(out)] else character(0)
      if (length(out) > limit) out <- out[seq_len(limit)]
      if (length(out) == 0L) return("No matches found.")
      result <- paste(out, collapse = "\n")
      result <- truncate_tool_result(result, "Grep")
      n_hits <- length(out)
      .tool_result2(
        result,
        kind     = "text",
        icon     = "search",
        title    = sprintf("Grep <code>%s</code> (%d match%s)",
                           htmltools::htmlEscape(pattern), n_hits,
                           if (n_hits == 1L) "" else "es"),
        markdown = paste0("```\n", result, "\n```"),
        payload  = list(text = result)
      )
    },
    description = paste0(
      "Search file contents using a regex pattern (ripgrep if available). ",
      "Returns matching lines with file paths and line numbers."
    ),
    arguments = list(
      pattern     = ellmer::type_string(
        "Regular expression pattern to search for.", required = TRUE),
      path        = ellmer::type_string(
        "File or directory to search in.", required = FALSE),
      glob        = ellmer::type_string(
        "Glob pattern to filter files (e.g. '*.R').", required = FALSE),
      output_mode = ellmer::type_enum(
        values = c("content", "files_with_matches", "count"),
        description = "Output format.", required = FALSE),
      `-i`        = ellmer::type_boolean(
        "Case-insensitive search.", required = FALSE),
      `-n`        = ellmer::type_boolean(
        "Show line numbers (default TRUE).", required = FALSE),
      head_limit  = ellmer::type_number(
        "Max lines to return (default 250).", required = FALSE),
      offset      = ellmer::type_number(
        "Skip first N results.", required = FALSE),
      multiline   = ellmer::type_boolean(
        "Enable multiline matching.", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of what is being searched for.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "Grep",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# LS tool
# ---------------------------------------------------------------------------

#' Create the LS tool
#'
#' @return An `ellmer::tool()` object.
#' @export
ls_tool <- function() {
  ellmer::tool(
    name = "LS",
    fun = function(path = ".", ignore_patterns = NULL, `_intent` = NULL) {
      base <- normalizePath(path, mustWork = FALSE)
      if (!dir.exists(base))
        return(paste0("[Error] Directory not found: ", path))
      tryCatch({
        entries <- list.files(base, all.files = TRUE, no.. = TRUE,
                              include.dirs = TRUE)
        # Apply ignore patterns
        if (!is.null(ignore_patterns)) {
          for (pat in ignore_patterns)
            entries <- entries[!grepl(pat, entries)]
        }
        # Annotate directories
        annotated <- vapply(entries, function(e) {
          full <- file.path(base, e)
          if (dir.exists(full)) paste0(e, "/") else e
        }, character(1))
        result <- paste(annotated, collapse = "\n")
        result <- truncate_tool_result(result, "LS")
        n <- length(annotated)
        dname <- if (path == ".") "." else basename(path)
        .tool_result2(
          result,
          kind     = "text",
          icon     = "folder",
          title    = sprintf("LS <code>%s</code> (%d entr%s)",
                             htmltools::htmlEscape(dname), n,
                             if (n == 1L) "y" else "ies"),
          markdown = paste0("```\n", result, "\n```"),
          payload  = list(text = result)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = "List files and directories at a given path.",
    arguments   = list(
      path            = ellmer::type_string(
        "Directory path to list (default current directory).",
        required = FALSE),
      ignore_patterns = ellmer::type_array(
        items = ellmer::type_string(),
        description = "Regex patterns of entries to exclude.",
        required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of why this directory is being listed.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "LS",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Helper: register all builtin tools to a chat object
# ---------------------------------------------------------------------------

#' Register all built-in tools to an ellmer Chat object
#'
#' @param chat An `ellmer::Chat` object.
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL. Called when permission is `"ask"`.
#' @param skip_file_tools Logical. Skip Read/Write/Edit/MultiEdit/Glob/Grep/LS
#'   (register only Bash) when btw file tools handle files (Path A).
#' @param sandbox List or NULL. Bash sandbox profile (see [.sandbox_profile()]);
#'   passed through to [bash_tool()].
#' @return Invisibly returns `chat`.
