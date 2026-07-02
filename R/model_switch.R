#' @title Model Switching (harness, no Shiny dependency)
#' @description Lossless mid-conversation model switching. Pure-R harness
#'   functions usable from both the CLI and the Shiny app. Conversation history
#'   (including tool requests/results) is preserved across the switch.
#'
#'   Two strategies:
#'   * **Route A (default)** -- swap the ellmer Chat's internal provider in place.
#'     The Chat object identity is unchanged, so callbacks (`on_tool_result`),
#'     the stream controller, and any closures capturing the Chat keep working
#'     untouched. Touches ellmer's private R6 field, guarded by tryCatch.
#'   * **Route B (fallback)** -- build a fresh Chat from the new spec, migrate
#'     turns via `set_turns()`, and rebuild the client through
#'     [codeagent_client()] (re-registers tools + system prompt). Pure public
#'     API; returns a NEW client object.
#'
#'   See `references/model-switch-alternatives.md` for the 13-point empirical
#'   validation behind this design.
#' @name model_switch
#' @keywords internal
NULL

#' Resolve a model spec/alias into a fresh ellmer Chat
#'
#' Thin wrapper over [.parse_client_spec()] so model switching reuses the same
#' alias + provider-prefix resolution as `codeagent_client_config()`.
#'
#' @param model Character. `"anthropic/..."`, `"openai/..."`, `"ollama/..."`,
#'   a plain model name, or an alias defined in `codeagent.md`.
#' @param cwd Character. Working directory (for alias lookup).
#' @return A fresh `ellmer::Chat`.
#' @keywords internal
.resolve_model_chat <- function(model, cwd = getwd()) {
  aliases <- tryCatch(.read_codeagent_config(cwd), error = function(e) list())
  .parse_client_spec(model, aliases = aliases, cwd = cwd)
}

#' Swap a Chat's provider in place (Route A)
#'
#' When the new model uses the same provider class (e.g. both OpenAI-compatible),
#' uses the public `set_model()` API added in ellmer 0.4.2. For cross-provider
#' switches (e.g. OpenAI-compat -> Anthropic) falls back to replacing the private
#' R6 `private$provider` field -- still necessary until ellmer adds
#' `set_provider()` (see https://github.com/tidyverse/ellmer/issues/1042).
#' Returns TRUE on success, FALSE if inaccessible.
#'
#' @param chat An `ellmer::Chat` to mutate.
#' @param new_chat An `ellmer::Chat` whose provider to adopt.
#' @return Logical. TRUE if swapped in place.
#' @keywords internal
.swap_provider <- function(chat, new_chat) {
  tryCatch({
    cur_class <- class(chat$get_provider())[1L]
    new_class <- class(new_chat$get_provider())[1L]

    # Same provider class: use the public set_model() API (ellmer >= 0.4.2).
    # This avoids touching private internals for the common same-vendor case.
    if (identical(cur_class, new_class) &&
        is.function(tryCatch(chat$set_model, error = function(e) NULL))) {
      new_model <- tryCatch(new_chat$get_model(), error = function(e) NULL)
      if (!is.null(new_model)) {
        chat$set_model(new_model)
        return(TRUE)
      }
    }

    # Cross-provider: replace the private$provider field in place.
    # Necessary until ellmer gains a public set_provider() method.
    priv <- chat$.__enclos_env__$private
    if (is.null(priv) || is.null(priv$provider))
      return(FALSE)
    priv$provider <- new_chat$get_provider()
    TRUE
  }, error = function(e) FALSE)
}

#' Switch the active model on a CodagentClient, preserving history
#'
#' Tries Route A (in-place provider swap); falls back to Route B (rebuild +
#' migrate turns) if the in-place swap fails. The returned client always has the
#' full conversation history and re-registered tools.
#'
#' @param client A `CodagentClient` from [codeagent_client()].
#' @param model Character. New model spec/alias (see [.resolve_model_chat()]).
#' @return A `CodagentClient` with the new model and preserved history. With
#'   Route A this is the SAME client object (Chat identity unchanged); with
#'   Route B it is a NEW client object.
#' @export
switch_model <- function(client, model) {
  if (!inherits(client, "CodagentClient"))
    cli::cli_abort("{.fn switch_model} expects a {.cls CodagentClient}, not {.cls {class(client)[1]}}.")
  if (!is.character(model) || length(model) != 1L || !nzchar(model))
    cli::cli_abort("{.arg model} must be a non-empty character spec or alias.")

  cwd      <- client$settings$cwd %||% getwd()
  new_chat <- .resolve_model_chat(model, cwd)
  new_model <- tryCatch(new_chat$get_model(), error = function(e) model)

  # Route A: in-place provider swap (Chat identity preserved).
  if (.swap_provider(client$chat, new_chat)) {
    client$settings$model <- new_model
    return(client)
  }

  # Route B: rebuild client, migrate history via public API.
  turns <- tryCatch(client$chat$get_turns(), error = function(e) list())
  tryCatch(new_chat$set_turns(turns), error = function(e) NULL)

  s <- client$settings
  codeagent_client(
    new_chat,
    permission_mode    = s$permission_mode %||% "default",
    rules              = s$rules %||% list(),
    cwd                = cwd,
    max_turns          = s$max_turns %||% 100L,
    btw_groups         = s$btw_groups,
    worktree_isolation = isTRUE(s$worktree_isolation),
    verify_fn          = s$verify_fn
  )
}
