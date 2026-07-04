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

  # Skill selection is now handled by shinychat's official slash-command
  # typeahead (type "/" in the chat input; see R/server_slash.R). The old
  # pickerInput-based selector was removed -- archived under
  # inst/experiments/pickerinput_skill_selector/.

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
