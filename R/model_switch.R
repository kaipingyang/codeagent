#' @title Model Switching (harness, no Shiny dependency)
#' @description Lossless mid-conversation model switching. Pure-R harness
#'   functions usable from both the CLI and the Shiny app. Conversation history
#'   (including tool requests/results) is preserved across the switch.
#'
#'   Two strategies:
#'   * **Route A (strict name-only)** -- use public `set_model()` only when the
#'     provider configuration and Model params/extra args are unchanged. Chat
#'     identity, callbacks, and tools remain intact.
#'   * **Route B (fallback)** -- for provider/configuration changes, build a
#'     fresh Chat, migrate turns, and rebuild tools while carrying forward the
#'     complete live client settings, hooks, and Data Shield engine. Returns a
#'     NEW client object; the original remains unchanged if rebuilding fails.
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

# Compare credential closures without invoking them. In addition to body/formals,
# compare any lexically captured variables used by the function (e.g. a captured
# API key). This avoids both secret disclosure and false equality for closures
# with identical source but different captured configuration.
.function_configuration_equal <- function(x, y) {
  if (!is.function(x) || !is.function(y)) return(identical(x, y))
  if (!identical(formals(x), formals(y)) || !identical(body(x), body(y)))
    return(FALSE)
  gx <- tryCatch(codetools::findGlobals(x, merge = FALSE)$variables,
                 error = function(e) character())
  gy <- tryCatch(codetools::findGlobals(y, merge = FALSE)$variables,
                 error = function(e) character())
  if (!identical(sort(gx), sort(gy))) return(FALSE)
  for (nm in gx) {
    ex <- exists(nm, envir = environment(x), inherits = TRUE)
    ey <- exists(nm, envir = environment(y), inherits = TRUE)
    if (!identical(ex, ey)) return(FALSE)
    if (ex && !identical(get(nm, envir = environment(x), inherits = TRUE),
                         get(nm, envir = environment(y), inherits = TRUE)))
      return(FALSE)
  }
  TRUE
}

.provider_configuration_equal <- function(x, y) {
  if (!identical(class(x), class(y))) return(FALSE)
  px <- tryCatch(S7::props(x), error = function(e) NULL)
  py <- tryCatch(S7::props(y), error = function(e) NULL)
  if (is.null(px) || is.null(py) || !identical(names(px), names(py)))
    return(FALSE)
  all(vapply(names(px), function(nm) {
    if (is.function(px[[nm]]) || is.function(py[[nm]]))
      .function_configuration_equal(px[[nm]], py[[nm]])
    else
      identical(px[[nm]], py[[nm]])
  }, logical(1L)))
}

.model_configuration_equal <- function(x, y, include_name = FALSE) {
  px <- tryCatch(S7::props(x), error = function(e) NULL)
  py <- tryCatch(S7::props(y), error = function(e) NULL)
  if (is.null(px) || is.null(py)) return(FALSE)
  if (!isTRUE(include_name)) {
    px$name <- NULL
    py$name <- NULL
  }
  identical(px, py)
}

#' Swap only a Chat's model name in place (strict Route A)
#'
#' Route A is allowed only when provider configuration is unchanged and the
#' target Model differs solely by name. Cross-provider, endpoint, credentials,
#' params, and extra-argument changes return `FALSE` without mutation.
#'
#' @param chat An `ellmer::Chat` to mutate.
#' @param new_chat An `ellmer::Chat` describing the requested target.
#' @return Logical. `TRUE` only after the post-switch state is verified.
#' @keywords internal
.swap_provider <- function(chat, new_chat) {
  tryCatch({
    old_provider <- chat$get_provider()
    new_provider <- new_chat$get_provider()
    old_model <- chat$get_model_object()
    new_model <- new_chat$get_model_object()
    old_name <- old_model@name

    if (!.provider_configuration_equal(old_provider, new_provider) ||
        !.model_configuration_equal(old_model, new_model, include_name = FALSE) ||
        !is.function(tryCatch(chat$set_model, error = function(e) NULL)))
      return(FALSE)

    chat$set_model(new_model@name)
    after_provider <- chat$get_provider()
    after_model <- chat$get_model_object()
    ok <- .provider_configuration_equal(old_provider, after_provider) &&
      identical(after_model@name, new_model@name) &&
      .model_configuration_equal(old_model, after_model, include_name = FALSE)
    if (!isTRUE(ok)) {
      tryCatch(chat$set_model(old_name), error = function(e) NULL)
      return(FALSE)
    }
    TRUE
  }, error = function(e) FALSE)
}

# Rebuild around a fresh Chat without reloading settings or re-merging rules.
# Every live runtime setting object (hooks, scanner callbacks, sandbox/tool
# settings, etc.) is carried forward; only the resolved model is changed.
.rebuild_client_for_model <- function(client, new_chat) {
  turns <- client$chat$get_turns()
  new_chat$set_turns(turns)
  old_prompt <- tryCatch(client$chat$get_system_prompt(), error = function(e) NULL)
  if (!is.null(old_prompt)) new_chat$set_system_prompt(old_prompt)

  settings <- client$settings
  settings$model <- new_chat$get_model_object()@name
  shield <- client$data_shield
  ask_fn <- if (interactive()) .console_ask_fn else NULL

  .register_all_tools(new_chat, settings, ask_fn = ask_fn)
  tryCatch(.mcp_autoconnect(new_chat, settings), error = function(e) NULL)
  if (inherits(shield, "DataShield")) {
    .bind_data_shield_reviewer_factory(shield, new_chat, settings,
                                       settings$cwd %||% getwd())
    shield$install(new_chat)
  }

  out <- .new_client(new_chat, settings, data_shield = shield)
  if (!identical(out$chat$get_model_object()@name, settings$model) ||
      length(out$chat$get_turns()) != length(turns))
    stop("rebuilt client failed model/history verification", call. = FALSE)
  out
}

# Shared decision for every Shiny model-switch entry point. Shiny modules capture
# Chat identity, so targets requiring Route B are explicitly rejected.
.shiny_switch_model <- function(chat, settings, model, cwd = getwd(),
                                running = FALSE) {
  if (isTRUE(running))
    return(list(ok = FALSE, type = "warning",
                message = "Streaming in progress -- cannot switch model now."))
  new_chat <- tryCatch(.resolve_model_chat(model, cwd), error = identity)
  if (inherits(new_chat, "error"))
    return(list(ok = FALSE, type = "error",
                message = paste0("Model switch failed: ", conditionMessage(new_chat))))
  if (!.swap_provider(chat, new_chat))
    return(list(ok = FALSE, type = "warning",
                message = paste0("This model requires a new provider/configuration. ",
                                 "Start a new session or app to switch to ", model, ".")))
  resolved <- chat$get_model_object()@name
  list(ok = TRUE, type = "success", model = resolved,
       message = sprintf("Switched to %s -- history preserved.", resolved))
}

#' Switch the active model on a CodeagentClient, preserving history
#'
#' Tries Route A (in-place provider swap); falls back to Route B (rebuild +
#' migrate turns) if the in-place swap fails. The returned client always has the
#' full conversation history and re-registered tools.
#'
#' @param client A `CodeagentClient` from [codeagent_client()].
#' @param model Character. New model spec/alias (see [.resolve_model_chat()]).
#' @return A `CodeagentClient` with the new model and preserved history. With
#'   Route A this is the SAME client object (Chat identity unchanged); with
#'   Route B it is a NEW client object.
#' @export
switch_model <- function(client, model) {
  if (!inherits(client, "CodeagentClient"))
    cli::cli_abort("{.fn switch_model} expects a {.cls CodeagentClient}, not {.cls {class(client)[1]}}.")
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

  # Route B: build a new client without mutating the old client. Settings are
  # migrated as-is (no reload/re-merge), including live hooks and DataShield.
  .rebuild_client_for_model(client, new_chat)
}
