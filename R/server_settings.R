#' @title Settings Server Logic
#' @name server_settings
#' @keywords internal
NULL

server_settings <- function(input, output, session, chat, settings, cwd, hooks = NULL) {

  # Live Customizations counts (Copilot style)
  output$customizations_counts <- shiny::renderUI({
    n_skills <- tryCatch(length(list_skills_meta(cwd)), error = function(e) 0L)
    n_hooks  <- if (!is.null(hooks)) tryCatch(hooks$count(), error = function(e) 0L) else 0L
    n_tools  <- tryCatch(length(chat$get_tools()), error = function(e) 0L)

    make_row <- function(icon, label, count = NULL) {
      htmltools::tags$div(
        class = "custom-item",
        style = "padding:3px 0; display:flex; align-items:center; gap:7px; cursor:pointer;",
        htmltools::tags$span(class = "ci-icon", icon),
        htmltools::tags$span(class = "ci-label", style = "flex:1; font-size:0.78rem;", label),
        if (!is.null(count) && count > 0L)
          htmltools::tags$span(
            class = "ci-count",
            style = "font-size:0.7rem; background:var(--ca-btn-bg); border-radius:3px; padding:0 4px; color:var(--ca-text-muted);",
            count
          )
      )
    }

    htmltools::tags$div(
      class = "ca-customizations",
      make_row("✨", "Skills",  n_skills),
      make_row("🔧", "Tools",   n_tools),
      make_row("🪝", "Hooks",   n_hooks),
      make_row("🔌", "MCP",     NULL)
    )
  })

  shiny::observeEvent(input$perm_mode, {
    settings$permission_mode <<- input$perm_mode
    tryCatch(.register_all_tools(chat, settings), error = function(e) NULL)
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$btw_groups_input, {
    tryCatch(
      register_r_tools(chat, groups = input$btw_groups_input),
      error = function(e) NULL)
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$theme_select, {
    shiny::showNotification(
      paste0("Theme change to '", input$theme_select, "' requires app relaunch."),
      type = "message",
      duration = 4
    )
  }, ignoreInit = TRUE)
}
