# ---------------------------------------------------------------------------
# Skin switch for a host app
# ---------------------------------------------------------------------------
# The user switches the page's look (e.g. the default Bootstrap look and the
# DSH look of codeagent_theme("dsh")) while the session runs: the chat,
# the workspace tabs and everything else stay; only the theme's CSS is swapped
# (bslib's session$setCurrentTheme()). The page structure does not change.

#' Skin switch for a host app
#'
#' A small radio group the user switches the page's theme with. Pass the same
#' names to [codeagent_server()]'s `themes`. The page must be built with a
#' bslib theme (`bslib::bs_theme()`, [codeagent_theme()]) for its theme to be
#' swapped. Only one per page.
#'
#' @param themes Named character vector: label -> theme name (a name of
#'   `codeagent_server(themes =)`), e.g. `c(Default = "default", DSH = "dsh")`.
#' @param selected The theme selected at start (default: the first) -- the one
#'   the page was built with.
#' @param label Optional label shown before the choices.
#' @return A Shiny tag.
#' @seealso [codeagent_server()], [codeagent_theme()]
#' @export
codeagent_theme_ui <- function(themes = c(Default = "default", DSH = "dsh"),
                               selected = NULL, label = NULL) {
  if (!is.character(themes) || !length(themes) || is.null(names(themes)) ||
      any(!nzchar(names(themes))) || anyDuplicated(themes))
    stop("`themes` must be a named character vector: label -> theme name.", call. = FALSE)
  htmltools::div(class = "ca-theme-switch small",
    shiny::radioButtons("ca_theme", label, choices = themes,
                        selected = selected %||% unname(themes[[1L]]), inline = TRUE))
}

# `themes`: named list, theme name -> a bslib theme or a codeagent_theme()
# style name. PURE (validation only).
.check_host_themes <- function(themes) {
  if (!is.list(themes) || !length(themes) || is.null(names(themes)) || any(!nzchar(names(themes))))
    stop("`themes` must be a named list: theme name -> bslib theme or codeagent_theme() style.", call. = FALSE)
  for (nm in names(themes)) {
    th <- themes[[nm]]
    if (!(inherits(th, "bs_theme") || (is.character(th) && length(th) == 1L)))
      stop("`themes$", nm, "` must be a bslib theme or a codeagent_theme() style name.", call. = FALSE)
  }
  invisible(TRUE)
}

.resolve_host_theme <- function(th) if (inherits(th, "bs_theme")) th else codeagent_theme(th)

# The page's theme follows the host's skin switch.
.serve_host_themes <- function(input, session, themes, on_theme = NULL) {
  resolved <- list()     # compiled once per theme and session
  shiny::observeEvent(input$ca_theme, ignoreInit = TRUE, {
    new <- input$ca_theme
    if (!is.character(new) || length(new) != 1L || !new %in% names(themes)) return()
    if (is.null(resolved[[new]])) resolved[[new]] <<- .resolve_host_theme(themes[[new]])
    ok <- tryCatch({ session$setCurrentTheme(resolved[[new]]); TRUE }, error = function(e) {
      .ui_toast(paste("The style could not be changed:", conditionMessage(e)), "warning"); FALSE })
    if (isTRUE(ok) && is.function(on_theme)) tryCatch(on_theme(new), error = function(e) NULL)
  })
}
