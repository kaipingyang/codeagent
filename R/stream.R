#' @title Agent streaming API
#' @description
#'   Public streaming primitives for codeagent. These run the full per-turn
#'   pipeline (compaction, system-reminder injection, session save, cost
#'   tracking) and expose typed callbacks for each content event.
#'
#'   * [`codeagent_stream_async()`] -- returns a `coro::async` promise.
#'     Use this inside Shiny `ExtendedTask` bodies or any `coro::async` context.
#'   * [`codeagent_stream()`] -- synchronous wrapper that pumps the event loop
#'     with `later::run_now()` and handles `Ctrl+C` gracefully. Use in CLI/ink.
#' @keywords internal
#' @name stream
NULL

# ---------------------------------------------------------------------------
# codeagent_stream_async
# ---------------------------------------------------------------------------

#' Stream one agent turn asynchronously
#'
#' Runs the full turn pipeline (compaction, system-reminder injection, session
#' save, cost tracking) and invokes typed callbacks for each content event.
#'
#' **Tool event dual paths** (see plan sec6 for details):
#' * `on_tool_request` / `on_tool_result` parameters are called from the
#'   `ContentToolRequest` / `ContentToolResult` **stream chunks**.
#'   `on_tool_request` fires **before** the permission gate ("pre-gate
#'   notification"). `on_tool_result` receives the UI-neutral versioned
#'   `artifact`, shinychat's optional `display` adapter, and portable `value`
#'   fallback from `.adapt_tool_result()`.
#' * `chat$on_tool_request` / `chat$on_tool_result` **callbacks** (registered
#'   by the permission gate, midloop compaction, and display helpers) are
#'   independent and complementary.
#'
#' @param client A `CodeagentClient` (from [codeagent_client()]) or a bare
#'   `ellmer::Chat` object (or any list with a `$stream_async` method for
#'   testing via duck-typing).
#' @param input Character scalar. The user message.
#' @param on_delta Optional `function(text_chunk)`. Called for each text chunk.
#' @param on_thinking Optional `function(text)`. Called for thinking blocks
#'   (only on models with extended thinking enabled).
#' @param on_tool_request Optional `function(list(id, name, arguments, intent))`.
#'   Called from the `ContentToolRequest` stream chunk, **before** the
#'   permission gate. Useful for displaying a "pending" tool card.
#' @param on_tool_result Optional
#'   `function(list(id, name, display, value, is_error, artifact))`. Called from
#'   the `ContentToolResult` stream chunk. `artifact` is codeagent's versioned,
#'   UI-neutral primary contract; `display` is the optional shinychat adapter;
#'   `value` is the portable fallback for unsupported artifact versions/kinds.
#' @param on_error Optional `function(message, recovered)`. Called on error.
#' @param on_usage Optional `function(usage)`. Called at turn end with a list:
#'   `n_tokens`, `model_limit`, `warning_state`, `cost_last` (USD or `NA`).
#' @param controller Optional `ellmer::stream_controller()` for cancellation.
#' @param tool_mode `"concurrent"` (default) or `"sequential"`. Passed to
#'   `chat$stream_async(tool_mode=)`. Concurrent mode only accelerates
#'   asynchronous tools; synchronous CLI tools execute serially regardless.
#' @param session_id Character or NULL. Passed to [save_session()].
#' @param iteration Integer. Current turn iteration (affects system-reminder
#'   injection and memory recall on iteration 1).
#' @param cwd Character or NULL. Working directory.
#' @param compaction_ctrl A `CompactionController` or NULL.
#' @param resource_state A `ContentReplacementState` or NULL.
#' @return A `coro::async` promise resolving to
#'   `list(text, usage, stop_reason, finish_reason)`. Successful provider
#'   reasons are normalized by the same mapper used by [agent_loop()]; errors
#'   and interrupts retain their harness stop reasons.
#' @seealso [codeagent_stream()] for the synchronous wrapper.
#' @export
codeagent_stream_async <- function(
    client, input,
    on_delta        = NULL,
    on_thinking     = NULL,
    on_tool_request = NULL,
    on_tool_result  = NULL,
    on_error        = NULL,
    on_usage        = NULL,
    controller      = NULL,
    tool_mode       = "concurrent",
    session_id      = NULL,
    iteration       = 1L,
    cwd             = NULL,
    compaction_ctrl = NULL,
    resource_state  = NULL) {

  chat     <- if (inherits(client, "CodeagentClient")) client$chat else client
  settings <- if (inherits(client, "CodeagentClient")) client$settings else list()
  if (is.null(cwd)) cwd <- settings$cwd %||% getwd()

  # Data Shield input gate (edge 1): scan the user's text + attachments before
  # the turn reaches the model. Mirrors agent_loop's 1a.6 for the Shiny/stream
  # path so both entry points guard edge 1. No-op when no shield is active.
  ig <- .input_gate_guarded(input, settings, chat)
  if (identical(ig$action, "block")) {
    msg <- ig$text %||% "[Blocked by Data Shield input gate]"
    if (!is.null(on_delta)) tryCatch(on_delta(msg), error = function(e) NULL)
    return(promises::promise_resolve(
      list(text = msg, usage = NULL, stop_reason = "shield_blocked",
           finish_reason = NA_character_)))
  }
  input <- ig$input %||% input   # may be redacted; rest preserved

  # Output-gate buffering (edge 3, kiro round-2 #2, user decision: buffer-then-
  # show). When a shield is active we must scan the FINAL reply before the user
  # sees it -- but streaming on_delta paints tokens straight to the screen, with
  # no interception point. So when a shield is present we BUFFER: suppress live
  # on_delta, accumulate the full reply, run .output_gate_scan, then emit the
  # (possibly redacted) text once at the end. No shield => stream live as before
  # (zero cost). Sacrifices the typewriter effect for real edge-3 enforcement.
  .shield_active <- !is.null(.input_gate_shield(settings, chat))
  .citation_active <- .web_citations_enabled(settings$web_citations)
  .buffer_output <- isTRUE(.shield_active) || isTRUE(.citation_active)
  citation_registry <- .new_citation_registry()

  # Run turn setup OUTSIDE the coro::async body: coro cannot assign the result
  # of an `if` expression, and .turn_setup contains such branches.
  actual_input <- .turn_setup(client, input, iteration, cwd,
                               compaction_ctrl, resource_state)
  # ellmer's `...` contract expects each text/content part as its own argument.
  # Preserve scalar input as one argument, but expand Shiny's multimodal list
  # (text followed by Content attachments) across the dots.
  stream_contents <- if (is.list(actual_input)) actual_input else list(actual_input)

  # Mark this as an async turn so promise-returning tools (e.g. concurrent
  # sub-agents) are permitted; cleared when the turn's promise settles.
  .enter_async_turn()
  .async_result <- coro::async(function() {
    # controller resets automatically when passed to a new stream call
    # (ellmer 0.4.1 docs), but an explicit tryCatch-guarded reset is harmless.
    if (!is.null(controller))
      tryCatch(controller$reset(), error = function(e) NULL)

    # acc is initialised at the top level so it is visible to the error handler.
    acc <- ""

    tryCatch({
      stream <- do.call(chat$stream_async,
                        c(stream_contents,
                          list(stream     = "content",
                               controller = controller,
                               tool_mode  = tool_mode)))

      for (chunk in coro::await_each(stream)) {

        if (S7::S7_inherits(chunk, ellmer::ContentThinking)) {
          # Extended-thinking block: emit to on_thinking if provided.
          th <- tryCatch(chunk@thinking, error = function(e) "")
          if (!is.null(on_thinking) && nzchar(th)) on_thinking(th)

        } else if (S7::S7_inherits(chunk, ellmer::ContentToolRequest)) {
          # Pre-gate notification: the permission gate fires later via
          # chat$on_tool_request; this callback is a preview for the UI.
          if (!is.null(on_tool_request)) {
            nm     <- tryCatch(chunk@name,      error = function(e) "")
            args   <- tryCatch(chunk@arguments, error = function(e) list())
            intent <- tryCatch(args[["_intent"]], error = function(e) NULL)
            on_tool_request(list(
              id        = tryCatch(chunk@id, error = function(e) ""),
              name      = nm,
              arguments = args,
              intent    = intent))
          }

        } else if (S7::S7_inherits(chunk, ellmer::ContentToolResult)) {
          # Tool completed: collect current-turn sources before display adaption.
          adapted <- tryCatch(.adapt_tool_result(chunk), error = function(e) chunk)
          .citation_registry_add(
            citation_registry, .citation_sources_from_result(adapted))
          if (!is.null(on_tool_result)) {
            display  <- tryCatch(adapted@extra$display, error = function(e) NULL)
            artifact <- tool_result_artifact(adapted, version = NULL)
            req      <- tryCatch(chunk@request, error = function(e) NULL)
            on_tool_result(list(
              id       = tryCatch(
                           if (!is.null(req)) req@id   else NA_character_,
                           error = function(e) NA_character_),
              name     = tryCatch(
                           if (!is.null(req)) req@name else NA_character_,
                           error = function(e) NA_character_),
              display  = display,
              value    = tool_result_value(adapted),
              is_error = !is.null(tryCatch(chunk@error, error = function(e) NULL)),
              artifact = artifact))
          }

        } else {
          # Text chunk: accumulate and notify. In buffer mode (shield active) we
          # withhold live deltas -- the reply is emitted once, post-scan, below.
          txt <- .chunk_text(chunk)
          if (nzchar(txt)) {
            acc <- paste0(acc, txt)
            if (!is.null(on_delta) && !isTRUE(.buffer_output)) on_delta(txt)
          }
        }
      }

      # Map only after the stream has closed and the final AssistantTurn exists.
      # Append the static note before the output gate. In live mode only the note
      # remains to emit; buffered mode emits the complete gated response once.
      finish <- .map_finish_reason(.last_finish_reason(chat))
      acc <- .append_finish_note(acc, finish$note)
      if (isTRUE(.citation_active))
        acc <- .render_turn_citations(
          acc, citation_registry, settings, chat)
      og <- .output_gate_guarded(acc, settings, chat)
      acc <- og$text %||% acc
      if (!is.null(on_delta)) {
        if (isTRUE(.buffer_output) && nzchar(acc))
          tryCatch(on_delta(acc), error = function(e) NULL)
        if (!isTRUE(.buffer_output) && !is.null(finish$note))
          tryCatch(on_delta(paste0("\n\n", finish$note)), error = function(e) NULL)
      }

      hooks <- tryCatch(settings$hooks_registry, error = function(e) NULL)
      if (!is.null(hooks)) tryCatch(
        hooks$run_assistant_message(acc), error = function(e) NULL)
      usage <- .turn_teardown(
        client, cwd, session_id, presentation_text = acc)
      if (!is.null(hooks)) tryCatch(
        hooks$run_stop(finish$stop_reason,
                       list(session_id = session_id,
                            finish_reason = finish$finish_reason)),
        error = function(e) NULL)
      if (!is.null(on_usage)) on_usage(usage)
      invisible(list(text = acc, usage = usage,
                     stop_reason = finish$stop_reason,
                     finish_reason = finish$finish_reason))

    }, error = function(e) {
      # acc is visible here (outer-scope variable in the async closure).
      recovered <- tryCatch(
        .handle_agent_error(e, chat, actual_input, compaction_ctrl,
                            hooks = tryCatch(settings$hooks_registry,
                                             error = function(e2) NULL)),
        error = function(e2) paste0("[error] ", conditionMessage(e2)))
      # Fail-closed on the ERROR path too (kiro round-4 #1): the partial reply in
      # `acc` was accumulated but the output gate only ran on the success branch.
      # When a shield is active, scan the partial text before it leaves via the
      # return value, and DO NOT surface the raw error string (conditionMessage
      # may itself embed a protected value, e.g. a mid-stream FAKEID) to on_error.
      if (isTRUE(.buffer_output)) {
        if (isTRUE(.citation_active))
          acc <- .render_turn_citations(
            acc, citation_registry, settings, chat)
        og  <- .output_gate_guarded(acc, settings, chat)
        acc <- og$text %||% acc
        if (!is.null(on_error)) on_error(
          "[data_shield] stream error; details withheld (fail-closed).",
          is.character(recovered))
      } else if (!is.null(on_error)) {
        on_error(conditionMessage(e), is.character(recovered))
      }
      invisible(list(text = acc, usage = NULL, stop_reason = "error",
                     finish_reason = .last_finish_reason(chat)))
    })
  })()
  promises::finally(.async_result, function() .exit_async_turn())
}

# ---------------------------------------------------------------------------
# codeagent_stream
# ---------------------------------------------------------------------------

#' Stream one agent turn synchronously (CLI / ink)
#'
#' A synchronous wrapper around [codeagent_stream_async()] that pumps the
#' `later` event loop at 100 ms intervals. Handles `Ctrl+C` gracefully:
#' the in-progress stream is cancelled via the `stream_controller` and the
#' REPL / calling code can continue (the interrupt is **not** re-thrown).
#'
#' @inheritParams codeagent_stream_async
#' @param on_tick Optional `function()` called once per ~100 ms event-loop tick
#'   while pumping the loop (e.g. to animate a spinner).
#' @param ... Passed to [codeagent_stream_async()].
#' @return Invisibly, `list(text, usage, stop_reason, finish_reason)`.
#' @seealso [codeagent_stream_async()] for the async variant.
#' @export
codeagent_stream <- function(client, input, ...,
                              on_tick         = NULL,
                              controller      = NULL,
                              session_id      = NULL,
                              iteration       = 1L,
                              cwd             = NULL,
                              compaction_ctrl = NULL,
                              resource_state  = NULL) {

  if (is.null(controller))
    controller <- tryCatch(ellmer::stream_controller(), error = function(e) NULL)

  result <- NULL
  done   <- FALSE

  p <- codeagent_stream_async(
    client, input, ...,
    controller      = controller,
    session_id      = session_id,
    iteration       = iteration,
    cwd             = cwd,
    compaction_ctrl = compaction_ctrl,
    resource_state  = resource_state)

  # codeagent_stream_async always fulfills (never rejects): the tryCatch inside
  # the async body converts all errors to list returns.
  promises::then(p, function(r) { result <<- r; done <<- TRUE })

  tryCatch({
    timeout <- Sys.time() + 60L * 30L   # 30-minute safety ceiling
    while (!isTRUE(done) && Sys.time() < timeout) {
      later::run_now(timeoutSecs = 0.1)  # 100 ms -> responsive Ctrl+C
      if (!is.null(on_tick)) tryCatch(on_tick(), error = function(e) NULL)
    }
  }, interrupt = function(e) {
    # Ctrl+C: cancel the stream gracefully.
    # ellmer 0.4.0+ (#840) + 0.4.1+ (#643) handle orphan tool requests and
    # AssistantPartialTurn automatically -- no manual patching needed.
    if (!is.null(controller))
      tryCatch(controller$cancel(), error = function(e2) NULL)
    cat("\n[interrupted]\n")
    # Do NOT re-throw: the caller (REPL / ink) continues to the next input.
  })

  invisible(result %||% list(text = "", usage = NULL,
                            stop_reason = "interrupted",
                            finish_reason = NA_character_))
}
