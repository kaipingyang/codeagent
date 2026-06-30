#' @title Built-in Tools
#' @description Core tool implementations for codeagent:
#'   Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS.
#'   Each tool is an `ellmer::tool()` object with permission-aware execution.
#' @name tools_builtin
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Tool factory helpers
# ---------------------------------------------------------------------------

# Wrap a tool result string in ContentToolResult with display metadata.
# title: HTML string shown in the shinychat tool card header.
# text:  plain-text value seen by the LLM.
# markdown: optional richer representation shown to the user.
# right_output: optional htmltools tag pushed to the right Output panel.
.tool_result <- function(text, title = NULL, markdown = NULL,
                          right_output = NULL) {
  display <- list()
  if (!is.null(title))        display$title        <- htmltools::HTML(title)
  if (!is.null(markdown))     display$markdown     <- markdown
  if (!is.null(right_output)) display$right_output <- right_output
  if (length(display) == 0L)  display <- NULL
  ellmer::ContentToolResult(
    value = text,
    extra = if (!is.null(display)) list(display = display) else list()
  )
}

# Build the on_request callback used inside tools
.make_permission_checker <- function(tool_name, mode, rules,
                                      ask_fn = NULL) {
  function(tool_input) {
    decision <- check_permission(tool_name, mode, rules, tool_input)
    if (decision == "allow") return(TRUE)
    if (decision == "deny")  return(FALSE)
    # decision == "ask": call ask_fn if provided
    if (!is.null(ask_fn)) return(isTRUE(ask_fn(tool_name, tool_input)))
    FALSE  # default deny if no ask_fn
  }
}

# ---------------------------------------------------------------------------
# Bash tool
# ---------------------------------------------------------------------------

#' Create the Bash tool
#'
#' @param mode Character. Permission mode (see [PermissionMode]).
#' @param rules List. [PermissionRule()] objects.
#' @param ask_fn Function or NULL. `function(tool_name, input) -> logical`.
#'   Called when permission is `"ask"`.
#' @return An `ellmer::tool()` object.
#' @export
bash_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("Bash", mode, rules, ask_fn)

  ellmer::tool(
    fun = function(command, timeout = .BASH_TIMEOUT_DEFAULT,
                   description = NULL, run_in_background = FALSE,
                   `_intent` = NULL) {
      if (!checker(list(command = command))) {
        return(.tool_result2(paste0("[Permission denied] Bash: ", command),
                             kind = "error", status = "denied",
                             icon = "terminal", title = "Bash -- denied",
                             payload = list(message = paste0("Permission denied: ", command))))
      }
      # Fire-and-forget: do not capture output, do not block.
      if (isTRUE(run_in_background)) {
        tmp <- tempfile(fileext = ".sh")
        writeLines(command, tmp)
        system2("bash", tmp, wait = FALSE, stdout = FALSE, stderr = FALSE)
        return(.tool_result2(paste0("[Background: command started]\nCommand: ", command),
                             kind = "text", icon = "terminal",
                             title = sprintf("Bash (bg) <code>%s</code>",
                                             substr(command, 1L, 60L)),
                             payload = list(text = command, lang = "sh")))
      }
      tryCatch({
        # Write command to temp file so shell quote nesting is never an issue
        tmp <- tempfile(fileext = ".sh")
        on.exit(unlink(tmp), add = TRUE)
        writeLines(command, tmp)
        out <- system2(
          "bash", tmp,
          stdout = TRUE, stderr = TRUE,
          timeout = as.numeric(timeout)
        )
        status <- attr(out, "status") %||% 0L
        result <- paste(out, collapse = "\n")
        if (!is.null(status) && status != 0L)
          result <- paste0(result, "\n[exit status: ", status, "]")
        result <- truncate_tool_result(result, "Bash")
        label  <- substr(command, 1L, 80L)
        if (nchar(command) > 80L) label <- paste0(label, "...")
        .tool_result2(result,
                      kind     = "text",
                      icon     = "terminal",
                      title    = sprintf("<code>%s</code>",
                                         htmltools::htmlEscape(label)),
                      markdown = sprintf("```sh\n%s\n```\n\n%s", command, result),
                      payload  = list(text = result, lang = "sh"))
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Execute a shell (bash) command. Use for file operations, running tests, ",
      "installing packages, git commands, etc. ",
      "Prefer over chained R calls when shell utilities are more appropriate. ",
      "NEVER use 'Rscript -e ...' to run R code -- shell quote nesting will always fail. ",
      "To run R code: ALWAYS use the Write tool to save code to /tmp/script.R first, ",
      "then run 'Rscript /tmp/script.R' with this tool."
    ),
    arguments = list(
      command     = ellmer::type_string(
        "The shell command to execute.", required = TRUE),
      timeout     = ellmer::type_number(
        "Timeout in seconds (default 30).", required = FALSE),
      description = ellmer::type_string(
        "Short description of what this command does (shown to user).",
        required = FALSE),
      run_in_background = ellmer::type_boolean(
        "Run in background (fire-and-forget).", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of why this command is being run.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Bash",
      read_only_hint   = FALSE,
      destructive_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Read tool
# ---------------------------------------------------------------------------

#' Create the Read tool
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @return An `ellmer::tool()` object.
#' @export
read_tool <- function(mode = "default", rules = list()) {
  ellmer::tool(
    fun = function(file_path, offset = NULL, limit = NULL, `_intent` = NULL) {
      r <- .safe_normalize_path(file_path)
      if (!is.null(r$error)) return(r$error)
      path <- r$path
      tryCatch({
        lines <- readLines(path, warn = FALSE)
        total <- length(lines)
        start <- if (!is.null(offset)) max(1L, as.integer(offset)) else 1L
        end   <- if (!is.null(limit))
          min(total, start + as.integer(limit) - 1L) else total
        if (start > end) return("")
        selected <- lines[start:end]
        numbered <- paste0(seq.int(start, end), "\t", selected)
        result   <- paste(numbered, collapse = "\n")
        result   <- truncate_tool_result(result, "Read")
        ext      <- tools::file_ext(path)
        fname    <- basename(path)
        range_str <- if (!is.null(offset) || !is.null(limit))
          sprintf(" (lines %d-%d)", start, end) else ""

        # right_output: code preview for the right panel
        .tool_result2(
          result,
          kind     = "code",
          icon     = "file-text",
          title    = sprintf("Read <code>%s</code>%s",
                             htmltools::htmlEscape(fname), range_str),
          markdown = sprintf("```%s\n%s\n```", ext, result),
          payload  = list(text = result,
                          lang = if (nzchar(ext)) ext else "text",
                          filename = fname)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Read the contents of a file. Returns lines with line numbers. ",
      "Use offset and limit to read specific sections of large files."
    ),
    arguments = list(
      file_path = ellmer::type_string(
        "Absolute or relative path to the file.", required = TRUE),
      offset    = ellmer::type_number(
        "Line number to start reading from (1-indexed).", required = FALSE),
      limit     = ellmer::type_number(
        "Maximum number of lines to return.", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of why this file is being read.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "Read",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Write tool
# ---------------------------------------------------------------------------

#' Create the Write tool
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return An `ellmer::tool()` object.
#' @export
write_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("Write", mode, rules, ask_fn)

  ellmer::tool(
    fun = function(file_path, content, `_intent` = NULL) {
      if (!checker(list(file_path = file_path))) {
        return(paste0("[Permission denied] Write: ", file_path))
      }
      tryCatch({
        dir.create(dirname(file_path), showWarnings = FALSE, recursive = TRUE)
        existed <- file.exists(file_path)
        writeLines(content, file_path)
        verb  <- if (existed) "Updated" else "Created"
        fname <- basename(file_path)
        .tool_result2(
          paste0(verb, ": ", file_path),
          kind    = "diff",
          icon    = if (existed) "pencil" else "file-earmark-plus",
          title   = sprintf("%s <code>%s</code>",
                            verb, htmltools::htmlEscape(fname)),
          payload = list(verb = verb, path = file_path, new = content)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Create or overwrite a file with the given content. ",
      "Prefer Edit for targeted changes to existing files."
    ),
    arguments = list(
      file_path = ellmer::type_string(
        "Path to the file to create or overwrite.", required = TRUE),
      content   = ellmer::type_string(
        "Full content to write to the file.", required = TRUE),
      `_intent` = ellmer::type_string(
        "Brief description of why this file is being written.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Write",
      read_only_hint   = FALSE,
      destructive_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Edit tool (exact string replacement)
# ---------------------------------------------------------------------------

#' Create the Edit tool
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return An `ellmer::tool()` object.
#' @export
edit_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("Edit", mode, rules, ask_fn)

  ellmer::tool(
    fun = function(file_path, old_string, new_string, replace_all = FALSE, `_intent` = NULL) {
      if (!checker(list(file_path = file_path))) {
        return(paste0("[Permission denied] Edit: ", file_path))
      }
      r <- .safe_normalize_path(file_path)
      if (!is.null(r$error)) return(r$error)
      path <- r$path
      tryCatch({
        content <- paste(readLines(path, warn = FALSE), collapse = "\n")
        # Uniqueness check (unless replace_all)
        if (!isTRUE(replace_all)) {
          m_list <- gregexpr(old_string, content, fixed = TRUE)[[1L]]
          count  <- if (length(m_list) == 1L && m_list[[1L]] == -1L) 0L
                    else length(m_list)
          if (count == 0L)
            return(paste0("[Error] old_string not found in ", file_path))
          if (count > 1L)
            return(paste0("[Error] old_string appears ", count,
                          " times \u2014 use replace_all=TRUE or provide more context."))
        }
        new_content <- if (isTRUE(replace_all))
          gsub(old_string, new_string, content, fixed = TRUE)
        else
          sub(old_string, new_string, content, fixed = TRUE)
        writeLines(new_content, path)
        .tool_result2(
          paste0("Edited: ", file_path),
          kind    = "diff",
          icon    = "pencil",
          title   = sprintf("Edit <code>%s</code>",
                            htmltools::htmlEscape(basename(file_path))),
          payload = list(verb = "Edited", path = file_path,
                         old = content, new = new_content)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Perform an exact string replacement in a file. ",
      "old_string must appear exactly once (unless replace_all=TRUE). ",
      "Provide enough context to make old_string unique."
    ),
    arguments = list(
      file_path   = ellmer::type_string(
        "Path to the file to edit.", required = TRUE),
      old_string  = ellmer::type_string(
        "Exact text to find and replace.", required = TRUE),
      new_string  = ellmer::type_string(
        "Replacement text.", required = TRUE),
      replace_all = ellmer::type_boolean(
        "Replace all occurrences (default FALSE).", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of what this edit achieves.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Edit",
      read_only_hint   = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# MultiEdit tool (batch edits in one file)
# ---------------------------------------------------------------------------

#' Create the MultiEdit tool
#'
#' Applies multiple `old_string -> new_string` replacements sequentially
#' to a single file in one call.
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return An `ellmer::tool()` object.
#' @export
multi_edit_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("MultiEdit", mode, rules, ask_fn)

  ellmer::tool(
    fun = function(file_path, edits, `_intent` = NULL) {
      if (!checker(list(file_path = file_path))) {
        return(paste0("[Permission denied] MultiEdit: ", file_path))
      }
      r <- .safe_normalize_path(file_path)
      if (!is.null(r$error)) return(r$error)
      path <- r$path
      tryCatch({
        content <- paste(readLines(path, warn = FALSE), collapse = "\n")
        orig_content <- content
        applied <- 0L
        for (edit in edits) {
          old <- edit[["old_string"]] %||% ""
          new <- edit[["new_string"]] %||% ""
          ra  <- isTRUE(edit[["replace_all"]])
          if (ra) {
            content <- gsub(old, new, content, fixed = TRUE)
          } else {
            ml  <- gregexpr(old, content, fixed = TRUE)[[1L]]
            cnt <- if (length(ml) == 1L && ml[[1L]] == -1L) 0L else length(ml)
            if (cnt != 1L) {
              return(paste0("[Error] Edit ", applied + 1L, ": old_string found ",
                            cnt, " times. Aborting."))
            }
            content <- sub(old, new, content, fixed = TRUE)
          }
          applied <- applied + 1L
        }
        writeLines(content, path)
        .tool_result2(
          paste0("Applied ", applied, " edit(s) to: ", file_path),
          kind    = "diff",
          icon    = "pencil-square",
          title   = sprintf("MultiEdit <code>%s</code> (%d edits)",
                            htmltools::htmlEscape(basename(file_path)), applied),
          payload = list(verb = sprintf("MultiEdit (%d)", applied),
                         path = file_path, old = orig_content, new = content)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Apply multiple string replacements to a single file in sequence. ",
      "Each edit is an object with old_string, new_string, and optional replace_all."
    ),
    arguments = list(
      file_path = ellmer::type_string(
        "Path to the file to edit.", required = TRUE),
      edits     = ellmer::type_array(
        items = ellmer::type_object(
          "A single edit operation.",
          old_string  = ellmer::type_string("Text to find.", required = TRUE),
          new_string  = ellmer::type_string("Replacement text.", required = TRUE),
          replace_all = ellmer::type_boolean(
            "Replace all occurrences.", required = FALSE)
        ),
        description = "Array of edit operations to apply in order."
      ),
      `_intent` = ellmer::type_string(
        "Brief description of what these edits achieve.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "MultiEdit",
      read_only_hint   = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# Glob tool
# ---------------------------------------------------------------------------

# Portable ** glob via list.files().
# Sys.glob("**/*.R") only works on Linux (glibc GLOB_STAR); silent on macOS/Windows.
# This helper provides a cross-platform fallback whenever the pattern contains **.
.glob_with_starstar <- function(base, pattern) {
  m         <- regexpr("\\*\\*", pattern, perl = TRUE)
  prefix    <- if (m > 1L) substr(pattern, 1L, m - 1L) else ""
  remainder <- substr(pattern, m[[1L]] + 2L, nchar(pattern))
  # Strip leading slash from the tail to get a file-level pattern.
  file_pat  <- sub("^[/\\\\]+", "", remainder)

  search_root <- normalizePath(
    if (nzchar(prefix))
      file.path(base, sub("[/\\\\]+$", "", prefix))
    else
      base,
    mustWork = FALSE
  )
  if (!dir.exists(search_root)) return(character(0))

  all_files <- list.files(search_root, recursive = TRUE, full.names = TRUE)
  if (length(all_files) == 0L || !nzchar(file_pat)) return(all_files)

  # When file_pat has no path separator, match only the filename portion.
  # When it does (e.g. "foo/*.R"), match the relative path.
  rx <- utils::glob2rx(file_pat)
  if (!grepl("[/\\\\]", file_pat, perl = TRUE)) {
    all_files[grepl(rx, basename(all_files))]
  } else {
    rel_paths <- substring(all_files, nchar(search_root) + 2L)
    all_files[grepl(rx, rel_paths)]
  }
}

#' Create the Glob tool
#'
#' @return An `ellmer::tool()` object.
#' @export
glob_tool <- function() {
  ellmer::tool(
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
#' @return Invisibly returns `chat`.
#' @export
register_builtin_tools <- function(chat, mode = "default",
                                    rules = list(), ask_fn = NULL,
                                    skip_file_tools = FALSE) {
  chat$register_tool(bash_tool(mode, rules, ask_fn))
  if (!isTRUE(skip_file_tools)) {
    chat$register_tool(read_tool(mode, rules))
    chat$register_tool(write_tool(mode, rules, ask_fn))
    chat$register_tool(edit_tool(mode, rules, ask_fn))
    chat$register_tool(multi_edit_tool(mode, rules, ask_fn))
    chat$register_tool(glob_tool())
    chat$register_tool(grep_tool())
    chat$register_tool(ls_tool())
  }
  invisible(chat)
}
