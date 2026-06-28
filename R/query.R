#' @title Agent Query Loop
#' @description `codeagent_client()` builds a configured client from any
#'   ellmer Chat. `codeagent()` runs one-shot queries. `query_loop()` drives
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
  if (!is.null(settings$base_url) && nzchar(settings$base_url)) {
    api_key_env <- settings$api_key_env %||% "CODEAGENT_API_KEY"
    ellmer::chat_openai_compatible(
      base_url      = settings$base_url,
      model         = settings$model,
      credentials   = function() Sys.getenv(api_key_env),
      system_prompt = sp,
      ...
    )
  } else {
    ellmer::chat_anthropic(
      model         = settings$model,
      system_prompt = sp,
      ...
    )
  }
}

# ---------------------------------------------------------------------------
# codeagent_client() — the primary configuration entry point
# ---------------------------------------------------------------------------

#' Create a codeagent client from any ellmer Chat
#'
#' Injects codeagent tools (Bash, Read, Write, Edit, Glob, Grep, LS, btw tools,
#' skill tool) and rebuilds the system prompt. The returned `CodagentClient`
#' is the single object passed to [codeagent()] and [codeagent_app()].
#'
#' @param chat An `ellmer::Chat` object — any backend supported by ellmer:
#'   `chat_openai_compatible()`, `chat_anthropic()`, `chat_ollama()`, etc.
#'   If NULL, a chat is auto-built from `CODEAGENT_BASE_URL`/`CODEAGENT_MODEL`
#'   env vars (or Anthropic defaults).
#' @param permission_mode Character. One of [PermissionMode].
#' @param rules List of [PermissionRule()] objects.
#' @param cwd Character. Working directory (used for CLAUDE.md, skills, sessions).
#' @param max_turns Integer. Maximum agentic loop turns.
#' @param btw_groups Character vector or NULL. btw tool groups to register
#'   (e.g. `c("docs","git","pkg")`). NULL = all available groups.
#' @return Object of class `CodagentClient` with slots `$chat` and `$settings`.
#' @export
codeagent_client <- function(
  chat            = NULL,
  permission_mode = "default",
  rules           = list(),
  cwd             = getwd(),
  max_turns       = 100L,
  btw_groups      = NULL
) {
  settings <- load_settings(cwd)
  settings$permission_mode <- permission_mode
  settings$rules           <- rules
  settings$cwd             <- cwd
  settings$max_turns       <- as.integer(max_turns)
  settings$btw_groups      <- btw_groups

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

  .new_client(chat, settings)
}

# ---------------------------------------------------------------------------
# codeagent() — one-shot query
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
# query_loop() — used by the Shiny app
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
query_loop <- function(user_input,
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
    return(list(response    = sprintf("[Max turns (%d) reached: stopping agent loop]", max_turns),
                session_id  = session_id,
                stop_reason = "max_turns"))
  }

  # 2. Budget check
  current_tokens <- estimate_tokens(chat)
  if (budget_tracker$should_stop(current_tokens,
                                   settings$model_limit %||% 200000L,
                                   iteration)) {
    return(list(response    = "[Budget exceeded: stopping agent loop]",
                session_id  = session_id,
                stop_reason = "budget_exceeded"))
  }

  # 3. Compaction
  compaction_ctrl$maybe_compact(chat, settings$model_limit %||% 200000L)

  # 4. Resource management
  resource_state$maybe_replace(chat)

  # 5. Send
  response <- tryCatch({
    chat$chat(user_input)
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("413|prompt_too_long", msg, ignore.case = TRUE)) {
      compaction_ctrl$handle_ptl_error(chat)
      tryCatch(chat$chat(user_input),
               error = function(e2) paste0("[Error] ", conditionMessage(e2)))
    } else {
      paste0("[Error] ", msg)
    }
  })

  if (!is.character(response)) response <- "[No text response]"

  # 6. Save session
  if (!is.null(session_id))
    tryCatch(save_session(chat, cwd, session_id), error = function(e) NULL)

  list(response = response, session_id = session_id, stop_reason = "completed")
}

# ---------------------------------------------------------------------------
# Tool registration helper
# ---------------------------------------------------------------------------

#' Register all codeagent tools to a Chat object
#'
#' @param chat An `ellmer::Chat` object.
#' @param settings Named list from [load_settings()].
#' @param ask_fn Function or NULL.
#' @return Invisibly `chat`.
#' @export
.register_all_tools <- function(chat, settings, ask_fn = NULL) {
  mode  <- settings$permission_mode %||% "default"
  rules <- settings$rules %||% list()
  cwd   <- settings$cwd %||% getwd()

  register_builtin_tools(chat, mode = mode, rules = rules, ask_fn = ask_fn)
  tryCatch(register_web_tools(chat),                          error = function(e) NULL)
  tryCatch(register_task_tools(chat),                         error = function(e) NULL)
  tryCatch(register_notebook_tools(chat, mode, rules, ask_fn),error = function(e) NULL)
  tryCatch(register_agent_tool(chat, settings$model %||% "claude-sonnet-4-6",
                                mode, rules),                 error = function(e) NULL)
  tryCatch(register_r_tools(chat, groups = settings$btw_groups %||% NULL),
                                                              error = function(e) NULL)
  tryCatch({
    st <- .make_skill_tool(cwd)
    if (!is.null(st)) chat$register_tool(st)
  }, error = function(e) NULL)

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
