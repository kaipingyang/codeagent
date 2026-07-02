#' @title RStudio / Positron IDE Addins
#' @description Addins registered in `inst/rstudio/addins.dcf` for launching
#'   codeagent from RStudio or Positron via keyboard shortcut or Addins menu.
#'
#'   * `codeagent_addin()` -- opens the Shiny chat app.
#'   * `codeagent_addin_selection()` -- reads the current editor selection and
#'     sends it as context to the chat app.
#' @name addin
#' @keywords internal
NULL

#' Open the codeagent Shiny app from an IDE addin
#'
#' Registers as an RStudio/Positron addin. Builds a client from the user's
#' settings and launches `codeagent_app()`.  Optionally pre-fills the first
#' user message with any text currently selected in the source editor.
#'
#' @param selection Character or NULL. Pre-fill text. When NULL (default in the
#'   plain chat addin) the app opens with an empty input.
#' @return Invisibly NULL.
#' @export
codeagent_addin <- function(selection = NULL) {
  if (!requireNamespace("shiny", quietly = TRUE))
    cli::cli_abort("{.pkg shiny} is required for the codeagent addin.")

  # Build client from settings (same path as CLI)
  client <- tryCatch(
    codeagent_client(),
    error = function(e) {
      cli::cli_abort(c(
        "Could not build a codeagent client.",
        "i" = "Run {.fn use_codeagent_setup} to configure a provider.",
        "x" = conditionMessage(e)
      ))
    }
  )

  # If selection provided, inject it as an initial prompt hint
  greeting <- if (!is.null(selection) && nzchar(trimws(selection))) {
    paste0("I have selected the following code:\n\n```r\n",
           trimws(selection), "\n```\n\nHow can I help with this?")
  } else NULL

  codeagent_app(client, greeting = greeting)
  invisible(NULL)
}

#' Open codeagent with the current editor selection as context
#'
#' Reads the selected text in the active RStudio/Positron source editor and
#' opens `codeagent_app()` with that code pre-loaded as context.  Works in
#' both RStudio and Positron (both support `rstudioapi`).
#'
#' @return Invisibly NULL.
#' @export
codeagent_addin_selection <- function() {
  selection <- .get_editor_selection()
  codeagent_addin(selection = selection)
}

# ---------------------------------------------------------------------------
# Editor helpers
# ---------------------------------------------------------------------------

# Read the current selection from the active source editor.
# Returns NULL if rstudioapi is unavailable or no selection exists.
.get_editor_selection <- function() {
  if (!requireNamespace("rstudioapi", quietly = TRUE)) return(NULL)
  if (!rstudioapi::hasFun("getSourceEditorContext")) return(NULL)
  ctx <- tryCatch(rstudioapi::getSourceEditorContext(), error = function(e) NULL)
  if (is.null(ctx)) return(NULL)
  sel <- ctx$selection[[1L]]$text %||% ""
  if (!nzchar(trimws(sel))) NULL else sel
}

# Insert text at the cursor position in the active source editor.
# Used by future addin features (e.g. /inline-edit that patches the file).
.insert_at_cursor <- function(text) {
  if (!requireNamespace("rstudioapi", quietly = TRUE)) return(invisible(NULL))
  if (!rstudioapi::hasFun("insertText")) return(invisible(NULL))
  tryCatch(rstudioapi::insertText(text), error = function(e) NULL)
  invisible(NULL)
}
