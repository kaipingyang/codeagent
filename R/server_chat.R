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
    text_part <- .user_input_text(user_contents)

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
      settings$model_limit %||% 200000L,
      compact_model = .resolve_compact_model(chat, settings)
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
      # Wrap the stream so an unreachable endpoint / auth failure / mid-stream
      # error surfaces as a visible message and the task leaves the "running"
      # state (which re-enables the input) instead of leaving the user staring
      # at a stuck streaming spinner.
      tryCatch(
        {
          stream <- do.call(
            chat$stream_async,
            c(stream_contents, list(stream = "content", controller = stream_ctrl))
          )
          await(shinychat::chat_append("chat", stream, session = session))
        },
        error = function(e) {
          tryCatch(
            shinychat::chat_append(
              "chat",
              paste0(
                "**Request failed.** ", conditionMessage(e),
                "\n\nCheck the model endpoint / credentials and try again."
              ),
              session = session
            ),
            error = function(e2) NULL
          )
        }
      )

      n_tokens    <- token_count_with_estimation(chat)
      model_limit <- settings$model_limit %||% 200000L
      # Context-left indicator: computed in a plain helper because coro::async
      # cannot assign the result of an `if` expression inside this body.
      session$sendCustomMessage("update_budget",
        .budget_payload(n_tokens, model_limit, settings$model %||% ""))

      shiny::isolate(state$iteration <- state$iteration + 1L)

      # Auto-save every turn (session_id is always set from startup).
      sid <- shiny::isolate(state$session_id)
      tryCatch(save_session(chat, cwd, sid), error = function(e) NULL)

      "done"
    })()
  })

  shiny::observeEvent(input$chat_user_input, {
    if (stream_task$status() == "running") return()
    if (isTRUE(shiny::isolate(state$busy))) return()   # e.g. /compact in progress
    state$interrupt <- FALSE

    # shinychat (dev, allow_attachments = TRUE) already delivers a normalized
    # value in input$chat_user_input:
    #   * allow_attachments = FALSE -> a plain character scalar
    #   * allow_attachments = TRUE  -> a contents list (text string, then one
    #     Content object per attachment)
    # Only an older/alternate build sends a raw {text, attachments} wire payload
    # that still needs user_input_contents(). Detect that shape explicitly:
    # calling user_input_contents() on an ALREADY-normalized contents list
    # wrongly returns an empty list() -> the message is silently dropped and the
    # downstream stream_task crashes in .preprocess_input (subscript out of
    # bounds). See inst/experiments/capture_input/ for the captured evidence.
    raw_input  <- input$chat_user_input
    user_contents <-
      if (is.list(raw_input) && !is.null(raw_input[["text"]])) {
        tryCatch(shinychat:::user_input_contents(raw_input),
                 error = function(e) raw_input)
      } else {
        raw_input
      }
    # Extract plain-text portion for slash-command detection
    text_part <- .user_input_text(user_contents)

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

  # Disable the chat input while streaming OR while a local command (e.g.
  # /compact) is in progress. Reacts to the ExtendedTask status + state$busy and
  # tells the client to gate the input (see agent.js `ca_input_busy`). This
  # eliminates overlapping sends (belt-and-suspenders over the server guards).
  shiny::observe({
    busy <- identical(tryCatch(stream_task$status(), error = function(e) ""),
                      "running") || isTRUE(state$busy) || isTRUE(state$initializing)
    session$sendCustomMessage("ca_input_busy", list(busy = busy))
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
      .resolve_model_chat(new_spec, cwd),
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
          .resolve_model_chat(args, cwd),
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
      # Show an immediate progress indicator, then run the (blocking) compaction
      # on the next event-loop tick so the indicator renders first. Set state$busy
      # so input submits are ignored until compaction finishes (see the input +
      # slash observers). Result is appended from the deferred callback below, so
      # we return NULL here (caller appends nothing now).
      instr <- trimws(args)
      cm    <- .resolve_compact_model(chat, settings)
      if (!is.null(state)) shiny::isolate(state$busy <- TRUE)
      tryCatch(shiny::showNotification(
        "\U0001F5DC Compacting context\u2026 (a few seconds)",
        id = "ca_compact_progress", duration = NULL, type = "message",
        session = session), error = function(e) NULL)
      later::later(function() {
        ok <- tryCatch({
          full_compact(chat, model = cm,
                       instructions = if (nzchar(instr)) instr else NULL)
          TRUE
        }, error = function(e) FALSE)
        tryCatch(shiny::removeNotification("ca_compact_progress", session = session),
                 error = function(e) NULL)
        tryCatch(shinychat::chat_append("chat",
          if (ok) "\u2705 Context compacted." else "\u274C Compact failed.",
          role = "assistant", session = session), error = function(e) NULL)
        if (!is.null(state)) shiny::isolate(state$busy <- FALSE)
      }, delay = 0.15)
      NULL
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

    budget = {
      n     <- tryCatch(estimate_tokens(chat), error = function(e) 0L)
      limit <- settings$model_limit %||% 200000L
      pct   <- if (limit > 0L) round(n / limit * 100) else 0L
      sprintf("**Token budget**: %s / %s tokens (%d%%)",
              format(n, big.mark = ","), format(limit, big.mark = ","), pct)
    },

    sessions = {
      sl <- tryCatch(list_sessions(cwd, limit = 10L), error = function(e) list())
      if (!length(sl)) {
        "No saved sessions."
      } else {
        lines <- vapply(sl, function(s)
          sprintf("- `%s`  %s", substr(s$session_id, 1L, 8L),
                  s$title %||% s$timestamp %||% ""), character(1))
        paste0("**Recent sessions**\n", paste(lines, collapse = "\n"))
      }
    },

    help = ,
    exit = ,
    quit = paste0(
      "**Slash commands**\n",
      "- `/model [spec]` -- switch model (popup if no arg)\n",
      "- `/compact` -- compact the context now\n",
      "- `/clear` -- clear the conversation\n",
      "- `/rewind [N]` -- rewind the last N exchange(s)\n",
      "- `/budget` -- show token usage\n",
      "- `/sessions` -- list recent saved sessions\n",
      "- `/<skill> [args]` -- invoke a skill (sent to the model)"
    ),

    # Unknown local command -- show help
    paste0("Unknown command: `/", name, "`.\n\n",
           "Built-in commands: `/model`, `/compact`, `/clear`, `/rewind [N]`, ",
           "`/budget`, `/sessions`, `/help`")
  )

  # Append feedback to chat (NULL means the command handled its own UI, e.g. modal).
  # Use the string + role form (NOT a Turn object): in shinychat's React build
  # chat_append() renders a plain string reliably, whereas a Turn object may not.
  if (!is.null(feedback) && nzchar(feedback)) {
    tryCatch(
      shinychat::chat_append("chat", feedback, role = "assistant",
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
      new_chat <- tryCatch(.resolve_model_chat(args, cwd), error = function(e) NULL)
      if (!is.null(new_chat) && .swap_provider(chat, new_chat)) {
        new_model <- tryCatch(chat$get_model(), error = function(e) args)
        state$settings_changed <- state$settings_changed + 1L
        mod$append(paste0("OK Switched to `", new_model, "`"), role = "assistant")
      } else {
        mod$append(paste0("ERR Could not switch to `", args, "`"), role = "assistant")
      }
    }
  })

  # /compact [instructions] -- compact context, optional focus instructions
  mod$slash_command("compact", "Compact the context", function(content) {
    instr <- tryCatch(trimws(content@user_text %||% ""), error = function(e) "")
    tryCatch({
      full_compact(chat, model = .resolve_compact_model(chat, settings),
                   instructions = if (nzchar(instr)) instr else NULL)
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
