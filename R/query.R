#' @title Agent Query Loop
#' @description `codeagent_client()` builds a configured client from any
#'   ellmer Chat. `codeagent()` runs one-shot queries. `agent_loop()` drives
#'   the Shiny app's agentic loop.
#' @name query
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# CodeagentClient S3 class
# ---------------------------------------------------------------------------

#' Wrap an ellmer Chat with codeagent settings into a client object
#'
#' @param chat Ellmer Chat object (already equipped with tools and system prompt).
#' @param settings Named list from [load_settings()].
#' @return Object of class `CodeagentClient`.
#' @keywords internal
.new_client <- function(chat, settings, data_shield = NULL) {
  structure(list(chat = chat, settings = settings, data_shield = data_shield),
            class = "CodeagentClient")
}

#' @export
print.CodeagentClient <- function(x, ...) {
  cat("<CodeagentClient>\n")
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

# Resolve which file-tool set to register: "core" (any path; default), "btw"
# (cwd-only hash-anchored), or "both". settings$file_tools wins; falls back to
# the legacy options(codeagent.use_btw_files) flag (TRUE == "both").
.resolve_file_tools <- function(settings = list()) {
  ft <- settings$file_tools %||% getOption("codeagent.file_tools", NULL) %||%
    (if (isTRUE(getOption("codeagent.use_btw_files", FALSE))) "both" else "core")
  match.arg(as.character(ft), c("core", "btw", "both"))
}

# Bind reviewers to verified clones of the current parent Chat. Rebinding is
# intentional after Route B so reviewers never retain the previous provider.
.bind_data_shield_reviewer_factory <- function(shield, parent_chat, settings,
                                               cwd = getwd()) {
  if (!inherits(shield, "DataShield") ||
      shield$coverage()$reviewers <= 0L || !inherits(parent_chat, "Chat"))
    return(invisible(FALSE))
  shield$bind_reviewer_factory(function(model = NULL) {
    clone <- parent_chat$clone()
    expected_provider <- parent_chat$get_provider()
    expected_model <- parent_chat$get_model_object()
    target <- model %||% expected_model@name
    clone$set_model(target)
    clone$set_turns(list())
    clone$set_tools(list())
    got_model <- clone$get_model_object()
    if (!.provider_configuration_equal(expected_provider,
                                        clone$get_provider()) ||
        !.model_configuration_equal(expected_model, got_model,
                                     include_name = FALSE) ||
        !identical(got_model@name, target) ||
        length(clone$get_turns()) != 0L || length(clone$get_tools()) != 0L)
      stop("reviewer Chat clone isolation verification failed", call. = FALSE)
    clone
  })
  invisible(TRUE)
}

#' Create a codeagent client from any ellmer Chat
#'
#' Injects codeagent tools (Bash, Read, Write, Edit, Glob, Grep, LS, btw tools,
#' skill tool) and rebuilds the system prompt. The returned `CodeagentClient`
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
#' @param max_budget_usd Numeric or NULL (default). Hard dollar-cost cap for
#'   this client's `chat` (mirrors Claude Code's `maxBudgetUsd`), checked
#'   alongside the token budget in [agent_loop()] via `chat$get_cost()`. NULL
#'   (default) means no cap. Only takes effect where ellmer has price data for
#'   the provider/model; unpriced custom endpoints (e.g. a Databricks/Azure
#'   serving endpoint ellmer doesn't recognize) report cost `$0` forever, so
#'   the cap silently never fires there -- this is a known limitation, not a
#'   bug (see `CODEAGENT_MAX_BUDGET_USD` env var / `max_budget_usd` in
#'   settings.json for the same knob without a client-code change).
#' @param register_tools Logical. If `TRUE` (default) register all tools now.
#'   `FALSE` returns a lightweight shell (chat + settings + system prompt, no
#'   tools) so callers (e.g. [codeagent_app()]) can render UI first and defer the
#'   expensive tool registration; call [.register_all_tools()] later.
#' @param data_shield `NULL` (off), a strategy list from `shield_*()` (creates a
#'   private [DataShield] R6), or an explicit [DataShield] instance shared by
#'   selected chat threads. For a harness-only client, attach tools then call
#'   `client$data_shield$install(client$chat)`.
#' @return Object of class `CodeagentClient` with `$chat`, `$settings`, and
#'   `$data_shield` (NULL when disabled).
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
  mcp_config         = NULL,
  register_tools     = TRUE,
  data_shield        = NULL,
  max_budget_usd     = NULL
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
  if (!is.null(max_budget_usd) &&
      (!is.numeric(max_budget_usd) || length(max_budget_usd) != 1L ||
       is.na(max_budget_usd) || max_budget_usd <= 0))
    cli::cli_abort("{.arg max_budget_usd} must be NULL or a single positive number.")

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
  # NULL (default) preserves whatever settings.json/CODEAGENT_MAX_BUDGET_USD
  # already loaded; only an explicit caller value overrides it.
  if (!is.null(max_budget_usd)) settings$max_budget_usd <- as.numeric(max_budget_usd)
  shield_state <- .data_shield_resolve(data_shield)
  settings$data_shield <- if (is.null(shield_state)) NULL else shield_state$coverage()$config
  settings$data_shield_engine <- shield_state

  # Declarative hooks from settings.json -> live HookRegistry (M5 closing).
  settings$hooks_registry      <- tryCatch(.hooks_from_settings(settings),
                                           error = function(e) NULL)

  # Replay InstructionsLoaded for each CLAUDE.md-style file that contributed
  # context. The load happened inside load_settings() (before hooks existed),
  # so we replay from the recorded path list. memory_type/load_reason are
  # best-effort approximations -- see .load_claude_md and run_instructions_loaded.
  if (!is.null(settings$hooks_registry)) {
    loaded <- attr(settings$claude_md, "loaded_files") %||% character(0)
    home_n <- tryCatch(normalizePath("~", mustWork = FALSE), error = function(e) "~")
    for (fp in loaded) {
      mtype <- if (startsWith(fp, home_n)) "User" else "Project"
      tryCatch(settings$hooks_registry$run_instructions_loaded(
        fp, mtype, "session_start", list()), error = function(e) NULL)
    }
  }

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

  if (inherits(shield_state, "DataShield"))
    tryCatch(.bind_data_shield_reviewer_factory(
      shield_state, chat, settings, cwd), error = function(e) NULL)

  ask_fn <- if (interactive()) .console_ask_fn else NULL
  if (interactive() && inherits(shield_state,"DataShield") &&
      !isTRUE(shield_state$coverage()$egress_approval_callback))
    shield_state$set_egress_ask(.console_egress_ask_fn)
  # register_tools = FALSE returns a cheap "shell" client (chat + settings +
  # system prompt, no tools registered) so callers like codeagent_app() can
  # render the UI instantly and defer the expensive tool registration
  # (btw_tools, skill scanning) to a progress-reported in-server step.
  if (isTRUE(register_tools)) {
    .register_all_tools(chat, settings, ask_fn = ask_fn)
    # Auto-connect MCP servers declared in settings.json (P2 closing). The
    # mcp_config param still works; this adds servers from the settings file.
    tryCatch(.mcp_autoconnect(chat, settings), error = function(e) NULL)
  }

  # Data Shield (opt-in): install its R6 policy engine after tool registration.
  # Harness-only hosts attach tools then call client$data_shield$install(chat).
  if (isTRUE(register_tools) && !is.null(shield_state))
    tryCatch(shield_state$install(chat), error = function(e) NULL)

  .new_client(chat, settings, data_shield = shield_state)
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
#' codeagent("List all .R files", model = "gpt-4.1", permission_mode = "bypass")
#' ```
#'
#' @param client_or_prompt Either a `CodeagentClient` (from [codeagent_client()])
#'   or a character prompt string (legacy mode).
#' @param prompt Character. The user prompt. Required when `client_or_prompt`
#'   is a `CodeagentClient`; unused in legacy mode.
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
  # Dispatch: new style (CodeagentClient) vs legacy (prompt string)
  if (inherits(client_or_prompt, "CodeagentClient")) {
    client <- client_or_prompt
    if (is.null(prompt))
      stop("'prompt' must be provided when 'client_or_prompt' is a CodeagentClient.",
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

  # Input gate (edge 1) + output gate (edge 3) also guard the one-shot path
  # (kiro round-2 #2): codeagent() used to call chat$chat(prompt) directly, so a
  # protected value pasted into the prompt, or reproduced in the reply, bypassed
  # both edges. Reuse the same gates as agent_loop / the Shiny stream.
  ig <- .input_gate_guarded(prompt, settings, chat)
  if (identical(ig$action, "block"))
    return(ig$text %||% "[Blocked by Data Shield input gate]")
  prompt <- ig$input %||% prompt

  response <- tryCatch(
    .with_codeagent_span(
      "codeagent.query",
      attributes = list(
        "codeagent.model"           = settings$model %||% "(auto)",
        "codeagent.permission_mode" = settings$permission_mode %||% "default"),
      function() chat$chat(prompt)
    ),
    error = function(e) paste0("[Error] ", conditionMessage(e))
  )
  if (!is.character(response)) return("[No response]")
  # Citation markers are resolved only against source records from this round,
  # then the complete deterministic output passes through the response gate.
  if (.web_citations_enabled(settings$web_citations))
    response <- .render_turn_citations(
      response, .citation_registry_from_last_round(chat), settings, chat)
  og <- .output_gate_guarded(response, settings, chat)
  og$text %||% response
}

# ---------------------------------------------------------------------------
# agent_loop() -- used by the Shiny app
# ---------------------------------------------------------------------------

#' Main agentic query loop
#'
#' Handles a single user turn. Accepts either a `CodeagentClient` (new style)
#' or the legacy `(chat, settings)` pair.
#'
#' @param user_input Character. User message.
#' @param client A `CodeagentClient` (from [codeagent_client()]), or an
#'   `ellmer::Chat` for legacy use.
#' @param settings Named list. Only needed in legacy mode (ignored when
#'   `client` is a `CodeagentClient`).
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
  # Resolve chat + settings from CodeagentClient or legacy pair
  if (inherits(client, "CodeagentClient")) {
    chat     <- client$chat
    settings <- client$settings
  } else {
    # Legacy: client is the bare Chat object
    chat <- client
    if (is.null(settings))
      settings <- load_settings(cwd %||% getwd())
  }
  if (is.null(cwd)) cwd <- settings$cwd %||% getwd()
  # Hooks fallback (kiro round-2 #2): a bare `agent_loop(user_input, client)`
  # call passes hooks=NULL, so UserPromptSubmit / lifecycle hooks silently never
  # fired even when the client's settings carry a registry. Recover it here so
  # every entry point sees the same hooks without the caller threading it.
  if (is.null(hooks)) hooks <- settings$hooks_registry

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

  # 1a.5 Fire UserPromptSubmit hook BEFORE reminder injection (CC parity): a
  #   hook may block the turn (prompt never reaches the model) or append
  #   additional_context. It acts on the raw user_input only -- the reminder is
  #   framework-injected ambient text, not user-typed content. NEVER rewrites
  #   the user's original text (matching CC's UserPromptSubmit contract).
  ups_context <- NULL
  if (!is.null(hooks)) {
    ups <- tryCatch(hooks$run_user_prompt_submit(user_input),
                    error = function(e) list(action = "allow"))
    if (identical(ups$action, "block")) {
      if (!is.null(session_id))
        tryCatch(save_session(chat, cwd, session_id), error = function(e) NULL)
      return(list(response    = ups$message %||% "[Blocked by UserPromptSubmit hook]",
                  session_id  = session_id,
                  stop_reason = "hook_blocked"))
    }
    ups_context <- ups$additional_context
  }

  # 1a.6 Data Shield input gate (edge 1): the shield's own confidentiality
  #   scan of the user input. SEPARATE system from the hook above -- unlike the
  #   hook it MAY redact (replace protected values / PII the user pasted in,
  #   keeping the rest of the text). block -> reject the turn; redact -> continue
  #   with the sanitized text. This is the Data Shield half of the input gate
  #   (hooks half is the UserPromptSubmit hook above); see R/input_gate.R.
  ig <- .input_gate_guarded(user_input, settings, chat)
  if (identical(ig$action, "block")) {
    if (!is.null(session_id))
      tryCatch(save_session(chat, cwd, session_id), error = function(e) NULL)
    return(list(response    = ig$text %||% "[Blocked by Data Shield input gate]",
                session_id  = session_id,
                stop_reason = "shield_blocked"))
  }
  user_input <- ig$input %||% user_input   # may be redacted; rest preserved

  # 1b. Inject system-reminder (dynamic context into user message, not system prompt)
  #     This mirrors Claude Code's <system-reminder> pattern: ephemeral metadata
  #     injected at message time so it doesn't invalidate the prompt cache. Any
  #     UserPromptSubmit additional_context is appended here too (append-only).
  reminder <- .build_system_reminder(settings, iteration, cwd, query = user_input)
  if (!is.null(ups_context) && nzchar(ups_context))
    reminder <- if (nzchar(reminder)) paste0(reminder, "\n\n", ups_context) else ups_context
  actual_input <- if (nzchar(reminder))
    paste0(user_input, "\n\n", reminder)
  else
    user_input

  # 2. Budget check (token ratio/diminishing-returns + optional USD hard cap)
  current_tokens <- estimate_tokens(chat)
  current_cost   <- tryCatch(.current_cost_usd(chat), error = function(e) NA_real_)
  if (budget_tracker$should_stop(current_tokens,
                                   settings$model_limit %||% 200000L,
                                   iteration,
                                   current_cost_usd = current_cost,
                                   max_budget_usd    = settings$max_budget_usd)) {
    budget_usd  <- settings$max_budget_usd
    usd_capped  <- !is.null(budget_usd) && !is.na(current_cost) &&
                    current_cost >= budget_usd
    reason  <- if (usd_capped) "budget_usd_exceeded" else "budget_exceeded"
    stop_msg <- if (usd_capped)
      sprintf("[Budget exceeded: cost $%.4f reached the $%.4f cap -- stopping agent loop]",
              current_cost, budget_usd)
    else "[Budget exceeded: stopping agent loop]"
    if (!is.null(hooks)) tryCatch(
      hooks$run_stop(reason, list(tokens = current_tokens, cost_usd = current_cost)),
      error = function(e) NULL)
    return(list(response    = stop_msg,
                session_id  = session_id,
                stop_reason = reason))
  }

  # 3. Cheap resource management before summary decisions
  resource_changed <- isTRUE(tryCatch(
    resource_state$maybe_replace(chat),
    error = function(e) FALSE
  ))

  # 4. Adaptive compaction; the controller fires lifecycle hooks only when the
  # request is over threshold and emits sanitized PostCompact metadata on change.
  compaction_ctrl$maybe_compact(
    chat,
    settings$model_limit %||% 200000L,
    compact_model = .resolve_compact_model(chat, settings),
    model = settings$model %||% "",
    hooks = hooks,
    use_provider_usage = !resource_changed
  )

  # 5. Send (with system-reminder injected into actual_input)
  response <- tryCatch({
    chat$chat(actual_input)
  }, error = function(e) {
    .handle_agent_error(e, chat, actual_input, compaction_ctrl, hooks = hooks)
  })

  if (!is.character(response)) response <- "[No text response]"

  # 6b. Verification must settle the actual final AssistantTurn before its
  # finish reason is read.
  verify_fn <- settings$verify_fn
  if (!is.null(verify_fn) && is.function(verify_fn)) {
    verify_result <- tryCatch(verify_fn(response, chat, cwd), error = function(e) {
      list(passed = FALSE, message = conditionMessage(e))
    })
    if (!isTRUE(verify_result$passed)) {
      verify_msg <- verify_result$message %||% "Verification failed."
      re_input <- paste0(
        "The previous response had verification failures. Please fix:\n\n",
        verify_msg)
      re_response <- tryCatch(chat$chat(re_input),
        error = function(e) paste0("[Verify retry error] ", conditionMessage(e)))
      if (is.character(re_response)) response <- re_response
    }
  }

  # 7. Map the final reason once, append only a static note, then gate the full
  # visible response before any hook/callback can observe it.
  finish <- .map_finish_reason(.last_finish_reason(chat))
  response <- .append_finish_note(response, finish$note)
  if (.web_citations_enabled(settings$web_citations))
    response <- .render_turn_citations(
      response, .citation_registry_from_last_round(chat), settings, chat)
  og <- .output_gate_guarded(response, settings, chat)
  if (!identical(og$action, "pass")) response <- og$text %||% response

  if (!is.null(hooks)) tryCatch(
    hooks$run_assistant_message(response), error = function(e) NULL)

  if (!is.null(session_id))
    tryCatch(save_session(
      chat, cwd, session_id, assistant_text_override = response),
      error = function(e) NULL)

  if (!is.null(hooks)) tryCatch(
    hooks$run_stop(finish$stop_reason, list(
      session_id = session_id, finish_reason = finish$finish_reason)),
    error = function(e) NULL)

  list(response = response, session_id = session_id,
       stop_reason = finish$stop_reason,
       finish_reason = finish$finish_reason)
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
  # Shiny path -- the CLI/one-shot path leaves them NULL and stays synchronous.
  if (is.function(settings$shiny_ask_fn)) {
    ask_fn          <- settings$shiny_ask_fn
    async_gate      <- TRUE
  } else {
    async_gate      <- FALSE
  }
  ask_question_fn <- settings$shiny_ask_question_fn %||% ask_question_fn

  # Core tools -- file-tool set is selectable (settings$file_tools):
  #   "core" (default): codeagent Read/Write/Edit/MultiEdit/Glob/Grep/LS -- work
  #                     on ANY path (absolute or relative), not limited to cwd.
  #   "btw"           : btw file tools only -- hash-anchored, atomic patch, but
  #                     btw restricts operations to the project cwd.
  #   "both"          : register both sets; the LLM picks per task.
  # Back-compat: options(codeagent.use_btw_files = TRUE) == "both".
  file_tools <- .resolve_file_tools(settings)
  # Approach A: build sensitive tools UNGATED (mode = "bypass", synchronous) and
  # let the single central gate (.install_permission_gate, installed at the end)
  # be the sole permission authority for EVERY tool -- native, btw, Format, MCP.
  register_builtin_tools(chat, mode = "bypass", rules = rules, ask_fn = NULL,
                         sandbox = settings$sandbox, async = FALSE,
                         skip_file_tools = identical(file_tools, "btw"))
  if (file_tools %in% c("btw", "both")) {
    tryCatch(register_btw_file_tools(chat, "bypass", rules, NULL),
             error = function(e) NULL)
  }
  tryCatch(register_web_tools(chat, citations = .web_citations_enabled(settings$web_citations)),
                                                              error = function(e) NULL)
  tryCatch(register_run_r_tool(chat, "bypass", rules, NULL,
                               sandbox = settings$sandbox,
                               async = FALSE), error = function(e) NULL)
  tryCatch(register_memory_tool(chat),                        error = function(e) NULL)
  tryCatch(register_lint_tools(chat),                         error = function(e) NULL)
  if (!is.null(settings$mcp_config))
    tryCatch(register_mcp_client(chat, settings$mcp_config),  error = function(e) NULL)
  tryCatch(register_task_tools(chat, settings$hooks_registry),
                                                              error = function(e) NULL)
  # Opt-in: reuse btw's task helpers (skill/README/context) as LLM tools.
  tryCatch(register_btw_task_tools(chat, settings),           error = function(e) NULL)
  tryCatch(register_todo_tool(chat, settings$session_id %||% "default"),
                                                              error = function(e) NULL)
  parent_model <- tryCatch(chat$get_model_object()@name,
                           error = function(e) settings$model %||% NULL)
  tryCatch(register_team_tool(chat, parent_model, cwd),
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
  tryCatch(register_notebook_tools(chat, "bypass", rules, NULL),error = function(e) NULL)
  tryCatch(register_agent_tool(chat, parent_model,
                                "bypass", rules,
                                worktree_isolation = isTRUE(settings$worktree_isolation),
                                ask_fn = NULL,
                                async = isTRUE(settings$async_subagents),
                                data_shield = settings$data_shield_engine,
                                cwd = cwd, parent_chat = chat,
                                hooks = settings$hooks_registry),
                                                              error = function(e) NULL)
  # Background (non-blocking) sub-agent tool -- opt-in, requires mirai.
  if (isTRUE(settings$background_agents))
    tryCatch(register_background_agent_tool(chat, settings$data_shield_engine),
             error = function(e) NULL)
  # Agent tools are owned by register_agent_tool() above. The internal path
  # excludes btw_tool_agent_* so a raw upstream delegator cannot bypass
  # worktree/async/Data Shield semantics. The exported register_r_tools() keeps
  # groups="agent" compatibility for standalone callers.
  tryCatch(.register_r_tools_impl(chat, groups = settings$btw_groups %||% NULL,
                                  include_agent = FALSE),
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
  # Mid-loop compaction: check the complete outgoing context before every model
  # request via on_request_start. No-op unless settings$midloop_compact = TRUE.
  tryCatch(register_midloop_compaction(chat, settings), error = function(e) NULL)

  # Single central permission gate (approach A): the sole authority over every
  # tool. Sync (console ask_fn) and async (Shiny shiny_ask_fn promise) both ride
  # ellmer's rejectable on_tool_request. Installed last so it sees all tools.
  gate_ask_fn <- settings$shiny_ask_fn %||% ask_fn
  gate_hooks  <- settings$hooks_registry %||%
                 tryCatch(.hooks_from_settings(settings), error = function(e) NULL)
  # Normalize complex list/data.frame results inside ToolDefs before ellmer sees
  # them; already-normalized Content/image/PDF values pass through unchanged.
  tryCatch(.install_tool_result_normalizers(chat),
           error = function(e) stop(conditionMessage(e), call. = FALSE))
  # PreToolUse updatedInput: wrap tools so a hook can rewrite arguments before
  # execution. Installed BEFORE the gate so the gate still sees original args
  # (a rewrite cannot bypass permission checks). No-op when no hooks.
  tryCatch(.install_tool_input_hooks(chat, gate_hooks), error = function(e) NULL)
  tryCatch(.install_permission_gate(chat, settings, mode_env, rules,
                                    ask_fn = gate_ask_fn, hooks = gate_hooks),
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

# Sync CLI egress approval. Never prints the raw result.
.console_egress_ask_fn <- function(event) {
  cat(sprintf(
    "\n[codeagent] Data Shield egress review\n  Tool: %s\n  Strategy: %s\n  Reason: %s\n  Matches: %d\n",
    event$tool_name %||% "?", event$strategy %||% "?",
    event$reason %||% "policy match", as.integer(event$match_count %||% 0L)))
  choices <- c("Redact and continue", "Block result")
  if (isTRUE(event$allow_raw_approval)) choices <- c(choices,"ALLOW RAW ONCE (dangerous)")
  for (i in seq_along(choices)) cat(sprintf("  %d) %s\n",i,choices[[i]]))
  cat("Choice [1]: ")
  answer <- suppressWarnings(as.integer(trimws(readLines(con=stdin(),n=1L))))
  if (is.na(answer) || answer < 1L || answer > length(choices)) answer <- 1L
  c("redact","block","raw_once")[[answer]]
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

# Normalize provider/current/legacy finish reasons at one boundary. The raw
# reason is retained for diagnostics; notes are static and safe to pass through
# the output gate.
.map_finish_reason <- function(finish_reason) {
  raw <- if (is.null(finish_reason) || !length(finish_reason))
    NA_character_ else as.character(finish_reason)[1L]
  key <- if (is.na(raw) || !nzchar(raw)) "" else tolower(trimws(raw))
  stop_reason <- switch(key,
    success =, stop = "completed",
    max_tokens =, context_window =, length = "truncated",
    content_filter = "filtered",
    tool_use = "incomplete_tool_use",
    "completed")
  note <- switch(stop_reason,
    truncated = "[Note: response was truncated at the model's output-token or context limit.]",
    filtered = "[Note: response was filtered by the model provider's safety policy.]",
    incomplete_tool_use = "[Note: response ended with an unresolved tool request.]",
    NULL)
  list(stop_reason = stop_reason, finish_reason = raw, note = note)
}

.append_finish_note <- function(text, note) {
  text <- as.character(text %||% "")[1L]
  if (is.null(note) || !length(note) || is.na(note) || !nzchar(note)) return(text)
  if (nzchar(text)) paste0(text, "\n\n", note) else note
}

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

.retry_pending_request <- function(chat, pending_turn, fallback_input) {
  if (is.null(pending_turn)) return(chat$chat(fallback_input))

  private <- tryCatch(environment(chat$chat)$private,
                      error = function(e) NULL)
  chat_impl <- tryCatch(private$chat_impl, error = function(e) NULL)
  if (!is.function(chat_impl)) {
    has_tool_result <- length(.turn_tool_result_ids(pending_turn)) > 0L
    if (has_tool_result) {
      stop(
        "Exact PTL retry is unavailable for a pending tool result.",
        call. = FALSE
      )
    }
    contents <- tryCatch(pending_turn@contents, error = function(e) NULL)
    if (is.null(contents)) return(chat$chat(fallback_input))
    return(do.call(chat$chat, contents))
  }

  # The pinned ellmer public chat() first synthesizes results for dangling tool
  # requests. Submit the already-built pending UserTurn through chat_impl so its
  # real tool result is present exactly once while preserving request callbacks.
  coro::collect(chat_impl(
    pending_turn,
    stream = FALSE,
    echo = "none"
  ))
  text <- tryCatch(chat$last_turn()@text, error = function(e) "")
  paste(as.character(text %||% ""), collapse = "")
}

.handle_agent_error <- function(e, chat, input, compaction_ctrl,
                                 max_retries = 3L, hooks = NULL) {
  msg   <- conditionMessage(e)
  clean <- cli::ansi_strip(msg)

  # Fire StopFailure + Notification at a genuinely-terminal error return (a
  # give-up path), NOT on paths that recover via retry. Returns `txt` so callers
  # can `return(.fail(...))` inline.
  .fail <- function(txt, detail = clean) {
    if (!is.null(hooks)) {
      tryCatch(hooks$run_stop_failure(detail, list(input = input)),
               error = function(e2) NULL)
      tryCatch(hooks$run_notification(txt, "error", list()),
               error = function(e2) NULL)
    }
    txt
  }

  # PTL: compact pair-safe history then retry the failed pending request once.
  if (grepl(.ERR_PTL, clean, ignore.case = TRUE)) {
    pending_turn <- attr(chat, "codeagent_pending_request_turn", exact = TRUE)
    compaction_ctrl$handle_ptl_error(
      chat,
      error = clean,
      pending_turn = pending_turn
    )
    retry_request <- function() {
      .retry_pending_request(chat, pending_turn, input)
    }
    return(tryCatch(
      retry_request(),
      error = function(e2) .fail(paste0("[PTL Error after compact] ",
                                        conditionMessage(e2)), conditionMessage(e2))
    ))
  }

  # Truncated / filtered / incomplete response: retry once (often transient);
  # surface a clear note if it recurs. (ellmer dev signals these explicitly.)
  if (grepl(.ERR_TRUNCATED, clean, ignore.case = TRUE)) {
    return(tryCatch(
      chat$chat(input),
      error = function(e2) .fail(paste0(
        "[Incomplete/truncated response] ", conditionMessage(e2)),
        conditionMessage(e2))
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
        return(.fail(paste0("[Error] ", conditionMessage(result)),
                     conditionMessage(result)))
    }
    return(.fail(paste0("[Rate limit] Gave up after ", max_retries, " retries.")))
  }

  # Network: retry with backoff
  if (grepl(.ERR_NETWORK, clean, ignore.case = TRUE)) {
    for (attempt in seq_len(min(max_retries, 2L))) {
      Sys.sleep(attempt)
      result <- tryCatch(chat$chat(input), error = function(e2) e2)
      if (is.character(result)) return(result)
    }
    return(.fail(paste0("[Network Error] ", clean)))
  }

  # Auth: no retry, surface clearly
  if (grepl(.ERR_AUTH, clean, ignore.case = TRUE))
    return(.fail(paste0("[Auth Error] Check CODEAGENT_API_KEY. ", clean)))

  # Unknown: surface as-is
  .fail(paste0("[Error] ", clean))
}
