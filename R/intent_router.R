# ---------------------------------------------------------------------------
# Intent routing (PROTOTYPE, branch proto/intent-routing -- not for main)
# ---------------------------------------------------------------------------
# The host decides, before the model's first request of a turn, whether the
# user's message must go to a given tool. `codeagent_server(intent_router =)`
# takes function(text, last_reply) returning NULL or
#   list(tool = "<tool name>", mode = "force" | "hint", hint = "<text>")
# force: the turn's FIRST request carries tool_choice = that tool; the choice
#        is cleared when the model asks for a tool (or the turn ends), so later
#        requests of the same turn are free (a forced choice on every request
#        stalls the endpoint -- verified 2026-11-25).
# hint:  the hint rides with the turn's system-reminder.
# ellmer 0.5 has no per-request tool_choice: .set_tool_choice() edits the
# chat's private model (TEMPORARY workaround; see the intent-routing spec).

.set_tool_choice <- function(chat, tool = NULL) {
  p <- chat$.__enclos_env__$private
  m <- p$model
  m@extra_args$tool_choice <- if (is.null(tool)) NULL else
    list(type = "function", `function` = list(name = tool))
  p$model <- m
  p$provider <- utils::getFromNamespace("provider_model<-", "ellmer")(p$provider, m)
  invisible(TRUE)
}

.last_reply_text <- function(chat, n = 240L) {
  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  for (t in rev(turns)) if (identical(t@role, "assistant")) {
    txt <- paste(vapply(Filter(function(c) inherits(c, "ellmer::ContentText"), t@contents),
                        function(c) c@text, ""), collapse = " ")
    if (nzchar(trimws(txt))) return(substr(gsub("\\s+", " ", txt), 1L, n))
  }
  ""
}

# Called once per turn, before the turn's setup. Returns list(hint, force):
# the hint text to add to the turn's context and the tool to force on the
# first request (set by the caller AFTER the turn setup, so a compaction
# request made there is never forced).
.route_intent <- function(router, chat, text, tool_names) {
  none <- list(hint = NULL, force = NULL)
  if (!is.function(router) || !nzchar(trimws(text %||% ""))) return(none)
  d <- tryCatch(router(text, .last_reply_text(chat)), error = function(e) NULL)
  if (!is.list(d) || is.null(d$tool) || !d$tool %in% tool_names) return(none)
  if (identical(d$mode, "force")) return(list(hint = d$hint, force = d$tool))
  list(hint = d$hint %||% sprintf("The user's request matches the %s tool: call it first.", d$tool), force = NULL)
}

.force_first_tool <- function(chat, state, tool) {
  if (is.null(tool)) return(invisible(FALSE))
  ok <- tryCatch(.set_tool_choice(chat, tool), error = function(e) FALSE)
  if (isTRUE(ok)) state$forced <- tool
  invisible(isTRUE(ok))
}

.clear_forced_tool <- function(chat, state) {
  if (!is.null(state$forced)) {
    tryCatch(.set_tool_choice(chat, NULL), error = function(e) NULL)
    state$forced <- NULL
  }
}
