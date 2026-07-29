#' @title Background (non-blocking) sub-agents
#' @description Fire-and-forget sub-agents that run in a `mirai` daemon so the
#'   main REPL / turn continues immediately (unlike `team_run()`, which waits).
#'   Results are polled and surfaced back to the model on a later turn via the
#'   system reminder -- mirroring Claude Code's async agents
#'   (`createAsyncAgentAttachmentsIfNeeded`). Opt-in via
#'   `settings$background_agents`; requires the `mirai` package.
#' @name async_agent
#' @keywords internal
NULL

# Dedicated mirai compute profile so background agents never clash with, or get
# torn down by, team_run()/team_coordinate() (which use the default profile).
.BG_COMPUTE <- "codeagent_bg"

# In-memory registry: id (chr) -> list(id, prompt, status, result, retrieved,
# mirai, started). Package-internal env, one per R session.
.bg_state <- new.env(parent = emptyenv())
.bg_state$agents  <- list()
.bg_state$counter <- 0L
.bg_state$daemons <- FALSE

.bg_available <- function() requireNamespace("mirai", quietly = TRUE)

.bg_ensure_daemons <- function(n = 2L) {
  if (isTRUE(.bg_state$daemons)) return(invisible())
  ok <- tryCatch({ mirai::daemons(n, .compute = .BG_COMPUTE); TRUE },
                 error = function(e) FALSE)
  if (isTRUE(ok)) .bg_state$daemons <- TRUE
  invisible()
}

# For tests / shutdown.
.bg_shutdown <- function() {
  tryCatch(mirai::daemons(0L, .compute = .BG_COMPUTE), error = function(e) NULL)
  .bg_state$daemons <- FALSE
  .bg_state$agents  <- list()
  invisible()
}

#' Spawn a background sub-agent. Returns the task id immediately (fire-and-forget).
#' @keywords internal
.bg_spawn <- function(prompt, model = NULL, cwd = getwd()) {
  if (!.bg_available())
    return(structure("[background agents require the mirai package]",
                     class = "bg_error"))
  .bg_ensure_daemons()
  model    <- model %||% Sys.getenv("CODEAGENT_MODEL", "")
  base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  api_key  <- Sys.getenv("CODEAGENT_API_KEY", "")
  m <- tryCatch(
    mirai::mirai(
      {
        Sys.setenv(CODEAGENT_BASE_URL = base_url, CODEAGENT_API_KEY = api_key,
                   CODEAGENT_MODEL = model)
        suppressMessages(suppressWarnings(library(codeagent)))
        tryCatch({
          client <- codeagent::codeagent_client(permission_mode = "bypass",
                                                 cwd = cwd, btw_groups = NULL)
          codeagent::codeagent(client, prompt)
        }, error = function(e) paste0("[Error] ", conditionMessage(e)))
      },
      prompt = prompt, model = model, base_url = base_url,
      api_key = api_key, cwd = cwd, .compute = .BG_COMPUTE),
    error = function(e) NULL)
  if (is.null(m))
    return(structure("[failed to spawn background agent]", class = "bg_error"))
  .bg_state$counter <- .bg_state$counter + 1L
  id <- as.character(.bg_state$counter)
  .bg_state$agents[[id]] <- list(id = id, prompt = prompt, status = "running",
                                 result = NULL, retrieved = FALSE,
                                 mirai = m, started = Sys.time())
  id
}

#' Poll running background agents; move resolved ones to "done".
#' @keywords internal
.bg_poll <- function() {
  for (id in names(.bg_state$agents)) {
    a <- .bg_state$agents[[id]]
    if (!identical(a$status, "running")) next
    if (is.null(a$mirai)) next   # no handle to poll (defensive)
    resolved <- tryCatch(!mirai::unresolved(a$mirai), error = function(e) FALSE)
    if (isTRUE(resolved)) {
      val <- tryCatch(a$mirai$data, error = function(e) NULL)
      if (inherits(val, "miraiError") || inherits(val, "errorValue") ||
          is.null(val))
        val <- paste0("[Error] background agent #", id, " failed")
      a$status    <- "done"
      a$result    <- if (is.character(val)) val
                     else "[background agent: no text result]"
      a$mirai     <- NULL   # release the mirai handle
      .bg_state$agents[[id]] <- a
    }
  }
  invisible()
}

# Completed-but-unretrieved agents; marks them retrieved so they surface once.
.bg_take_completed <- function() {
  out <- list()
  for (id in names(.bg_state$agents)) {
    a <- .bg_state$agents[[id]]
    if (identical(a$status, "done") && !isTRUE(a$retrieved)) {
      out[[length(out) + 1L]] <- a
      a$retrieved <- TRUE
      .bg_state$agents[[id]] <- a
    }
  }
  out
}

.bg_running <- function()
  Filter(function(a) identical(a$status, "running"), .bg_state$agents)

#' Status data.frame of all background agents (polls first).
#' @keywords internal
.bg_status <- function() {
  .bg_poll()
  ag <- .bg_state$agents
  if (!length(ag))
    return(data.frame(id = character(0), status = character(0),
                      prompt = character(0), stringsAsFactors = FALSE))
  data.frame(
    id     = vapply(ag, function(a) a$id, character(1)),
    status = vapply(ag, function(a) a$status, character(1)),
    prompt = vapply(ag, function(a) substr(a$prompt, 1L, 60L), character(1)),
    stringsAsFactors = FALSE, row.names = NULL)
}

# System-reminder block: completed (unretrieved) results + running notices.
# Returns "" when there is nothing to report. Mirrors Claude Code's
# createAsyncAgentAttachmentsIfNeeded (surface results + avoid duplicate spawn).
.bg_reminder_block <- function() {
  if (!length(.bg_state$agents)) return("")
  .bg_poll()
  done    <- .bg_take_completed()
  running <- .bg_running()
  if (!length(done) && !length(running)) return("")
  lines <- character(0)
  if (length(done)) {
    lines <- c(lines, "Background sub-agent results now available:")
    for (a in done)
      lines <- c(lines, sprintf("- #%s (%s): %s", a$id,
                                substr(a$prompt, 1L, 50L),
                                substr(a$result, 1L, 1500L)))
  }
  if (length(running))
    lines <- c(lines, sprintf(
      "Background sub-agents still running (do not re-spawn these): %s",
      paste0("#", vapply(running, function(a) a$id, character(1)),
             collapse = ", ")))
  paste(lines, collapse = "\n")
}

# ---------------------------------------------------------------------------
# Async-turn tracking (Phase A). ellmer async (promise-returning) tools work
# ONLY under chat_async()/stream_async(); sync chat$chat() rejects them.
# codeagent_stream_async() marks the turn async (.enter_async_turn/.exit_async_turn)
# so the Agent tool knows it may return a promise for concurrent sub-agents.
# Sync turns (one-shot codeagent()/agent_loop) fall back to the sync loop.
# ---------------------------------------------------------------------------
.async_turn_state <- new.env(parent = emptyenv())
.async_turn_state$depth <- 0L
.enter_async_turn <- function() {
  .async_turn_state$depth <- .async_turn_state$depth + 1L
  invisible(NULL)
}
.exit_async_turn <- function() {
  .async_turn_state$depth <- max(0L, .async_turn_state$depth - 1L)
  invisible(NULL)
}
.in_async_turn <- function() isTRUE(.async_turn_state$depth > 0L)

# Async variant of .run_subagent_loop(): returns a promise resolving to the
# sub-agent's text response. Used only inside an async parent turn so multiple
# Agent calls interleave (ellmer tool_mode = "concurrent").
.run_subagent_loop_async <- function(sub_chat, prompt, max_turns = 30L,
                                      persist = FALSE, cwd = getwd(),
                                      description = NULL) {
  p <- promises::then(
    sub_chat$chat_async(prompt),
    onFulfilled = function(response) {
      if (isTRUE(persist)) {
        sid <- paste0("subagent-", substr(tryCatch(.generate_uuid_v4(),
                      error = function(e) "x"), 1L, 8L))
        tryCatch(save_session(sub_chat, cwd, sid,
                              title = description %||% "sub-agent"),
                 error = function(e) NULL)
      }
      if (is.character(response)) response
      else "[Sub-agent completed with no text output]"
    })
  promises::catch(p, function(e)
    paste0("[Error in sub-agent] ", conditionMessage(e)))
}
