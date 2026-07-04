#' @title Run R Code Tool (permission-gated)
#' @description Wraps [btw::btw_tool_run_r()] behind codeagent's permission gate.
#'   Executing arbitrary R code is dangerous (no sandbox, runs in the global
#'   environment), so this tool is treated like Bash: `destructive_hint = TRUE`,
#'   never read-only, and every call must be confirmed via `ask_fn` in `default`
#'   mode (or a permission rule / `bypass`).
#' @name tool_run_r
#' @keywords internal
NULL

#' Create the RunR tool
#'
#' Runs R code in the current session and captures return values, printed
#' output, messages, warnings, errors, and plots. Because arbitrary R execution
#' can read/write files, hit the network, or mutate global state, the call is
#' gated through [check_permission()] under the tool name `"RunR"`.
#'
#' @param mode Character. Permission mode (see [PermissionMode]).
#' @param rules List. [PermissionRule()] objects.
#' @param ask_fn Function or NULL. `function(tool_name, input) -> logical`.
#'   Called when permission resolves to `"ask"`.
#' @param sandbox List or NULL. Sandbox profile (see [.sandbox_profile()]). RunR
#'   runs in-process so the environment cannot be scrubbed, but when the sandbox
#'   is enabled, code calling shell/process/env or (when network is disabled)
#'   network functions is refused.
#' @return An `ellmer::tool()` object, or `NULL` if btw is unavailable.
#' @export
run_r_tool <- function(mode = "default", rules = list(), ask_fn = NULL,
                       sandbox = NULL) {
  if (!requireNamespace("btw", quietly = TRUE)) {
    warning("[codeagent] btw not available; RunR tool skipped.", call. = FALSE)
    return(NULL)
  }
  checker <- .make_permission_checker("RunR", mode, rules, ask_fn)
  sb_prof <- .sandbox_profile(list(sandbox = sandbox))

  ellmer::tool(
    fun = function(code, `_intent` = NULL) {
      if (!checker(list(code = code))) {
        ellmer::tool_reject(paste0("Permission denied for RunR. Code:\n", code))
      }
      # Sandbox: two levels.
      #  (a) Always: refuse obvious shell/env patterns (cheap first line).
      #  (b) If sandbox enabled + callr available: execute in a SEPARATE R
      #      process with a scrubbed environment (real isolation -- the child
      #      cannot see this process's API keys) and a wall-clock timeout.
      #      This is the true isolation the in-process regex cannot provide.
      blocked <- .sandbox_block_r_code(code, sb_prof)
      if (!is.null(blocked)) {
        ellmer::tool_reject(paste0("Sandbox blocked: ", blocked))
      }
      if (isTRUE(sb_prof$enabled) && requireNamespace("callr", quietly = TRUE)) {
        return(.runr_sandboxed_exec(code, sb_prof))
      }
      tryCatch(
        {
          raw <- btw::btw_tool_run_r(code = code, `_intent` = `_intent` %||% "")
          .runr_to_tool_result(raw, code)
        },
        error = function(e) {
          .tool_result(paste0("[Error] ", conditionMessage(e)),
                       title = "RunR -- error")
        }
      )
    },
    name = "RunR",
    description = paste0(
      "Execute R code in the current R session and capture return values, ",
      "printed output, messages, warnings, errors, and plots. Execution stops ",
      "at the first error. Use for data inspection, quick computations, ",
      "plotting, and exercising package functions. ",
      "When sandboxing is enabled, code runs in an isolated subprocess with a ",
      "scrubbed environment (no API keys visible) and a timeout; otherwise it ",
      "runs in-process and is permission-gated (may require user confirmation)."
    ),
    arguments = list(
      code = ellmer::type_string(
        "The R code to run.", required = TRUE),
      `_intent` = ellmer::type_string(
        "Brief description of why this code is being run.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Run R code",
      read_only_hint   = FALSE,
      destructive_hint = TRUE,
      open_world_hint  = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Sandboxed RunR execution via a separate R process (callr)
# ---------------------------------------------------------------------------

# Run R code in a fresh callr subprocess with a scrubbed environment and a
# wall-clock timeout. Unlike the in-process path, the child cannot read this
# process's environment variables (API keys), so a scrubbed env is real -- and
# a runaway loop is killed at the timeout. Returns a codeagent tool result.
.runr_sandboxed_exec <- function(code, profile, timeout = 30) {
  keep <- profile$keep_env %||% c("PATH", "HOME", "LANG", "LC_ALL", "TMPDIR")
  vals <- Sys.getenv(keep, unset = NA)
  child_env <- vals[!is.na(vals)]
  # callr merges with Sys.getenv unless we explicitly blank the rest; setting
  # only kept vars plus scrubbing common secret vars keeps the child clean.
  secret_like <- c("CODEAGENT_API_KEY", "ANTHROPIC_API_KEY", "OPENAI_API_KEY",
                   "AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "GITHUB_PAT",
                   "GITHUB_TOKEN", "DATABRICKS_TOKEN")
  scrub <- stats::setNames(rep("", length(secret_like)), secret_like)
  # CRITICAL: blank R_ENVIRON_USER / R_ENVIRON so the child does NOT re-source
  # the user's .Renviron (which would repopulate the very secrets we scrub).
  no_renviron <- c(R_ENVIRON_USER = "", R_ENVIRON = "")
  env <- c(child_env, scrub, no_renviron)

  plot_file <- tempfile(fileext = ".png")
  on.exit(unlink(plot_file), add = TRUE)

  runner <- function(user_code, plot_path) {
    grDevices::png(plot_path, width = 800, height = 600)
    on.exit(grDevices::dev.off(), add = TRUE)
    out <- utils::capture.output({
      val <- eval(parse(text = user_code), envir = new.env())
      if (!is.null(val) && !inherits(val, "ggplot")) print(val)
      if (inherits(val, "ggplot")) print(val)
    })
    paste(out, collapse = "\n")
  }

  res <- tryCatch(
    callr::r(runner, args = list(user_code = code, plot_path = plot_file),
             env = env, timeout = timeout, show = FALSE),
    error = function(e) structure(conditionMessage(e), class = "runr_error"))

  if (inherits(res, "runr_error")) {
    msg <- as.character(res)
    if (grepl("timed out|timeout", msg, ignore.case = TRUE))
      msg <- paste0("execution timed out after ", timeout, "s")
    return(.tool_result(
      paste0("[Sandbox RunR error] ", msg),
      title = "RunR (sandboxed) -- error"))
  }

  text <- if (is.character(res) && nzchar(res)) res else "(no output)"
  # Attach the plot if one was drawn (non-trivial file size).
  has_plot <- file.exists(plot_file) && file.info(plot_file)$size > 1000
  md <- paste0("```r\n", code, "\n```\n\n```\n", text, "\n```")
  if (has_plot) {
    b64 <- base64enc::base64encode(plot_file)
    md  <- paste0(md, "\n\n![plot](data:image/png;base64,", b64, ")")
  }
  .tool_result(text, title = "RunR (sandboxed)", markdown = md)
}

#' Register the RunR tool to a Chat
#'
#' @inheritParams run_r_tool
#' @param chat An `ellmer::Chat` object.
#' @return Invisibly returns `chat`.
#' @keywords internal
register_run_r_tool <- function(chat, mode = "default", rules = list(),
                                ask_fn = NULL, sandbox = NULL, async = FALSE) {
  if (isTRUE(async)) {
    # Shiny path: bypass-built inner + async permission gate (see
    # .asyncify_gated_tool). RunR is destructive/never read-only, so in default
    # mode this shows the approval bar before executing.
    inner <- run_r_tool("bypass", rules, NULL, sandbox = sandbox)
    if (!is.null(inner))
      chat$register_tool(.asyncify_gated_tool(inner, "RunR", mode, rules, ask_fn))
    return(invisible(chat))
  }
  t <- run_r_tool(mode, rules, ask_fn, sandbox = sandbox)
  if (!is.null(t)) chat$register_tool(t)
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Transform btw's BtwRunToolResult into codeagent's display contract.
#
# btw_tool_run_r() returns an S7 BtwRunToolResult whose @extra$contents holds a
# list of Content objects (ContentSource = the code, ContentOutput = printed
# output, ContentImageInline = base64 plots). btw's own @extra$display uses
# {open, copy_code} -- NOT codeagent's {title, markdown, right_output}. Without
# translation the right-panel push and plot rendering both fail.
# ---------------------------------------------------------------------------

.runr_to_tool_result <- function(raw, code) {
  contents <- tryCatch(raw@extra$contents, error = function(e) NULL)
  status   <- tryCatch(raw@extra$status   %||% "success", error = function(e) "success")

  text_parts <- character(0)
  images     <- list()

  for (ct in (contents %||% list())) {
    cls <- class(ct)[1]
    if (grepl("ContentImageInline", cls, fixed = TRUE)) {
      images[[length(images) + 1L]] <- list(
        type = tryCatch(ct@type, error = function(e) "image/png"),
        data = tryCatch(ct@data, error = function(e) "")
      )
    } else if (grepl("ContentOutput", cls, fixed = TRUE)) {
      txt <- tryCatch(ct@text, error = function(e) "")
      if (nzchar(txt)) text_parts <- c(text_parts, txt)
    } else if (grepl("ContentError", cls, fixed = TRUE)) {
      txt <- tryCatch(ct@text, error = function(e) "")
      if (nzchar(txt)) text_parts <- c(text_parts, paste0("Error: ", txt))
    } else if (grepl("ContentWarning|ContentMessage", cls)) {
      txt <- tryCatch(ct@text, error = function(e) "")
      if (nzchar(txt)) text_parts <- c(text_parts, txt)
    }
    # ContentSource (the echoed code) is skipped -- already have `code`.
  }

  output_text <- paste(text_parts, collapse = "\n")

  # LLM-facing value: printed output (+ note about plots)
  value <- output_text
  if (length(images) > 0L) {
    plot_note <- sprintf("[%d plot(s) generated]", length(images))
    value <- if (nzchar(value)) paste0(value, "\n", plot_note) else plot_note
  }
  if (!nzchar(value)) value <- "[no output]"

  # Human markdown preview: code + output
  markdown <- sprintf("```r\n%s\n```", code)
  if (nzchar(output_text))
    markdown <- paste0(markdown, "\n\n```\n", output_text, "\n```")

  # Typed payload: image kind when plots present, else code kind.
  imgs <- lapply(images, function(im)
    list(mime = im$type, b64 = im$data))

  if (length(imgs) > 0L) {
    .tool_result2(
      value,
      kind     = "image",
      status   = if (status == "success") "success" else "error",
      icon     = "play-circle",
      title    = if (status == "success") "Run R code" else "RunR - error",
      markdown = markdown,
      payload  = list(images = imgs, code = code, output = output_text)
    )
  } else {
    .tool_result2(
      value,
      kind     = if (status == "success") "code" else "error",
      status   = if (status == "success") "success" else "error",
      icon     = "play-circle",
      title    = if (status == "success") "Run R code" else "RunR - error",
      markdown = markdown,
      payload  = if (status == "success")
        list(text = code, lang = "r", output = output_text)
      else
        list(message = output_text)
    )
  }
}


