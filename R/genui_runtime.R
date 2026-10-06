# GenUI runtime helpers: everything between a validated model call and the
# DOM. Pure functions first (dataset lookup, canvas-output validation, quota,
# output discovery, trace fold, summary), then the executor, which touches the
# browser only through an injectable `ops` list so every path is testable
# without one. See references/plan/42-genui-phase1-3.md.

# -- limits -------------------------------------------------------------------

# Conservative starting values (research sec. 10). A quota hit is a fixed tool
# error; the adapter never frees room by removing other components.
.GENUI_LIMITS <- list(
  mutations_per_turn = 6L,
  live_instances     = 12L,
  trace_entries      = 200L,
  arg_bytes          = 8192L,
  string_chars       = 2048L,
  array_items        = 100L
)

# -- dataset ------------------------------------------------------------------

# The data frame a component reads. Looked up by name in `env` (and its
# parents, so attached datasets such as mtcars resolve); only data frames
# qualify. The error lists the data frames the model could use instead.
#' @keywords internal
.genui_resolve_dataset <- function(name, env = globalenv()) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name))
    stop("`dataset` must name a data frame in the R session, like \"mtcars\".",
         call. = FALSE)
  value <- get0(name, envir = env, inherits = TRUE, ifnotfound = NULL)
  if (is.null(value)) {
    frames <- Filter(function(nm) is.data.frame(
      get0(nm, envir = env, inherits = FALSE)), ls(env))
    hint <- if (length(frames))
      paste0(" Available data frames: ", paste(sort(frames), collapse = ", "), ".")
    else " There are no data frames in the R session yet."
    stop("No data frame named \"", name, "\".", hint, call. = FALSE)
  }
  if (!is.data.frame(value))
    stop("\"", name, "\" is not a data frame.", call. = FALSE)
  value
}

# -- canvas-output validation -------------------------------------------------

# Every model-authored string is checked before the DOM changes. Components
# render strings as text, so this is defence in depth: no markup, no links or
# URL schemes (a model-chosen URL is browser egress), no control characters.
.GENUI_BAD_TEXT <- c(
  markup  = "<\\s*[A-Za-z!/?]",
  scheme  = "(?i)\\b(javascript|vbscript|data|file|blob)\\s*:",
  url     = "(?i)\\b(https?|ftp|wss?)://|\\bwww\\.",
  control = "[\\x01-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]"
)

#' @keywords internal
.genui_validate_strings <- function(args) {
  strings <- .genui_strings(args)
  for (s in strings) {
    for (pattern in .GENUI_BAD_TEXT)
      if (grepl(pattern, s, perl = TRUE))
        return(paste0(
          "Canvas text cannot contain markup, links, URLs or control ",
          "characters. Use plain words for titles and labels."))
  }
  NULL
}

.genui_strings <- function(x) {
  if (is.character(x)) return(x[!is.na(x)])
  if (is.list(x)) return(unlist(lapply(x, .genui_strings), use.names = FALSE))
  character()
}

# -- quota --------------------------------------------------------------------

#' @keywords internal
.genui_quota_check <- function(action, args, live, turn_mutations, trace_len,
                               limits = .GENUI_LIMITS) {
  if (turn_mutations >= limits$mutations_per_turn)
    return(sprintf(paste0(
      "Canvas limit reached: at most %d changes per turn. Finish this answer ",
      "and continue in the next turn."), limits$mutations_per_turn))
  if (identical(action, "create") && live >= limits$live_instances)
    return(sprintf(paste0(
      "Canvas limit reached: at most %d components at once. Remove one ",
      "(canvas_remove) before adding another."), limits$live_instances))
  if (trace_len >= limits$trace_entries)
    return(sprintf(paste0(
      "Canvas history is full (%d changes). Start a new session to keep ",
      "building."), limits$trace_entries))
  bytes <- nchar(jsonlite::toJSON(args, auto_unbox = TRUE, null = "null"),
                 type = "bytes")
  if (bytes > limits$arg_bytes)
    return(sprintf("Canvas arguments are too large (%d bytes; limit %d).",
                   bytes, limits$arg_bytes))
  if (any(nchar(.genui_strings(args)) > limits$string_chars))
    return(sprintf("A canvas text value is longer than %d characters.",
                   limits$string_chars))
  if (.genui_max_length(args) > limits$array_items)
    return(sprintf("A canvas argument has more than %d items.",
                   limits$array_items))
  NULL
}

.genui_max_length <- function(x) {
  if (is.list(x))
    return(max(c(length(x), vapply(x, .genui_max_length, numeric(1L)))))
  length(x)
}

# -- output discovery ---------------------------------------------------------

# Output elements a component's UI declares. Removing a shell from the DOM
# leaves its render observers registered in the session; knowing the ids lets
# the executor destroy them with `output[[id]] <- NULL`.
.GENUI_OUTPUT_CLASS <-
  "(^|\\s)(shiny-[a-z-]*output|html-widget-output)(\\s|$)"

#' @keywords internal
.genui_output_ids <- function(ui) {
  out <- character()
  walk <- function(x) {
    if (inherits(x, "shiny.tag")) {
      attribs <- x$attribs
      cls <- paste(unlist(attribs[names(attribs) == "class"]), collapse = " ")
      id <- attribs$id
      if (is.character(id) && grepl(.GENUI_OUTPUT_CLASS, cls))
        out <<- c(out, id)
      walk(x$children)
    } else if (is.list(x)) {
      for (child in x) walk(child)
    }
  }
  walk(ui)
  unique(out)
}

# -- plan application and trace fold ------------------------------------------

# Apply one committed op to a canvas state (pure). The state is the shape
# shinygenui::genui_dispatch() expects plus codeagent's `dataset` field.
#' @keywords internal
.genui_apply_op <- function(state, op) {
  switch(op$action,
    create = {
      state$instances[[op$id]] <- list(component = op$component,
                                       args = op$args, parent_id = op$parent_id,
                                       dataset = op$dataset)
      state$next_id <- as.integer(sub("^c", "", op$id)) + 1L
    },
    update = state$instances[[op$id]]$args <- op$args,
    remove = , clear = state$instances[op$ids] <- NULL)
  state
}

.genui_empty_state <- function() list(instances = list(), next_id = 1L)

# Dispatch one trace op against `state`, re-running every shinygenui check.
.genui_redispatch <- function(catalog, op, state, resolve_data) {
  data <- if (!is.null(op$dataset)) resolve_data(op$dataset) else NULL
  call <- switch(op$action,
    create = shinygenui::genui_call(op$component, op$args %||% list()),
    update = shinygenui::genui_call("update_component",
                                    list(id = op$id, args = op$args %||% list())),
    remove = shinygenui::genui_call("remove_component", list(id = op$id)),
    clear  = shinygenui::genui_call("clear_canvas"),
    stop("Unknown canvas action \"", op$action, "\".", call. = FALSE))
  plan <- shinygenui::genui_dispatch(catalog, call, state, data = data)
  replayed <- .genui_plan_to_op(plan)
  if (!identical(replayed$id, op$id) && !is.null(op$id))
    stop("Canvas history is inconsistent at ", op$id, ".", call. = FALSE)
  replayed$dataset <- op$dataset
  replayed
}

# Replay a whole trace through dispatch (no DOM). Any op that no longer
# validates -- a dataset gone, a column renamed -- is an error: restore is
# strict and never produces a partial canvas.
#' @keywords internal
.genui_fold_trace <- function(catalog, trace, resolve_data) {
  state <- .genui_empty_state()
  for (op in trace) {
    replayed <- .genui_redispatch(catalog, op, state, resolve_data)
    state <- .genui_apply_op(state, replayed)
  }
  state
}

# -- summary ------------------------------------------------------------------

# One bounded line for the per-turn system reminder, so instance ids survive
# compaction of the turns that created them.
#' @keywords internal
.genui_state_summary <- function(state, max = 12L) {
  inst <- state$instances %||% list()
  if (!length(inst)) return("")
  ids <- names(inst)
  shown <- utils::head(ids, max)
  parts <- vapply(shown, function(id) sprintf(
    "%s %s (dataset %s)", id, inst[[id]]$component,
    inst[[id]]$dataset %||% "?"), character(1L))
  more <- length(ids) - length(shown)
  paste0("Canvas components now on screen: ", paste(parts, collapse = "; "),
         if (more > 0L) sprintf("; and %d more", more), ".")
}

# -- DOM naming ---------------------------------------------------------------

.GENUI_CANVAS_ID <- "ca_genui_canvas"
.genui_shell_id  <- function(id) paste0("ca_genui_shell_", id)
# Module scope of an instance's n-th mount. Every update mounts a fresh scope
# so the old one can be destroyed whole; the first keeps the plain name.
.genui_module_id <- function(id, n = 1L)
  if (n <= 1L) paste0("ca_genui_", id) else paste0("ca_genui_", id, "_", n)

# -- executor -----------------------------------------------------------------

# The Shiny side of the executor. Every call names the session explicitly and
# runs component servers inside its reactive domain: tool calls arrive from
# ellmer's promise chain, where the ambient domain is unreliable.
#' @keywords internal
.genui_shiny_ops <- function(session) {
  force(session)
  list(
    insert = function(selector, ui, where = "beforeEnd")
      shiny::insertUI(selector = selector, where = where, ui = ui,
                      immediate = TRUE, session = session),
    remove = function(selector, multiple = FALSE)
      shiny::removeUI(selector = selector, multiple = multiple,
                      immediate = TRUE, session = session),
    null_output = function(output_id)
      shiny::withReactiveDomain(session, session$output[[output_id]] <- NULL),
    # Shiny's module destroy (session$destroy(namespace)) tears down every
    # observer, output and input of a module scope -- including observers a
    # component server created but never returned. FALSE where the installed
    # Shiny predates it; the caller then falls back to nulling known outputs.
    destroy_scope = function(module_id) {
      destroy <- tryCatch(session$destroy, error = function(e) NULL)
      if (!is.function(destroy)) return(FALSE)
      shiny::withReactiveDomain(session, destroy(module_id))
      TRUE
    },
    run_server = function(component, module_id, args, data) {
      if (is.null(component$server)) return(NULL)
      shiny::withReactiveDomain(session,
                                component$server(module_id, args, data))
    },
    input_values = function(module_id) {
      input <- session$input
      all <- shiny::isolate(names(input)) %||% character()
      prefix <- paste0(module_id, "-")
      keys <- all[startsWith(all, prefix)]
      if (!length(keys)) return(NULL)
      vals <- lapply(keys, function(k) shiny::isolate(input[[k]]))
      stats::setNames(vals, substring(keys, nchar(prefix) + 1L))
    }
  )
}

.genui_destroy_handles <- function(handles) {
  for (h in .genui_collect_observers(handles))
    tryCatch(h$destroy(), error = function(e) NULL)
  invisible(NULL)
}

.genui_collect_observers <- function(x) {
  if (is.null(x)) return(list())
  if (inherits(x, "Observer") ||
      (is.list(x) && !is.object(x) && is.function(x$destroy)) ||
      (is.environment(x) && is.function(get0("destroy", x, inherits = FALSE))))
    return(list(x))
  if (is.list(x) && !is.object(x))
    return(unlist(lapply(x, .genui_collect_observers), recursive = FALSE))
  list()
}

# Release everything one mount owns on the server: returned handles, then the
# module scope (or, without scope destroy, the outputs its UI declared).
.genui_release <- function(runtime, ops) {
  if (is.null(runtime)) return(invisible(NULL))
  .genui_destroy_handles(runtime$handles)
  done <- tryCatch(isTRUE(ops$destroy_scope(runtime$module_id)),
                   error = function(e) FALSE)
  if (!done)
    for (o in runtime$outputs %||% character())
      tryCatch(ops$null_output(o), error = function(e) NULL)
  invisible(NULL)
}

.genui_shell <- function(component, id, ui) {
  htmltools::div(
    id = .genui_shell_id(id),
    class = paste0("genui-shell genui-width-", component$width %||% "auto"),
    `data-genui-component` = component$name,
    ui)
}

# Start a component's server in `module_id`; on failure release the attempt
# (its scope, so observers it made before failing go too) and rethrow.
.genui_start <- function(component, module_id, args, data, outputs, ops) {
  tryCatch(
    ops$run_server(component, module_id, args, data),
    error = function(e) {
      .genui_release(list(module_id = module_id, outputs = outputs), ops)
      stop(e)
    })
}

# Mount one instance. Building the UI comes first so a failing ui() leaves the
# DOM untouched; a failing server removes the shell and its scope again.
#' @keywords internal
.genui_mount <- function(component, id, args, data, ops,
                         module_id = .genui_module_id(id)) {
  ui <- component$ui(module_id, args)
  outputs <- .genui_output_ids(ui)
  ops$insert(paste0("#", .GENUI_CANVAS_ID), .genui_shell(component, id, ui))
  handles <- tryCatch(
    .genui_start(component, module_id, args, data, outputs, ops),
    error = function(e) {
      tryCatch(ops$remove(paste0("#", .genui_shell_id(id))),
               error = function(e2) NULL)
      stop(e)
    })
  list(module_id = module_id, outputs = outputs, handles = handles)
}

#' @keywords internal
.genui_unmount <- function(id, runtime, ops) {
  .genui_release(runtime, ops)
  tryCatch(ops$remove(paste0("#", .genui_shell_id(id))), error = function(e) NULL)
  invisible(NULL)
}

# Replace an instance's content in place under a fresh module scope. On
# success the old scope is destroyed. A failing new server is released and
# the old arguments are mounted again under `rollback_module_id`, so the
# canvas, registry and trace all keep the previous arguments; the error then
# propagates with the restored runtime attached.
#' @keywords internal
.genui_remount <- function(component, id, old_args, new_args, runtime, data, ops,
                           module_id, rollback_module_id) {
  new_ui <- component$ui(module_id, new_args)
  shell <- paste0("#", .genui_shell_id(id))
  swap <- function(ui) {
    tryCatch(ops$remove(paste0(shell, " > *"), multiple = TRUE),
             error = function(e) NULL)
    ops$insert(shell, ui)
  }
  new_outputs <- .genui_output_ids(new_ui)
  swap(new_ui)
  handles <- tryCatch(
    .genui_start(component, module_id, new_args, data, new_outputs, ops),
    error = function(e) e)
  .genui_release(runtime, ops)
  if (!inherits(handles, "error"))
    return(list(module_id = module_id, outputs = new_outputs, handles = handles))
  old_ui <- component$ui(rollback_module_id, old_args)
  old_outputs <- .genui_output_ids(old_ui)
  swap(old_ui)
  old_handles <- tryCatch(
    .genui_start(component, rollback_module_id, old_args, data, old_outputs, ops),
    error = function(e) NULL)
  attr(handles, "restored") <- list(module_id = rollback_module_id,
                                    outputs = old_outputs, handles = old_handles)
  stop(handles)
}
