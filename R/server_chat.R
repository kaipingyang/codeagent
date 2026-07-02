#' @title Chat Server Logic
#' @description Streaming task, ESC interrupt, tool result push.
#' @name server_chat
#' @keywords internal
NULL

server_chat <- function(input, output, session, chat, settings,
                         state, cwd) {

  # Tool result store (button_id -> ContentToolResult)
  tool_results <- new.env(hash = TRUE, parent = emptyenv())

  # Stream controller for cancellation (ESC / stop button)
  stream_ctrl <- tryCatch(ellmer::stream_controller(), error = function(e) NULL)

  # Send the slash-command list to the browser once on startup so the
  # autocomplete dropdown (agent.js) can filter candidates client-side.
  shiny::observe({
    # Local commands (always available, no args or fixed args)
    local_cmds <- list(
      list(name = "model",   description = "Switch model",        has_args = FALSE, type = "command"),
      list(name = "compact", description = "Compact context",     has_args = FALSE, type = "command"),
      list(name = "clear",   description = "Clear chat history",  has_args = FALSE, type = "command"),
      list(name = "rewind",  description = "Rewind N exchanges",  has_args = TRUE,  type = "command")
    )
    # Skills (loaded from disk; have args)
    skill_cmds <- tryCatch({
      metas <- list_skills_meta(cwd)
      lapply(names(metas), function(nm) {
        m <- metas[[nm]]
        list(name = nm,
             description = m$description %||% "",
             has_args = nzchar(m$argument_hint %||% ""),
             type = "skill")
      })
    }, error = function(e) list())
    all_cmds <- c(local_cmds, skill_cmds)
    session$sendCustomMessage("ca_slash_commands", all_cmds)
  }) |> shiny::bindEvent(session$clientData$url_hostname, once = TRUE)

  # ca_slash_select: JS dropdown picked a command; fill and optionally submit.
  shiny::observeEvent(input$ca_slash_select, {
    sel <- input$ca_slash_select
    val    <- sel$value  %||% ""
    submit <- isTRUE(sel$submit)
    focus  <- isTRUE(sel$focus)
    tryCatch(
      shinychat::update_chat_user_input("chat", value = val,
                                        submit = submit, focus = focus,
                                        session = session),
      error = function(e) NULL)
  })

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

    # Bind tool card click -> select this result
    session$sendCustomMessage("bind_tool_card",
                              list(button_id = button_id))
  })

  # Tool card click -> re-render stored result
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
    else user_input  # "normal" or anything else -> send as-is

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

      # Auto-save every turn (session_id is always set from startup).
      sid <- shiny::isolate(state$session_id)
      tryCatch(save_session(chat, cwd, sid), error = function(e) NULL)

      "done"
    })()
  })

  shiny::observeEvent(input$chat_user_input, {
    if (stream_task$status() == "running") return()
    state$interrupt <- FALSE

    # Pre-process: local commands are handled here (not sent to LLM).
    parsed <- tryCatch(.preprocess_input(input$chat_user_input, cwd),
                       error = function(e) list(type = "normal"))

    if (identical(parsed$type, "command")) {
      .handle_chat_command(parsed, chat, settings, state, session, cwd)
      return()
    }

    stream_task$invoke(input$chat_user_input)
  })

  shiny::observeEvent(input$esc, {
    if (stream_task$status() == "running") {
      state$interrupt <- TRUE
      if (!is.null(stream_ctrl)) stream_ctrl$cancel()
      tryCatch(.patch_interrupted_chat(chat), error = function(e) NULL)
    }
  })

  # shinychat built-in stop button (enable_cancel = TRUE) sends input$chat_cancel
  shiny::observeEvent(input$chat_cancel, {
    if (stream_task$status() == "running") {
      state$interrupt <- TRUE
      if (!is.null(stream_ctrl)) stream_ctrl$cancel()
      tryCatch(.patch_interrupted_chat(chat), error = function(e) NULL)
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

  # /model modal confirm: fires from a plain observer (not async) -- safe.
  # Reuses the same .resolve_model_chat + .swap_provider path as Settings picker.
  shiny::observeEvent(input$ca_model_pick_confirm, {
    shiny::removeModal()
    new_spec <- input$ca_model_pick %||% ""
    if (!nzchar(new_spec)) return()
    new_chat <- tryCatch(
      codeagent:::.resolve_model_chat(new_spec, cwd),
      error = function(e) NULL)
    if (!is.null(new_chat) && .swap_provider(chat, new_chat)) {
      new_model <- tryCatch(chat$get_model(), error = function(e) new_spec)
      state$settings_changed <- state$settings_changed + 1L
      .ui_toast(sprintf("Switched to %s -- history preserved.", new_model), "success")
    } else {
      .ui_toast(paste0("Could not switch to ", new_spec), "warning")
    }
  })

  invisible(stream_task)
}

# ---------------------------------------------------------------------------
# Local command handler (Shiny equivalent of REPL meta-commands)
# ---------------------------------------------------------------------------

# Execute a local command parsed by .preprocess_input(type="command").
# Mirrors the REPL's built-in command switch so both UIs behave identically.
# Appends a feedback message to the chat so the user sees the result inline.
.handle_chat_command <- function(parsed, chat, settings, state, session, cwd) {
  name <- parsed$name %||% ""
  args <- parsed$args %||% ""

  feedback <- switch(name,

    model = {
      cur   <- tryCatch(chat$get_model(), error = function(e) settings$model %||% "?")
      tiers <- settings$tier_models %||% list()
      if (!nzchar(args)) {
        # No arg: open modal picker.
        # Labels show "tier (endpoint)" so user knows what they're picking.
        if (length(tiers)) {
          choices <- stats::setNames(
            unlist(tiers),
            vapply(names(tiers), function(nm)
              sprintf("%s  (%s)", nm, tiers[[nm]]), character(1)))
        } else {
          choices <- stats::setNames(cur, cur)
        }
        shiny::showModal(shiny::modalDialog(
          title = "Switch model",
          shiny::radioButtons("ca_model_pick", NULL,
            choices  = choices,
            selected = if (cur %in% unlist(tiers)) cur else unlist(tiers)[1L] %||% cur),
          footer = shiny::tagList(
            shiny::modalButton("Cancel"),
            shiny::actionButton("ca_model_pick_confirm", "Switch",
                                class = "btn-primary")
          ),
          easyClose = TRUE
        ))
        # CRITICAL: shinychat shows a pending bubble + disables input whenever
        # a user message is submitted (JS-side, before the server responds).
        # For local commands we must send a chat_append_message to clear it --
        # "message" action is the only thing that sets inputDisabled=false.
        sprintf("**/model** -- pick a model in the popup to switch.")
      } else {
        new_chat <- tryCatch(
          codeagent:::.resolve_model_chat(args, cwd),
          error = function(e) NULL)
        if (!is.null(new_chat) && .swap_provider(chat, new_chat)) {
          new_model <- tryCatch(chat$get_model(), error = function(e) args)
          state$settings_changed <- state$settings_changed + 1L
          paste0("OK Switched to `", new_model, "`")
        } else {
          paste0("ERR Could not switch to `", args, "` -- check the model spec.")
        }
      }
    },

    compact = {
      tryCatch({
        full_compact(chat)
        "OK Context compacted."
      }, error = function(e) paste0("ERR Compact failed: ", conditionMessage(e)))
    },

    clear = {
      tryCatch(chat$set_turns(list()), error = function(e) NULL)
      "OK History cleared."
    },

    rewind = {
      n_back <- suppressWarnings(as.integer(args))
      if (is.na(n_back) || n_back < 1L) n_back <- 1L
      cur  <- length(tryCatch(chat$get_turns(), error = function(e) list()))
      keep <- max(0L, cur - 2L * n_back)
      kept <- tryCatch(truncate_chat_turns(chat, keep), error = function(e) cur)
      sprintf("<<< Rewound %d exchange(s); %d turns kept.", n_back, kept)
    },

    # Unknown local command -- show help
    paste0("Unknown command: `/", name, "`.\n\n",
           "Built-in commands: `/model`, `/compact`, `/clear`, `/rewind [N]`")
  )

  # Append feedback to chat (NULL means the command handled its own UI, e.g. modal).
  if (!is.null(feedback) && nzchar(feedback)) {
    tryCatch(
      shinychat::chat_append("chat",
        ellmer::Turn("assistant", list(ellmer::ContentText(feedback))),
        session = session),
      error = function(e) NULL)
  }

  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Interrupted chat repair  (ported from side::patch_interrupted_chat)
# ---------------------------------------------------------------------------

# When streaming is cancelled, a ContentToolRequest may exist in the turns
# without a matching ContentToolResult. This leaves the chat in an invalid
# state -- the next API call will error because the model expects results for
# every request it issued. Replace orphaned requests with a ContentText
# explaining the interruption so the conversation can continue cleanly.
.patch_interrupted_chat <- function(chat) {
  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  if (!length(turns)) return(invisible(NULL))

  request_ids <- character(0)
  result_ids  <- character(0)
  for (turn in turns) {
    contents <- tryCatch(turn@contents, error = function(e) list())
    for (ct in contents) {
      cls <- class(ct)[1L]
      if (grepl("ContentToolRequest", cls, fixed = FALSE))
        request_ids <- c(request_ids, tryCatch(ct@id, error = function(e) ""))
      if (grepl("ContentToolResult", cls, fixed = FALSE))
        result_ids <- c(result_ids,
          tryCatch(ct@request@id, error = function(e) ""))
    }
  }
  orphan_ids <- request_ids[!request_ids %in% result_ids]
  if (!length(orphan_ids)) return(invisible(NULL))

  new_turns <- lapply(turns, function(turn) {
    contents <- tryCatch(turn@contents, error = function(e) list())
    new_contents <- lapply(contents, function(ct) {
      cls <- class(ct)[1L]
      if (!grepl("ContentToolRequest", cls, fixed = FALSE)) return(ct)
      id <- tryCatch(ct@id, error = function(e) "")
      if (!id %in% orphan_ids) return(ct)
      name <- tryCatch(ct@name, error = function(e) "tool")
      ellmer::ContentText(paste0("_Tool call to `", name, "` interrupted._"))
    })
    tryCatch(turn@contents <- new_contents, error = function(e) NULL)
    turn
  })
  tryCatch(chat$set_turns(new_turns), error = function(e) NULL)
  invisible(NULL)
}
