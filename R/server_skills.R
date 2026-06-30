#' @title Skills Server Logic
#' @name server_skills
#' @keywords internal
NULL

server_skills <- function(input, output, session, cwd, pinned_skills) {


  # Server file browser
  roots <- c(home = path.expand("~"), cwd = cwd)
  shinyFiles::shinyFileChoose(input, "ca_server_btn", roots = roots, session = session)
  shiny::observe({
    shiny::req(input$ca_server_btn)
    fi <- shinyFiles::parseFilePaths(roots, input$ca_server_btn)
    shiny::req(nrow(fi) > 0)
    current <- shiny::isolate(input$chat_user_input) %||% ""
    shinychat::update_chat_user_input(
      "chat",
      value   = paste0("[attached: ", fi$name[[1]], "] ", current),
      focus   = TRUE,
      submit  = FALSE,
      session = session
    )
  })

  # Reset picker to empty on session start (bootstrap-select selects first item)
  session$onFlushed(function() {
    shinyWidgets::updatePickerInput(session, "skill_picker", selected = character(0))
  }, once = TRUE)

  # Skill picker -> fill chat textarea
  shiny::observeEvent(input$skill_picker, ignoreInit = TRUE, {
    shiny::req(nzchar(input$skill_picker))
    shinychat::update_chat_user_input(
      "chat",
      value   = paste0("/", input$skill_picker, " "),
      focus   = TRUE,
      submit  = FALSE,
      session = session
    )
  })

  # Voice -> append to chat textarea
  shiny::observeEvent(input$ca_voice_text, {
    shiny::req(input$ca_voice_text$final)
    shiny::req(nzchar(input$ca_voice_text$text))
    current <- shiny::isolate(input$chat_user_input) %||% ""
    shinychat::update_chat_user_input(
      "chat",
      value   = trimws(paste(trimws(current), input$ca_voice_text$text)),
      focus   = TRUE,
      submit  = FALSE,
      session = session
    )
  })
}
