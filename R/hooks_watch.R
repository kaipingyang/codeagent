#' @title Filesystem-watch hooks (FileChanged / ConfigChange)
#' @description Bridges the `watcher` package (libfswatch / inotify) to the
#'   `FileChanged` and `ConfigChange` hook events. The watcher runs in the
#'   background and dispatches callbacks through the `later` event loop, so it
#'   works wherever a `later` loop is being pumped: the Shiny app (its reactive
#'   loop) and the CLI REPL (which pumps `later` while streaming and, since the
#'   non-blocking keypress change, while idle at the prompt too).
#'
#'   `watcher`'s callback only reports the CHANGED PATHS, not whether each was a
#'   create/modify/delete -- so `FileChanged`'s `event` field is always
#'   `"change"` here (documented downgrade; CC distinguishes change/add/unlink).
#' @name hooks_watch
#' @keywords internal
NULL

# Config files whose changes map to ConfigChange (vs generic FileChanged).
# Path -> CC `source` enum value.
.config_source_for <- function(path) {
  p <- tryCatch(normalizePath(path, mustWork = FALSE), error = function(e) path)
  if (grepl("[/\\\\]\\.codeagent[/\\\\]settings\\.json$", p)) return("project_settings")
  if (grepl("[/\\\\]settings\\.json$", p) &&
      grepl(tryCatch(normalizePath("~/.codeagent", mustWork = FALSE),
                     error = function(e) "~/.codeagent"), p, fixed = TRUE))
    return("user_settings")
  if (grepl("settings\\.json$", p)) return("local_settings")
  NA_character_
}

#' Start filesystem-watch hooks for a session.
#'
#' @param hooks A [HookRegistry] or NULL. NULL / no watcher package -> no-op.
#' @param cwd Directory to watch recursively for `FileChanged`.
#' @param config_paths Character vector of settings-file paths to watch for
#'   `ConfigChange` (defaults to user + project settings.json).
#' @param latency Numeric seconds; watcher debounce (default 1).
#' @return A list with a `$stop()` method (idempotent) and the watcher objects,
#'   or NULL if nothing could be started. Store it and call `$stop()` on session
#'   teardown.
#' @keywords internal
.start_hook_watchers <- function(hooks, cwd = getwd(), config_paths = NULL,
                                 latency = 1) {
  if (is.null(hooks)) return(NULL)
  if (!requireNamespace("watcher", quietly = TRUE)) return(NULL)

  # Only start watchers for events that actually have a registered hook -- no
  # point running a background monitor nobody listens to.
  want_file   <- isTRUE(tryCatch(hooks$has_hooks(HookEvent$FILE_CHANGED),
                                 error = function(e) FALSE))
  want_config <- isTRUE(tryCatch(hooks$has_hooks(HookEvent$CONFIG_CHANGE),
                                 error = function(e) FALSE))
  if (!want_file && !want_config) return(NULL)

  if (is.null(config_paths)) {
    config_paths <- c(
      file.path(path.expand("~"), ".codeagent", "settings.json"),
      file.path(cwd, ".codeagent", "settings.json"))
  }
  config_norm <- vapply(config_paths, function(p)
    tryCatch(normalizePath(p, mustWork = FALSE), error = function(e) p),
    character(1))

  watchers <- list()

  # FileChanged: watch cwd recursively. Config files living under cwd would also
  # surface here; we route those to ConfigChange and suppress the generic event
  # so a settings.json edit does not double-fire.
  if (want_file) {
    fw <- tryCatch(watcher::watcher(cwd, latency = latency, callback = function(paths) {
      for (p in paths) {
        pn <- tryCatch(normalizePath(p, mustWork = FALSE), error = function(e) p)
        if (pn %in% config_norm) next  # handled by ConfigChange watcher
        tryCatch(hooks$run_file_changed(pn, "change", list()),
                 error = function(e) NULL)
      }
    }), error = function(e) NULL)
    if (!is.null(fw) && isTRUE(tryCatch(fw$start(), error = function(e) FALSE)))
      watchers$file <- fw
  }

  # ConfigChange: watch each settings.json path directly.
  if (want_config) {
    existing <- config_paths[file.exists(config_paths)]
    if (length(existing)) {
      cw <- tryCatch(watcher::watcher(existing, latency = latency,
                                      callback = function(paths) {
        for (p in paths) {
          pn  <- tryCatch(normalizePath(p, mustWork = FALSE), error = function(e) p)
          src <- .config_source_for(pn)
          if (is.na(src)) src <- "local_settings"
          tryCatch(hooks$run_config_change(src, pn, list()),
                   error = function(e) NULL)
        }
      }), error = function(e) NULL)
      if (!is.null(cw) && isTRUE(tryCatch(cw$start(), error = function(e) FALSE)))
        watchers$config <- cw
    }
  }

  if (!length(watchers)) return(NULL)

  stopped <- FALSE
  list(
    watchers = watchers,
    stop = function() {
      if (stopped) return(invisible(NULL))
      for (w in watchers) tryCatch(w$stop(), error = function(e) NULL)
      stopped <<- TRUE
      invisible(NULL)
    }
  )
}
