#' @title Agent Query Loop
#' @description `codeagent_client()` builds a configured client from any
#'   ellmer Chat. `codeagent()` runs one-shot queries. `agent_loop()` drives
#'   the Shiny app's agentic loop.
#' @name query
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# CodagentClient S3 class
# ---------------------------------------------------------------------------

#' Wrap an ellmer Chat with codeagent settings into a client object
#'
#' @param chat Ellmer Chat object (already equipped with tools and system prompt).
#' @param settings Named list from [load_settings()].
#' @return Object of class `CodagentClient`.
#' @keywords internal
.new_client <- function(chat, settings) {
  structure(list(chat = chat, settings = settings), class = "CodagentClient")
}

#' @export
print.CodagentClient <- function(x, ...) {
  cat("<CodagentClient>\n")
  cat("  model:           ", x$settings$model %||% "(auto)", "\n")
  cat("  permission_mode: ", x$settings$permission_mode %||% "default", "\n")
  cat("  cwd:             ", x$settings$cwd %||% getwd(), "\n")
  invisible(x)
}

# ---------------------------------------------------------------------------
# Chat factory (Anthropic vs OpenAI-compatible)
# ---------------------------------------------------------------------------

#' Create a bare ellmer Chat from settings
#'
#' @param settings List. Output of [load_settings()].
#' @param cwd Character. Working directory.
#' @param ... Passed to the underlying ellmer function.
#' @return An `ellmer::Chat` object.
#' @keywords internal
.make_chat <- function(settings, cwd = getwd(), ...) {
  sp <- .build_system_prompt(settings, cwd)

  # effort_level -> ellmer params(reasoning_effort=) when set
  extra_params <- if (!is.null(settings$effort_level) && nzchar(settings$effort_level)) {
    list(params = ellmer::params(reasoning_effort = settings$effort_level))
  } else list()

  # Resolve the ellmer chat factory to use.
  # Priority: explicit settings$provider > base_url presence > default "anthropic"
  # Strip leading "chat_" if user typed the full function name for convenience.
  raw_prov <- settings$provider %||% NULL
  if (!is.null(raw_prov)) raw_prov <- sub("^chat_", "", trimws(raw_prov))
  provider <- raw_prov %||%
    if (!is.null(settings$base_url) && nzchar(settings$base_url))
      "openai_compatible" else "anthropic"

  api_key_env <- settings$api_key_env %||% "CODEAGENT_API_KEY"
  creds <- function() Sys.getenv(api_key_env)
  bu    <- settings$base_url %||% ""
  model <- settings$model

  chat_args <- switch(
    provider,
    # ---- OpenAI-compatible: Databricks / Azure / vLLM / any custom endpoint ----
    openai_compatible = c(list(base_url=bu, model=model, credentials=creds, system_prompt=sp, preserve_thinking=TRUE), extra_params),
    openai            = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    vllm              = c(list(base_url=if(nzchar(bu)) bu else NULL, model=model, system_prompt=sp), extra_params),
    lmstudio          = c(list(base_url=if(nzchar(bu)) bu else NULL, model=model, system_prompt=sp), extra_params),
    # ---- Anthropic ----
    anthropic         = c(list(model=model, system_prompt=sp), extra_params),
    claude            = c(list(model=model, system_prompt=sp), extra_params),
    # ---- Local ----
    ollama            = c(list(base_url=if(nzchar(bu)) bu else NULL, model=model, system_prompt=sp), extra_params),
    # ---- Hosted vendors ----
    databricks        = c(list(workspace=if(nzchar(bu)) bu else NULL, model=model, system_prompt=sp), extra_params),
    deepseek          = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    google_gemini     = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    google_vertex     = c(list(model=model, system_prompt=sp), extra_params),
    groq              = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    github            = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    aws_bedrock       = c(list(model=model, system_prompt=sp), extra_params),
    azure_openai      = c(list(base_url=if(nzchar(bu)) bu else NULL, model=model, credentials=creds, system_prompt=sp), extra_params),
    mistral           = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    perplexity        = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    portkey           = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    posit             = c(list(model=model, system_prompt=sp), extra_params),
    huggingface       = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    groq              = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    cloudflare        = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    snowflake         = c(list(model=model, system_prompt=sp), extra_params),
    openrouter        = c(list(model=model, credentials=creds, system_prompt=sp), extra_params),
    {
      cli::cli_abort(c(
        "Unknown provider {.val {provider}}.",
        "i" = "Valid values: openai_compatible, anthropic, ollama, databricks, deepseek, google_gemini, groq, openai, github, vllm, lmstudio, azure_openai, aws_bedrock, mistral, perplexity, posit, ...",
        "i" = "Or pass a {.cls Chat} object directly to {.fn codeagent_client}."
      ))
    }
  )

  fn_name <- paste0("chat_", provider)
  fn <- tryCatch(get(fn_name, envir = asNamespace("ellmer"), inherits = FALSE),
                 error = function(e) NULL)
  if (is.null(fn))
    cli::cli_abort("ellmer does not export {.fn {fn_name}}. Check provider spelling.")

  do.call(fn, c(chat_args, list(...)))
}

# ---------------------------------------------------------------------------
# codeagent_client() -- the primary configuration entry point
# ---------------------------------------------------------------------------

#' Create a codeagent client from any ellmer Chat
#'
#' Injects codeagent tools (Bash, Read, Write, Edit, Glob, Grep, LS, btw tools,
#' skill tool) and rebuilds the system prompt. The returned `CodagentClient`
#' is the single object passed to [codeagent()] and [codeagent_app()].
#'
#' @param chat An `ellmer::Chat` object -- any backend supported by ellmer:
#'   `chat_openai_compatible()`, `chat_anthropic()`, `chat_ollama()`, etc.
#'   If NULL, a chat is auto-built from `CODEAGENT_BASE_URL`/`CODEAGENT_MODEL`
#'   env vars (or Anthropic defaults).
#' @param permission_mode Character. One of [PermissionMode].
#' @param rules List of [PermissionRule()] objects.
#' @param cwd Character. Working directory (used for CLAUDE.md, skills, sessions).
#' @param max_turns Integer. Maximum agentic loop turns.
#' @param btw_groups Character vector or NULL. btw tool groups to register
#'   (e.g. `c("docs","git","pkg")`). NULL = all available groups.
#' @param worktree_isolation Logical. Run sub-agents in isolated git worktrees.
#' @param verify_fn Function or NULL. Optional output verifier; re-enters the
#'   loop when it reports failures (e.g. [verify_r_tests()]).
#' @param mcp_config MCP client config (JSON path or inline list) to connect
#'   external MCP servers; see [register_mcp_client()]. NULL disables.
#' @return Object of class `CodagentClient` with slots `$chat` and `$settings`.
#' @export
codeagent_client <- function(
  chat               = NULL,
  permission_mode    = "default",
  rules              = list(),
  cwd                = getwd(),
  max_turns          = 100L,
  btw_groups         = NULL,
  worktree_isolation = FALSE,
  verify_fn          = NULL,
  mcp_config         = NULL
) {
  # Input validation (user-facing entry point).
  if (!is.null(chat) && !inherits(chat, "Chat"))
    cli::cli_abort("{.arg chat} must be an {.cls ellmer::Chat} object or NULL, not {.cls {class(chat)[1]}}.")
  valid_modes <- unlist(PermissionMode, use.names = FALSE)
  if (!is.character(permission_mode) || length(permission_mode) != 1L ||
      !permission_mode %in% valid_modes)
    cli::cli_abort(c(
      "{.arg permission_mode} must be one of {.val {valid_modes}}.",
      "x" = "You supplied {.val {permission_mode}}."
    ))
  if (!is.list(rules))
    cli::cli_abort("{.arg rules} must be a list of {.fn PermissionRule} objects.")

  settings <- load_settings(cwd)
  settings$permission_mode     <- permission_mode
  # Merge rules: caller-supplied rules take priority over settings.json rules.
  # settings$rules is already parsed from permissions.allow/deny/ask by load_settings().
  settings$rules               <- c(rules, settings$rules)
  settings$cwd                 <- cwd
  settings$max_turns           <- as.integer(max_turns)
  settings$btw_groups          <- btw_groups
  settings$worktree_isolation  <- isTRUE(worktree_isolation)
  settings$verify_fn           <- verify_fn
  settings$mcp_config          <- mcp_config

  # Declarative hooks from settings.json -> live HookRegistry (M5 closing).
  settings$hooks_registry      <- tryCatch(.hooks_from_settings(settings),
                                           error = function(e) NULL)

  if (is.null(chat)) {
    chat <- .make_chat(settings, cwd)
  } else {
    # User-supplied chat: update system prompt to include skill hint + CLAUDE.md
    sp <- .build_system_prompt(settings, cwd)
    tryCatch(chat$set_system_prompt(sp), error = function(e) NULL)
    # Extract model from the chat if possible
    settings$model <- tryCatch(chat$get_model(),
                               error = function(e) settings$model)
  }

  ask_fn <- if (interactive()) .console_ask_fn else NULL
  .register_all_tools(chat, settings, ask_fn = ask_fn)

  # Auto-connect MCP servers declared in settings.json (P2 closing). The
  # mcp_config param still works; this adds servers from the settings file.
  tryCatch(.mcp_autoconnect(chat, settings), error = function(e) NULL)

  .new_client(chat, settings)
}

# ---------------------------------------------------------------------------
# codeagent() -- one-shot query
# ---------------------------------------------------------------------------

#' Run a one-shot codeagent query
#'
#' Two calling conventions:
#'
#' **New (recommended):** pass a [codeagent_client()] as first argument.
#' ```r
#' client <- codeagent_client(chat_openai_compatible(...), permission_mode = "bypass")
#' codeagent(client, "List all .R files")
#' ```
#'
#' **Legacy (backward-compatible):** omit client, pass model etc. directly.
#' ```r
#' codeagent("List all .R files", model = "gsds-gpt41", permission_mode = "bypass")
#' ```
#'
#' @param client_or_prompt Either a `CodagentClient` (from [codeagent_client()])
#'   or a character prompt string (legacy mode).
#' @param prompt Character. The user prompt. Required when `client_or_prompt`
#'   is a `CodagentClient`; unused in legacy mode.
#' @param model Character. Legacy: model name.
#' @param permission_mode Character. Legacy: permission mode.
#' @param rules List. Legacy: permission rules.
#' @param cwd Character. Legacy: working directory.
#' @param max_turns Integer. Legacy: max turns.
#' @param btw_groups Character vector or NULL. Legacy: btw tool groups.
#' @param ... Legacy: extra args passed to `.make_chat()`.
#' @return Character. The final model response.
#' @export
codeagent <- function(client_or_prompt,
                       prompt          = NULL,
                       model           = "claude-sonnet-4-6",
                       permission_mode = "default",
                       rules           = list(),
                       cwd             = getwd(),
                       max_turns       = 100L,
                       btw_groups      = NULL,
                       ...) {
  # Dispatch: new style (CodagentClient) vs legacy (prompt string)
  if (inherits(client_or_prompt, "CodagentClient")) {
    client <- client_or_prompt
    if (is.null(prompt))
      stop("'prompt' must be provided when 'client_or_prompt' is a CodagentClient.",
           call. = FALSE)
    chat     <- client$chat
    settings <- client$settings
  } else {
    # Legacy: client_or_prompt IS the prompt string
    actual_prompt <- client_or_prompt
    settings <- load_settings(cwd)
    settings$model           <- model
    settings$permission_mode <- permission_mode
    settings$max_turns       <- as.integer(max_turns)
    settings$cwd             <- cwd
    settings$btw_groups      <- btw_groups
    if (!is.null(list(...)$base_url)) settings$base_url <- list(...)$base_url
    chat <- .make_chat(settings, cwd)
    ask_fn <- if (interactive()) .console_ask_fn else NULL
    .register_all_tools(chat, settings, ask_fn = ask_fn)
    prompt <- actual_prompt
  }

  response <- tryCatch(
    chat$chat(prompt),
    error = function(e) paste0("[Error] ", conditionMessage(e))
  )
  if (is.character(response)) response else "[No response]"
}

# ---------------------------------------------------------------------------
# agent_loop() -- used by the Shiny app
# ---------------------------------------------------------------------------

#' Main agentic query loop
#'
#' Handles a single user turn. Accepts either a `CodagentClient` (new style)
#' or the legacy `(chat, settings)` pair.
#'
#' @param user_input Character. User message.
#' @param client A `CodagentClient` (from [codeagent_client()]), or an
#'   `ellmer::Chat` for legacy use.
#' @param settings Named list. Only needed in legacy mode (ignored when
#'   `client` is a `CodagentClient`).
#' @param compaction_ctrl A [CompactionController] R6 object.
#' @param budget_tracker A [BudgetTracker] R6 object.
#' @param resource_state A [ContentReplacementState] R6 object.
#' @param hooks A [HookRegistry] R6 object or NULL.
#' @param cwd Character. Working directory (for session save). Overrides
#'   `client$settings$cwd` when provided explicitly.
#' @param session_id Character or NULL.
#' @param iteration Integer. Current loop iteration.
#' @return Named list: `response`, `session_id`, `stop_reason`.
#' @export
agent_loop <- function(user_input,
                        client,
                        settings        = NULL,
                        compaction_ctrl = CompactionController$new(),
                        budget_tracker  = BudgetTracker$new(),
                        resource_state  = ContentReplacementState$new(),
                        hooks           = NULL,
                        cwd             = NULL,
                        session_id      = NULL,
                        iteration       = 1L) {
  # Resolve chat + settings from CodagentClient or legacy pair
  if (inherits(client, "CodagentClient")) {
    chat     <- client$chat
    settings <- client$settings
  } else {
    # Legacy: client is the bare Chat object
    chat <- client
    if (is.null(settings))
      settings <- load_settings(cwd %||% getwd())
  }
  if (is.null(cwd)) cwd <- settings$cwd %||% getwd()

  # 1. Max turns check
  max_turns <- as.integer(settings$max_turns %||% 100L)
  if (iteration > max_turns) {
    if (!is.null(hooks)) tryCatch(
      hooks$run_stop("max_turns", list(iteration = iteration)),
      error = function(e) NULL)
    return(list(response    = sprintf("[Max turns (%d) reached: stopping agent loop]", max_turns),
                session_id  = session_id,
                stop_reason = "max_turns"))
  }

  # 1a. Fire SessionStart hook on the first iteration of a session.
  if (!is.null(hooks) && iteration <= 1L)
    tryCatch(hooks$run_session_start(list(cwd = cwd, session_id = session_id)),
             error = function(e) NULL)

  # 1b. Inject system-reminder (dynamic context into user message, not system prompt)
  #     This mirrors Claude Code's <system-reminder> pattern: ephemeral metadata
  #     injected at message time so it doesn't invalidate the prompt cache.
  reminder <- .build_system_reminder(settings, iteration, cwd, query = user_input)
  actual_input <- if (nzchar(reminder))
    paste0(user_input, "\n\n", reminder)
  else
    user_input

  # 2. Budget check
  current_tokens <- estimate_tokens(chat)
  if (budget_tracker$should_stop(current_tokens,
                                   settings$model_limit %||% 200000L,
                                   iteration)) {
    if (!is.null(hooks)) tryCatch(
      hooks$run_stop("budget_exceeded", list(tokens = current_tokens)),
      error = function(e) NULL)
    return(list(response    = "[Budget exceeded: stopping agent loop]",
                session_id  = session_id,
                stop_reason = "budget_exceeded"))
  }

  # 3. Compaction (fire PreCompact hook first)
  if (!is.null(hooks)) tryCatch(
    hooks$run_pre_compact("auto", list(tokens = current_tokens)),
    error = function(e) NULL)
  compaction_ctrl$maybe_compact(chat, settings$model_limit %||% 200000L,
                                compact_model = settings$small_fast_model %||% .HAIKU_MODEL)

  # 4. Resource management
  resource_state$maybe_replace(chat)

  # 5. Fire UserMessage hook
  if (!is.null(hooks)) tryCatch(hooks$run_user_message(user_input), error = function(e) NULL)

  # 6. Send (with system-reminder injected into actual_input)
  response <- tryCatch({
    chat$chat(actual_input)
  }, error = function(e) {
    .handle_agent_error(e, chat, actual_input, compaction_ctrl)
  })

  if (!is.character(response)) response <- "[No text response]"

  # 6b. Inspect the model's stop reason (ellmer AssistantTurn$finish_reason).
  #     "length" means the reply hit the output-token cap -> flag it so the UI /
  #     caller knows the answer may be cut off. ellmer resolves tool_use loops
  #     inside chat$chat(), so the final turn is normally "stop"/"length".
  finish_reason <- .last_finish_reason(chat)
  if (identical(finish_reason, "length")) {
    response <- paste0(
      response,
      "\n\n[Note: response was truncated at the model's output-token limit.]")
  }

  # 7. Fire AssistantMessage hook
  if (!is.null(hooks)) tryCatch(hooks$run_assistant_message(response), error = function(e) NULL)

  # 7b. Verification loop -- run verify_fn and re-enter if it reports failures
  verify_fn <- settings$verify_fn
  if (!is.null(verify_fn) && is.function(verify_fn)) {
    verify_result <- tryCatch(verify_fn(response, chat, cwd), error = function(e) {
      list(passed = FALSE, message = conditionMessage(e))
    })
    if (!isTRUE(verify_result$passed)) {
      verify_msg <- verify_result$message %||% "Verification failed."
      re_input   <- paste0(
        "The previous response had verification failures. Please fix:\n\n",
        verify_msg
      )
      re_response <- tryCatch(chat$chat(re_input),
                               error = function(e) paste0("[Verify retry error] ", conditionMessage(e)))
      if (is.character(re_response)) response <- re_response
    }
  }

  # 8. Save session
  if (!is.null(session_id))
    tryCatch(save_session(chat, cwd, session_id), error = function(e) NULL)

  # 9. Fire Stop hook (normal completion)
  if (!is.null(hooks)) tryCatch(
    hooks$run_stop("completed", list(session_id = session_id)),
    error = function(e) NULL)

  list(response = response, session_id = session_id,
       stop_reason = if (identical(finish_reason, "length")) "truncated" else "completed",
       finish_reason = finish_reason)
}

# ---------------------------------------------------------------------------
# Tool registration helper
# ---------------------------------------------------------------------------

#' Register all codeagent tools to a Chat object
#'
#' @param chat An `ellmer::Chat` object.
#' @param settings Named list from [load_settings()].
#' @param ask_fn Function or NULL.
#' @param ask_question_fn Function or NULL. Shiny callback for AskUserQuestion
#'   (Phase 3). NULL uses CLI readline path.
#' @return Invisibly `chat`.
#' @keywords internal
.register_all_tools <- function(chat, settings, ask_fn = NULL,
                                  ask_question_fn = NULL) {
  # Live, mutable permission mode shared by every checker. Plan-mode tools flip
  # `mode_env$mode` mid-conversation and all already-registered checkers observe
  # it (see .make_permission_checker). Static string still works elsewhere.
  mode_env      <- new.env(parent = emptyenv())
  mode_env$mode <- settings$permission_mode %||% "default"
  mode  <- mode_env             # pass the env as `mode` to permission checkers
  rules <- settings$rules %||% list()
  cwd   <- settings$cwd %||% getwd()

  # Shiny interaction wiring (Phase 3). When the Shiny server has installed
  # promise-returning callbacks (settings$shiny_ask_fn / shiny_ask_question_fn),
  # build ASYNC-gated variants of the interactive tools (Write/Edit/MultiEdit/
  # Bash/RunR + AskUserQuestion) so they pause on the UI approval/question bar.
  # These override the ask_fn/ask_question_fn args and are only present in the
  # Shiny path — the CLI/one-shot path leaves them NULL and stays synchronous.
  if (is.function(settings$shiny_ask_fn)) {
    ask_fn          <- settings$shiny_ask_fn
    async_gate      <- TRUE
  } else {
    async_gate      <- FALSE
  }
  ask_question_fn <- settings$shiny_ask_question_fn %||% ask_question_fn

  # Set btw.client so btw's subagent tool uses our gateway (Databricks /
  # OpenAI-compatible) instead of falling back to chat_anthropic() which
  # requires ANTHROPIC_API_KEY.  We build a fresh chat for subagents and
  # store it in the btw.client option; this persists for the session lifetime
  # so subagent_resolve_client() finds it at tool execution time.
  if (requireNamespace("btw", quietly = TRUE) && is.null(getOption("btw.client"))) {
    sub_settings <- list(model       = settings$model %||% "claude-sonnet-4-6",
                         base_url    = Sys.getenv("CODEAGENT_BASE_URL", ""),
                         api_key_env = "CODEAGENT_API_KEY")
    btw_chat <- tryCatch(.make_chat(sub_settings, cwd), error = function(e) NULL)
    if (!is.null(btw_chat)) options(btw.client = btw_chat)
  }

  # Core tools -- always register default file tools (Read/Write/Edit/... support
  # absolute paths). When Path A is enabled, ALSO register btw file tools so the
  # LLM has both: btw for hash-anchored project-local edits, default for
  # absolute-path operations. The two sets coexist; the LLM picks based on task.
  register_builtin_tools(chat, mode = mode, rules = rules, ask_fn = ask_fn,
                         sandbox = settings$sandbox, async = async_gate)
  if (isTRUE(getOption("codeagent.use_btw_files", FALSE))) {
    tryCatch(register_btw_file_tools(chat, mode, rules, ask_fn),
             error = function(e) NULL)
  }
  tryCatch(register_web_tools(chat),                          error = function(e) NULL)
  tryCatch(register_run_r_tool(chat, mode, rules, ask_fn,
                               sandbox = settings$sandbox,
                               async = async_gate), error = function(e) NULL)
  tryCatch(register_memory_tool(chat),                        error = function(e) NULL)
  if (!is.null(settings$mcp_config))
    tryCatch(register_mcp_client(chat, settings$mcp_config),  error = function(e) NULL)
  tryCatch(register_task_tools(chat),                         error = function(e) NULL)
  tryCatch(register_todo_tool(chat, settings$session_id %||% "default"),
                                                              error = function(e) NULL)
  tryCatch(register_team_tool(chat, settings$model %||% NULL, cwd),
                                                              error = function(e) NULL)
  # Data exploration tool (opt-in via settings$explore_data = TRUE; default TRUE
  # since ExploreData is read-only and does not modify any data).
  if (!isFALSE(settings$explore_data))
    tryCatch(register_explore_data_tool(chat), error = function(e) NULL)
  # Codebase RAG retrieval (opt-in via settings$rag = TRUE or list(enabled=TRUE);
  # indexing is costly).
  rag_on <- isTRUE(settings$rag) ||
            (is.list(settings$rag) && isTRUE(settings$rag$enabled))
  if (rag_on)
    tryCatch(register_rag_tool(chat, cwd), error = function(e) NULL)
  tryCatch(register_notebook_tools(chat, mode, rules, ask_fn),error = function(e) NULL)
  tryCatch(register_agent_tool(chat, settings$model %||% "claude-sonnet-4-6",
                                mode_env$mode, rules,
                                worktree_isolation = isTRUE(settings$worktree_isolation),
                                ask_fn = ask_fn),
                                                              error = function(e) NULL)
  tryCatch(register_r_tools(chat, groups = settings$btw_groups %||% NULL),
                                                              error = function(e) NULL)
  # Plan-mode tools: let the model enter/exit read-only planning mode. Skip in
  # bypass (nothing to gate) so the model can't lock itself out.
  if (!identical(mode_env$mode, "bypass"))
    tryCatch(register_plan_mode_tools(chat, mode_env), error = function(e) NULL)
  tryCatch({
    st <- .make_skill_tool(cwd)
    if (!is.null(st)) chat$register_tool(st)
  }, error = function(e) NULL)
  # AskUserQuestion: always registered (read-only, all permission modes).
  # ask_question_fn is NULL for CLI (readline path) or a Shiny callback (Phase 3).
  tryCatch(register_ask_user_tool(chat, ask_question_fn, async = async_gate),
           error = function(e) NULL)

  invisible(chat)
}

# ---------------------------------------------------------------------------
# Console ask function
# ---------------------------------------------------------------------------

.console_ask_fn <- function(tool_name, tool_input) {
  cmd <- tool_input[["command"]] %||% tool_input[["file_path"]] %||% "(no details)"
  cat(sprintf("\n[codeagent] Permission request: %s\n  Input: %s\n  Allow? [y/N] ",
              tool_name, substr(as.character(cmd), 1L, 120L)))
  ans <- trimws(readLines(con = stdin(), n = 1L))
  identical(tolower(ans), "y")
}

# ---------------------------------------------------------------------------
# Built-in verify functions
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Enhanced error recovery with classification + backoff
# ---------------------------------------------------------------------------

# Error classification patterns
.ERR_PTL         <- "413|prompt_too_long|context_length_exceeded"
.ERR_RATE_LIMIT  <- "429|rate.limit|too.many.requests|quota"
.ERR_NETWORK     <- "timeout|connection|ECONNREFUSED|ETIMEDOUT|curl"
.ERR_AUTH        <- "401|403|unauthorized|forbidden|invalid.*key"
# ellmer dev warns/errors on truncated / filtered / incomplete responses.
.ERR_TRUNCATED   <- "truncat|incomplete|max_tokens|finish_reason.*length|content.*filter|response.*filtered"

# Read the finish_reason of the most recent assistant turn (ellmer dev
# AssistantTurn$finish_reason): "stop" | "length" | "tool_use" | "content_filter"
# | ... Returns NA_character_ when unavailable.
.last_finish_reason <- function(chat) {
  tryCatch({
    lt <- if (!is.null(chat) && "last_turn" %in% names(chat)) chat$last_turn() else NULL
    fr <- tryCatch(lt@finish_reason, error = function(e) NULL)
    if (is.null(fr) || !length(fr) || !nzchar(fr)) NA_character_ else as.character(fr)
  }, error = function(e) NA_character_)
}

.handle_agent_error <- function(e, chat, input, compaction_ctrl,
                                 max_retries = 3L) {
  msg   <- conditionMessage(e)
  clean <- cli::ansi_strip(msg)

  # PTL: compact then retry once
  if (grepl(.ERR_PTL, clean, ignore.case = TRUE)) {
    compaction_ctrl$handle_ptl_error(chat, error = clean)
    return(tryCatch(
      chat$chat(input),
      error = function(e2) paste0("[PTL Error after compact] ", conditionMessage(e2))
    ))
  }

  # Truncated / filtered / incomplete response: retry once (often transient);
  # surface a clear note if it recurs. (ellmer dev signals these explicitly.)
  if (grepl(.ERR_TRUNCATED, clean, ignore.case = TRUE)) {
    return(tryCatch(
      chat$chat(input),
      error = function(e2) paste0(
        "[Incomplete/truncated response] ", conditionMessage(e2))
    ))
  }

  # Rate limit: exponential backoff up to max_retries
  if (grepl(.ERR_RATE_LIMIT, clean, ignore.case = TRUE)) {
    for (attempt in seq_len(max_retries)) {
      wait_secs <- 2L ^ attempt   # 2, 4, 8 seconds
      message(sprintf("[codeagent] Rate limited. Retry %d/%d in %ds...",
                      attempt, max_retries, wait_secs))
      Sys.sleep(wait_secs)
      result <- tryCatch(chat$chat(input), error = function(e2) e2)
      if (is.character(result)) return(result)
      if (!grepl(.ERR_RATE_LIMIT, conditionMessage(result), ignore.case = TRUE))
        return(paste0("[Error] ", conditionMessage(result)))
    }
    return(paste0("[Rate limit] Gave up after ", max_retries, " retries."))
  }

  # Network: retry with backoff
  if (grepl(.ERR_NETWORK, clean, ignore.case = TRUE)) {
    for (attempt in seq_len(min(max_retries, 2L))) {
      Sys.sleep(attempt)
      result <- tryCatch(chat$chat(input), error = function(e2) e2)
      if (is.character(result)) return(result)
    }
    return(paste0("[Network Error] ", clean))
  }

  # Auth: no retry, surface clearly
  if (grepl(.ERR_AUTH, clean, ignore.case = TRUE))
    return(paste0("[Auth Error] Check CODEAGENT_API_KEY. ", clean))

  # Unknown: surface as-is
  paste0("[Error] ", clean)
}
