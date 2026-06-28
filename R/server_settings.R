#' @title Settings Server Logic
#' @name server_settings
#' @keywords internal
NULL

server_settings <- function(input, output, session, chat, settings) {

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
    session$sendCustomMessage("set_theme", list(theme = input$theme_select))
  }, ignoreInit = TRUE)
}
