#' @title Chat Server Logic
#' @description Streaming task, ESC interrupt, tool result push.
#' @name server_chat
#' @keywords internal
NULL

server_chat <- function(input, output, session, chat, settings,
                         state, cwd) {

  # Tool result store (button_id → ContentToolResult)
  tool_results <- new.env(hash = TRUE, parent = emptyenv())

  # Stream controller for cancellation (ESC / stop button)
  stream_ctrl <- tryCatch(ellmer::stream_controller(), error = function(e) NULL)

  # Push a tool result into the right Output panel via the typed dispatcher.
  # Returns the (possibly adapted) result so callers can store it.
  .push_output <- function(result, immediate = TRUE) {
    display <- tryCatch(result@extra$display, error = function(e) NULL)
    title   <- tryCatch(
      gsub("<[^>]+>", "", as.character(display$title %||% display$toolcard$title %||% "Output")),
      error = function(e) "Output"
    )
    content <- tryCatch(render_tool_output(display), error = function(e) NULL)
    if (is.null(content)) return(invisible(result))

    # Two-phase: instant raw-HTML push before stream finishes, then renderUI.
    if (isTRUE(immediate)) {
      html <- tryCatch(
        as.character(htmltools::tags$div(class = "ca-output-content p-2", content)),
        error = function(e) NULL
      )
      if (!is.null(html))
        session$sendCustomMessage("show_ca_immediate", list(html = html))
    }
    state$main_output <- list(title = title, content = content)
    shiny::updateTabsetPanel(session, "main_tab", selected = "output")
    invisible(result)
  }

  # on_tool_result: fires immediately when tool completes (before stream ends)
  # Adapts any result (raw btw included) into the typed contract, then pushes.
  chat$on_tool_result(function(result) {
    result <- tryCatch(.adapt_tool_result(result), error = function(e) result)

    button_id <- tryCatch(result@extra$display$button_id, error = function(e) NULL)
    if (is.null(button_id)) {
      tool_name <- tryCatch(result@request@name %||% "tool", error = function(e) "tool")
      button_id <- paste0(tool_name, "_", format(Sys.time(), "%H%M%S"))
    }

    tool_results[[button_id]] <- result
    .push_output(result, immediate = TRUE)

    # Bind tool card click → select this result
    session$sendCustomMessage("bind_tool_card",
                              list(button_id = button_id))
  })

  # Tool card click → re-render stored result
  shiny::observeEvent(input$select_tool_output, {
    bid    <- input$select_tool_output
    result <- tool_results[[bid]]
    if (is.null(result)) return()
    # Re-render stored result into the Output panel (no instant push on replay).
    .push_output(result, immediate = FALSE)
  })

  # ------------------------------------------------------------------
  # Streaming task (ExtendedTask + coro::async)
  # ------------------------------------------------------------------
    stream_task <- shiny::ExtendedTask$new(function(user_input) {
    parsed <- .preprocess_input(user_input, cwd)
    actual_input <- if (identical(parsed$type, "skill"))
      tryCatch(load_skill_prompt(parsed$name, parsed$args, cwd),
               error = function(e) user_input)
    else user_input

    shiny::isolate(state$compaction_ctrl$maybe_compact(
      chat,
      settings$model_limit %||% 200000L
    ))
    shiny::isolate(state$resource_state$maybe_replace(chat))

    coro::async(function() {
      if (!is.null(stream_ctrl)) stream_ctrl$reset()
      stream <- chat$stream_async(actual_input, stream = "content",
                                  controller = stream_ctrl)
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

      "done"
    })()
  })

  shiny::observeEvent(input$chat_user_input, {
    if (stream_task$status() == "running") return()
    state$interrupt <- FALSE
    stream_task$invoke(input$chat_user_input)
  })

  shiny::observeEvent(input$esc, {
    if (stream_task$status() == "running") {
      state$interrupt <- TRUE
      if (!is.null(stream_ctrl)) stream_ctrl$cancel()
    }
  })

  # shinychat built-in stop button (enable_cancel = TRUE) sends input$chat_cancel
  shiny::observeEvent(input$chat_cancel, {
    if (stream_task$status() == "running") {
      state$interrupt <- TRUE
      if (!is.null(stream_ctrl)) stream_ctrl$cancel()
    }
  })

  # renderUI for main_output (two-phase: immediate + full)
  output$main_output <- shiny::renderUI({
    val <- state$main_output
    if (is.null(val)) {
      return(htmltools::tags$p(
        style = "color:var(--bs-secondary-color, #6c757d); padding:24px; text-align:center;",
        "Tool output will appear here."
      ))
    }
    # Wrap in a bslib card(full_screen=TRUE) so the Output panel gets the same
    # expand-to-fullscreen affordance as the in-chat tool card.
    bslib::card(
      full_screen = TRUE,
      class       = "toolcard-output-card",
      bslib::card_header(
        class = "ca-output-title",
        style = "font-size:0.8rem; font-weight:600;",
        val$title
      ),
      bslib::card_body(
        class   = "ca-output-body",
        padding = 8,
        val$content
      )
    )
  })

  invisible(stream_task)
}
