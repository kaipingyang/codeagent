#' @title Chat Server Logic
#' @description Streaming task, ESC interrupt, tool result push.
#' @name server_chat
#' @keywords internal
NULL

server_chat <- function(input, output, session, chat, settings,
                         state, cwd, chat_server_mod = NULL) {

  # Tool result store (button_id -> ContentToolResult)
  tool_results <- new.env(hash = TRUE, parent = emptyenv())

  # Stream controller for cancellation (ESC / stop button)
  stream_ctrl <- tryCatch(ellmer::stream_controller(), error = function(e) NULL)

  # Register slash commands via shinychat's native $slash_command() API.
  # This replaces the old ca_slash_commands / agent.js dropdown.
  if (!is.null(chat_server_mod)) {
    .register_slash_commands(chat_server_mod, chat, settings, state, session, cwd)
  }

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
  # ------------------------------------------------------------------
  # Streaming task (ExtendedTask + coro::async)
  # user_contents: character scalar OR list (text + ContentImage/ContentPDF)
  # ------------------------------------------------------------------
    stream_task <- shiny::ExtendedTask$new(function(user_contents) {
    # Extract text for skill-prompt injection; keep full contents for LLM
    text_part <- if (is.character(user_contents)) user_contents
                 else if (is.list(user_contents) && length(user_contents) > 0 &&
                            is.character(user_contents[[1]]))
                   user_contents[[1]]
                 else as.character(user_contents)

    parsed <- .preprocess_input(text_part, cwd)
    # For skill trigger: replace text part with skill prompt; keep attachments
    actual_input <- if (identical(parsed$type, "skill")) {
      sp <- tryCatch(load_skill_prompt(parsed$name, parsed$args, cwd),
                     error = function(e) text_part)
      if (is.list(user_contents) && length(user_contents) > 1)
        c(list(sp), user_contents[-1L])   # skill text + original attachments
      else sp
    } else {
      user_contents  # "normal" or anything else -> send as-is (text or contents list)
    }

    shiny::isolate(state$compaction_ctrl$maybe_compact(
      chat,
      settings$model_limit %||% 200000L
    ))
    shiny::isolate(state$resource_state$maybe_replace(chat))

    # Resolve the positional turn contents ONCE, out here -- not inside the
    # coro::async body. coro rewrites `if` as control flow and cannot assign the
    # result of an `if` expression (coro `expr_info` error), so the
    # list-vs-scalar branch must live outside async. A list is spliced into
    # separate positional args (text + ContentImage/PDF); a scalar is wrapped so
    # do.call() treats it as a single positional arg.
    stream_contents <- if (is.list(actual_input)) actual_input else list(actual_input)

    coro::async(function() {
      if (!is.null(stream_ctrl)) stream_ctrl$reset()
      # do.call() splices stream_contents as positional `...` args to
      # user_turn() (equivalent to `!!!`), but is a plain call that coro can
      # transform -- a bare `!!!` inside a coro::async body is not coro-safe.
      stream <- do.call(
        chat$stream_async,
        c(stream_contents, list(stream = "content", controller = stream_ctrl))
      )
      await(shinychat::chat_append("chat", stream, session = session))

      n_tokens    <- token_count_with_estimation(chat)
      model_limit <- settings$model_limit %||% 200000L
      pct         <- round(n_tokens / model_limit * 100)
      # Context-left indicator (Claude Code calculateTokenWarningState).
      ws    <- tryCatch(calculate_token_warning_state(n_tokens, settings$model %||% ""),
                        error = function(e) NULL)
      left  <- if (is.null(ws)) NA_integer_ else ws$percent_left
      level <- if (is.null(ws)) "ok"
               else if (isTRUE(ws$at_blocking)) "blocking"
               else if (isTRUE(ws$above_error)) "error"
               else if (isTRUE(ws$above_warning)) "warning"
               else "ok"
      session$sendCustomMessage("update_budget", list(
        text          = format(n_tokens, big.mark = ","),
        pct           = pct,
        percent_left  = left,
        level         = level
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

    # user_input_contents() normalises plain text OR {text, attachments} payloads
    # (shinychat dev allow_attachments=TRUE). Returns character scalar or list of
    # contents (text + ContentImage/ContentPDF etc).
    raw_input  <- input$chat_user_input
    user_contents <- tryCatch(
      shinychat:::user_input_contents(raw_input),
      error = function(e) raw_input
    )
    # Extract plain-text portion for slash-command detection
    text_part <- if (is.character(user_contents)) user_contents
                 else if (is.list(user_contents) && length(user_contents) > 0 &&
                            is.character(user_contents[[1]]))
                   user_contents[[1]]
                 else if (is.list(raw_input)) raw_input[["text"]] %||% ""
                 else as.character(raw_input)

    # Pre-process: local commands are handled here (not sent to LLM).
    parsed <- tryCatch(.preprocess_input(text_part, cwd),
                       error = function(e) list(type = "normal"))

    if (identical(parsed$type, "command")) {
      .handle_chat_command(parsed, chat, settings, state, session, cwd)
      return()
    }

    # Pass full contents (text + any attachments) to the stream task
    stream_task$invoke(user_contents)
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

# ---------------------------------------------------------------------------
# Slash command registration (shinychat native API)
# ---------------------------------------------------------------------------

# Register all slash commands on a chat_server() module via $slash_command().
# Called once from server_chat() when chat_server_mod is available.
# Replaces the old ca_slash_commands sendCustomMessage + agent.js dropdown.
.register_slash_commands <- function(mod, chat, settings, state, session, cwd) {
  force(mod); force(chat); force(settings); force(state); force(session); force(cwd)

  # /model -- open model picker modal (no args) or switch directly (with args)
  mod$slash_command("model", "Switch model", function(content) {
    args <- if (missing(content)) "" else trimws(content@user_text)
    cur  <- tryCatch(chat$get_model(), error = function(e) settings$model %||% "?")
    if (!nzchar(args)) {
      tiers <- settings$tier_models %||% list()
      choices <- if (length(tiers)) {
        stats::setNames(unlist(tiers),
          vapply(names(tiers), function(nm)
            sprintf("%s  (%s)", nm, tiers[[nm]]), character(1)))
      } else stats::setNames(cur, cur)
      shiny::showModal(shiny::modalDialog(
        title = "Switch model",
        shiny::radioButtons("ca_model_pick", NULL,
          choices  = choices,
          selected = if (cur %in% unlist(tiers)) cur else unlist(tiers)[1L] %||% cur),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton("ca_model_pick_confirm", "Switch", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      mod$append(sprintf("**/model** -- pick a model in the popup to switch."),
                 role = "assistant")
    } else {
      new_chat <- tryCatch(codeagent:::.resolve_model_chat(args, cwd), error = function(e) NULL)
      if (!is.null(new_chat) && .swap_provider(chat, new_chat)) {
        new_model <- tryCatch(chat$get_model(), error = function(e) args)
        state$settings_changed <- state$settings_changed + 1L
        mod$append(paste0("OK Switched to `", new_model, "`"), role = "assistant")
      } else {
        mod$append(paste0("ERR Could not switch to `", args, "`"), role = "assistant")
      }
    }
  })

  # /compact -- compact context
  mod$slash_command("compact", "Compact the context", function() {
    tryCatch({
      full_compact(chat)
      mod$append("OK Context compacted.", role = "assistant")
    }, error = function(e)
      mod$append(paste0("ERR Compact failed: ", conditionMessage(e)), role = "assistant"))
  })

  # /clear -- clear UI + client history
  mod$slash_command("clear", "Clear chat history", function() {
    tryCatch(chat$set_turns(list()), error = function(e) NULL)
    mod$clear(
      messages       = list(list(role = "assistant", content = "OK History cleared.")),
      client_history = "keep"   # already cleared above
    )
  })

  # /rewind [N] -- rewind N exchanges
  mod$slash_command("rewind", "Rewind N exchanges", function(content) {
    args   <- trimws(content@user_text)
    n_back <- suppressWarnings(as.integer(args))
    if (is.na(n_back) || n_back < 1L) n_back <- 1L
    cur    <- length(tryCatch(chat$get_turns(), error = function(e) list()))
    keep   <- max(0L, cur - 2L * n_back)
    kept   <- tryCatch(truncate_chat_turns(chat, keep), error = function(e) cur)
    mod$append(sprintf("<<< Rewound %d exchange(s); %d turns kept.", n_back, kept),
               role = "assistant")
  })

  # Skills -- register each installed skill as a slash command
  tryCatch({
    metas <- list_skills_meta(cwd)
    for (nm in names(metas)) {
      local({
        skill_name <- nm
        skill_desc <- metas[[nm]]$description %||% ""
        has_args   <- nzchar(metas[[nm]]$argument_hint %||% "")
        if (has_args) {
          mod$slash_command(skill_name, skill_desc, function(content) {
            args   <- trimws(content@user_text)
            prompt <- tryCatch(load_skill_prompt(skill_name, args, cwd),
                               error = function(e) paste0("/", skill_name, " ", args))
            # Inject skill prompt directly into the chat (as a user turn)
            tryCatch(chat$chat(prompt), error = function(e) NULL)
          })
        } else {
          mod$slash_command(skill_name, skill_desc, function() {
            prompt <- tryCatch(load_skill_prompt(skill_name, "", cwd),
                               error = function(e) paste0("/", skill_name))
            tryCatch(chat$chat(prompt), error = function(e) NULL)
          })
        }
      })
    }
  }, error = function(e) NULL)

  invisible(NULL)
}
