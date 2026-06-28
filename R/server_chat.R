#' @title Chat Server Logic
#' @description Streaming task, ESC interrupt, tool result push.
#' @name server_chat
#' @keywords internal
NULL

server_chat <- function(input, output, session, chat, settings,
                         state, cwd) {

  # ------------------------------------------------------------------
  # Streaming task (ExtendedTask + coro::async)
  # ------------------------------------------------------------------
  stream_task <- shiny::ExtendedTask$new(function(user_input) {
    parsed <- .preprocess_input(user_input, cwd)
    actual_input <- if (identical(parsed$type, "skill"))
      tryCatch(load_skill_prompt(parsed$name, parsed$args, cwd),
               error = function(e) user_input)
    else user_input

    compaction_ctrl <- state$compaction_ctrl
    resource_state  <- state$resource_state

    compaction_ctrl$maybe_compact(chat, settings$model_limit %||% 200000L)
    resource_state$maybe_replace(chat)

    coro::async(function() {
      stream <- chat$stream_async(actual_input, stream = "content")
      await(shinychat::chat_append("chat", stream, session = session))

      n_tokens    <- estimate_tokens(chat)
      model_limit <- settings$model_limit %||% 200000L
      pct         <- round(n_tokens / model_limit * 100)
      session$sendCustomMessage("update_budget", list(
        text = format(n_tokens, big.mark = ","),
        pct  = pct
      ))

      shiny::isolate(state$iteration <- state$iteration + 1L)

      sid <- shiny::isolate(state$session_id)
      if (!is.null(sid))
        tryCatch(save_session(chat, cwd, sid), error = function(e) NULL)

      # Push tool results to right panel
      turns <- tryCatch(chat$get_turns(), error = function(e) list())
      for (t in rev(turns)) {
        for (c in tryCatch(t@contents, error = function(e) list())) {
          if (S7::S7_inherits(c, ellmer::ContentToolResult)) {
            right_out <- tryCatch(c@extra$display$right_output, error = function(e) NULL)
            if (!is.null(right_out)) {
              title <- tryCatch(
                as.character(c@extra$display$title %||% "Output"),
                error = function(e) "Output"
              )
              state$main_output <- list(title = title, content = right_out)
              shiny::updateTabsetPanel(session, "main_tab", selected = "output")
            }
            # Immediate HTML push (two-phase display)
            html_raw <- tryCatch(c@extra$display$markdown, error = function(e) NULL)
            if (!is.null(html_raw)) {
              session$sendCustomMessage("show_ca_immediate", list(
                html = as.character(htmltools::tags$div(
                  class = "ca-output-content p-3",
                  htmltools::HTML(commonmark::markdown_html(html_raw))
                ))
              ))
            }
          }
        }
        break  # only process last assistant turn
      }

      "done"
    })()
  })

  shiny::observeEvent(input$chat_user_input, {
    if (stream_task$status() == "running") return()
    state$interrupt <- FALSE
    stream_task$invoke(input$chat_user_input)
  })

  shiny::observeEvent(input$esc, {
    if (stream_task$status() == "running") state$interrupt <- TRUE
  })

  # renderUI for main_output (two-phase: immediate + full)
  output$main_output <- shiny::renderUI({
    val <- state$main_output
    if (is.null(val)) {
      return(htmltools::tags$p(
        style = "color:var(--ca-text-muted); padding:24px; text-align:center;",
        "Tool output will appear here."
      ))
    }
    htmltools::tagList(
      htmltools::tags$div(
        class = "ca-output-title px-3 py-2",
        style = "font-size:0.8rem; font-weight:600; border-bottom:1px solid var(--ca-border);",
        val$title
      ),
      htmltools::tags$div(
        class = "ca-output-body p-2",
        style = "overflow:auto;",
        val$content
      )
    )
  })

  invisible(stream_task)
}
