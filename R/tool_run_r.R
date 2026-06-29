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
#' @return An `ellmer::tool()` object, or `NULL` if btw is unavailable.
#' @export
run_r_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  if (!requireNamespace("btw", quietly = TRUE)) {
    warning("[codeagent] btw not available; RunR tool skipped.", call. = FALSE)
    return(NULL)
  }
  checker <- .make_permission_checker("RunR", mode, rules, ask_fn)

  ellmer::tool(
    fun = function(code, `_intent` = NULL) {
      if (!checker(list(code = code))) {
        return(.tool_result(
          paste0("[Permission denied] RunR:\n", code),
          title = "RunR — denied"
        ))
      }
      tryCatch(
        {
          raw <- btw::btw_tool_run_r(code = code, `_intent` = `_intent` %||% "")
          .runr_to_tool_result(raw, code)
        },
        error = function(e) {
          .tool_result(paste0("[Error] ", conditionMessage(e)),
                       title = "RunR — error")
        }
      )
    },
    name = "RunR",
    description = paste0(
      "Execute R code in the current R session and capture return values, ",
      "printed output, messages, warnings, errors, and plots. Execution stops ",
      "at the first error. Use for data inspection, quick computations, ",
      "plotting, and exercising package functions. ",
      "DANGER: code runs unsandboxed in the global environment and can read or ",
      "write files, access the network, and mutate state — every call is ",
      "permission-gated and may require user confirmation."
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

#' Register the RunR tool to a Chat
#'
#' @inheritParams run_r_tool
#' @param chat An `ellmer::Chat` object.
#' @return Invisibly returns `chat`.
#' @keywords internal
register_run_r_tool <- function(chat, mode = "default", rules = list(),
                                ask_fn = NULL) {
  t <- run_r_tool(mode, rules, ask_fn)
  if (!is.null(t)) chat$register_tool(t)
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Transform btw's BtwRunToolResult into codeagent's display contract.
#
# btw_tool_run_r() returns an S7 BtwRunToolResult whose @extra$contents holds a
# list of Content objects (ContentSource = the code, ContentOutput = printed
# output, ContentImageInline = base64 plots). btw's own @extra$display uses
# {open, copy_code} — NOT codeagent's {title, markdown, right_output}. Without
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
    # ContentSource (the echoed code) is skipped — already have `code`.
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

  # right_output: code + output + inline plot images for the Output panel
  img_tags <- lapply(images, function(im) {
    htmltools::tags$img(
      src   = paste0("data:", im$type, ";base64,", im$data),
      style = "max-width:100%; height:auto; margin-top:8px; border-radius:4px;"
    )
  })
  right_output <- htmltools::tagList(
    htmltools::tags$pre(
      style = "margin:0; font-size:0.75rem; overflow:auto;",
      htmltools::tags$code(class = "language-r", code)
    ),
    if (nzchar(output_text))
      htmltools::tags$pre(
        style = "margin:8px 0 0; font-size:0.75rem; overflow:auto;",
        output_text
      ),
    img_tags
  )

  title <- if (status == "success")
    "<span>Run R code</span>" else "RunR — error"

  .tool_result(
    value,
    title        = title,
    markdown     = markdown,
    right_output = right_output
  )
}

