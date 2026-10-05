#' @title Generative UI adapter
#' @description codeagent-owned adapter over the exported pure functions of
#'   shinygenui. shinygenui decides whether a model call is valid and what plan
#'   it becomes; codeagent turns that plan into DOM and is answerable for it.
#'   `genui_server()` is never called: it would replace the system prompt,
#'   register tools behind the central permission gate, and take stream
#'   ownership. See `references/plan/41-genui-adapter.md`.
#' @name genui
#' @keywords internal
NULL

# Components codeagent has reviewed. Everything else in the starter pack is a
# candidate upstream may add to; it is left out, not rejected. markdown_card is
# deliberately absent: it keeps external img src and javascript: URLs.
.GENUI_ADMITTED <- c("value_box", "data_table", "scatter_plot", "histogram")

# Build the frozen catalog from a candidate component list. An admitted
# component that is missing is an error -- the prompt would otherwise promise a
# component the catalog cannot build.
#' @keywords internal
.genui_admit_catalog <- function(components) {
  names_ <- vapply(components, function(x) as.character(x$name), character(1L))
  missing <- setdiff(.GENUI_ADMITTED, names_)
  if (length(missing))
    stop("[codeagent] shinygenui no longer provides admitted component(s): ",
         paste0("\"", missing, "\"", collapse = ", "),
         ". The installed shinygenui does not match the reviewed contract.",
         call. = FALSE)
  do.call(shinygenui::genui_catalog, components[names_ %in% .GENUI_ADMITTED])
}

# Stable fingerprint of a catalog's tool surface: component names plus each
# argument's name, type and constraints, sorted so order does not matter. Only
# plain data goes in -- the Type objects are S7 and the component ui/server are
# closures, neither of which hashes stably across processes.
#' @keywords internal
.genui_catalog_digest <- function(catalog) {
  describe_arg <- function(type) list(
    type     = class(type)[[1L]],
    values   = tryCatch(type@values, error = function(e) NULL),
    required = tryCatch(type@required, error = function(e) NULL))
  comps <- lapply(sort(names(catalog)), function(nm) {
    comp <- catalog[[nm]]
    arg_names <- sort(names(comp$args))
    list(name = nm, container = isTRUE(comp$container),
         args = stats::setNames(lapply(arg_names, function(a)
           describe_arg(comp$args[[a]])), arg_names))
  })
  rlang::hash(comps)
}

# Tool name prefix. Tool names are listed statically (.genui_tool_names()) and
# registered by exact name; the prefix is never used to grant a capability, or
# any host tool named canvas_* would inherit "read".
.GENUI_PREFIX <- "canvas_"

# Lifecycle tools and the shinygenui call each one dispatches to. canvas_state
# maps to NA: shinygenui has no dispatchable state read, so the adapter answers
# it from its own state.
.GENUI_LIFECYCLE <- c(canvas_update = "update_component",
                      canvas_remove = "remove_component",
                      canvas_clear  = "clear_canvas",
                      canvas_state  = NA_character_)

#' @keywords internal
.genui_tool_name <- function(component) paste0(.GENUI_PREFIX, component)

# The shinygenui call name for a tool, or NULL for canvas_state.
#' @keywords internal
.genui_dispatch_name <- function(tool_name) {
  if (!startsWith(tool_name, .GENUI_PREFIX))
    stop("[codeagent] \"", tool_name, "\" is not a GenUI tool; GenUI tool names ",
         "start with \"", .GENUI_PREFIX, "\".", call. = FALSE)
  if (tool_name %in% names(.GENUI_LIFECYCLE)) {
    target <- .GENUI_LIFECYCLE[[tool_name]]
    return(if (is.na(target)) NULL else target)
  }
  substring(tool_name, nchar(.GENUI_PREFIX) + 1L)
}

#' @keywords internal
.genui_tool_names <- function() {
  c(.genui_tool_name(.GENUI_ADMITTED), names(.GENUI_LIFECYCLE))
}

# Fields every op carries, whatever its action. shinygenui plans differ by
# action (create has `component`, remove/clear have `ids`); a fixed shape means
# the executor never branches on which upstream fields happen to exist.
.GENUI_OP_FIELDS <- c("action", "id", "component", "args", "parent_id", "ids")

# Convert a shinygenui plan into a codeagent-owned op. This is the only place
# the upstream plan object is read; everything downstream depends on the plain
# list returned here.
#' @keywords internal
.genui_plan_to_op <- function(plan) {
  if (!inherits(plan, "genui_plan"))
    stop("[codeagent] Expected a shinygenui plan, got <",
         paste(class(plan), collapse = "/"), ">.", call. = FALSE)
  raw <- unclass(plan)
  stats::setNames(lapply(.GENUI_OP_FIELDS, function(f) raw[[f]]), .GENUI_OP_FIELDS)
}

# The cross-UI artifact for one GenUI operation. Its payload is deliberately
# closed: it is persisted with the session and rendered by non-Shiny hosts, so
# it carries identifiers and a caller-supplied safe summary only -- never the
# op's args (model-authored strings, data references), HTML, or observers.
# `kind = "generative_ui"` is not in tool_display's rich set, so chat shows a
# compact card rather than a copy of the canvas DOM.
#' @keywords internal
.genui_artifact <- function(op, catalog_digest, safe_summary) {
  if (!is.character(safe_summary) || length(safe_summary) != 1L)
    stop("`safe_summary` must be a character(1).", call. = FALSE)
  .new_tool_artifact(
    kind = "generative_ui",
    icon = "bar-chart",
    title = safe_summary,
    payload = list(
      catalog_digest = catalog_digest,
      operation      = op$action,
      instance_ids   = as.character(c(op$id, op$ids)),
      safe_summary   = safe_summary))
}

# The canvas section codeagent appends to its own system prompt. Rendered from
# codeagent's template (inst/genui/system.md), never shinygenui's default: that
# one opens by redefining the agent's identity, caps every reply at a sentence
# or two, and names lifecycle calls (update_component, ...) that are dispatch
# names rather than tools a model can call.
#
# The template has no container/parent_id section: no admitted component is a
# container. Add one together with the first admitted container component.
#' @keywords internal
.genui_prompt_fragment <- function(catalog) {
  template <- system.file("genui", "system.md", package = "codeagent",
                          mustWork = TRUE)
  shinygenui::genui_prompt(catalog, template = template)
}

# What building the catalog needs: shinygenui itself, plus the packages its
# starter pack checks for at call time (genui_components_bslib() runs
# rlang::check_installed(c("ggplot2", "DT"))). Those two are only Suggests of
# shinygenui, so having shinygenui installed is not enough.
.GENUI_STARTER_DEPS <- c("ggplot2", "DT")


# Checked by install location, not by loading: the app asks this on the path
# to first paint, and loading ggplot2 + DT there costs seconds.
#' @noRd
.genui_missing <- function(pkgs = c("shinygenui", .GENUI_STARTER_DEPS)) {
  pkgs[!nzchar(vapply(pkgs, function(p) system.file(package = p), ""))]
}

#' @noRd
.genui_available <- function() !length(.genui_missing())

#' @noRd
.genui_build_catalog <- function() {
  # Unbound (data = NULL): column names stay out of the tool schema and the
  # catalog survives the conversation moving between data sets.
  .genui_admit_catalog(shinygenui::genui_components_bslib(data = NULL))
}

# The id of the tool request being executed, when ellmer provides one. Each
# committed op keeps it: the request id is what binds a canvas change to the
# conversation turn that made it (rewind, cancel and restore all use it).
.genui_request_id <- function() {
  tryCatch({
    id <- ellmer::tool_context()$request@id
    if (is.character(id) && length(id) == 1L && nzchar(id)) id else NA_character_
  }, error = function(e) NA_character_)
}

.genui_message <- function(e) {
  msg <- tryCatch(cli::ansi_strip(conditionMessage(e)),
                  error = function(e2) conditionMessage(e))
  trimws(gsub("\\s*\n\\s*", " ", msg))
}

.genui_error_result <- function(message) {
  ellmer::ContentToolResult(error = message)
}

# Update deltas arrive as a JSON object string (as in shinygenui's own
# update tool). Parsed here only so the strings inside can be validated before
# dispatch; dispatch parses the same string again itself.
.genui_update_delta <- function(x) {
  if (is.null(x)) return(list())
  if (is.list(x)) return(x)
  tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE),
           error = function(e) list(x))
}

.genui_action <- function(dispatch_name) {
  switch(dispatch_name,
         update_component = "update", remove_component = "remove",
         clear_canvas = "clear", "create")
}

.genui_success_result <- function(op, digest) {
  json <- function(x) as.character(
    jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
  value <- switch(op$action,
    create = sprintf(paste0(
      "Created canvas component \"%s\" (%s, dataset %s). Refer to it by id ",
      "\"%s\" in canvas_update or canvas_remove."),
      op$id, op$component, op$dataset %||% "?", op$id),
    update = sprintf("Updated canvas component \"%s\" (%s) in place. Current arguments: %s",
                     op$id, op$component, json(op$args)),
    remove = if (length(op$ids) > 1L)
      sprintf("Removed canvas component \"%s\" and %d component(s) inside it.",
              op$id, length(op$ids) - 1L)
      else sprintf("Removed canvas component \"%s\".", op$id),
    clear = if (length(op$ids))
      sprintf("Cleared the canvas; removed %d component(s).", length(op$ids))
      else "The canvas was already empty.")
  title <- switch(op$action,
    create = paste("Canvas: added", op$component),
    update = paste("Canvas: updated", op$id),
    remove = paste("Canvas: removed", op$id),
    clear  = "Canvas: cleared")
  artifact <- .genui_artifact(op, digest, title)
  display <- .new_tool_result_display(
    title = .safe_tool_display_title(title), icon = .icon_tag("bar-chart"),
    text = value, show_request = FALSE, open = FALSE, label = title,
    value_preview = .tool_display_preview(value, 160L))
  ellmer::ContentToolResult(
    value = value,
    extra = list(display = display, codeagent = list(artifact = artifact)))
}

# Build an ellmer tool function whose formals are exactly `arg_names`, so the
# ToolDef's declared arguments and the function signature agree.
.genui_tool_fn <- function(arg_names, handler) {
  env <- new.env(parent = asNamespace("codeagent"))
  env$.genui_handler <- handler
  rlang::new_function(
    rlang::pairlist2(!!!rlang::rep_named(arg_names, list(NULL))),
    quote({
      nms <- names(formals(sys.function())) %||% character()
      args <- mget(nms, envir = environment())
      .genui_handler(args[!vapply(args, is.null, logical(1L))])
    }),
    env)
}

.genui_build_tools <- function(adapter) {
  catalog <- adapter$catalog()
  dataset_type <- ellmer::type_string(paste(
    "Name of the data frame in the R session to read, such as \"mtcars\".",
    "Create or load it first with your other tools if it does not exist yet."))
  component_tools <- lapply(.GENUI_ADMITTED, function(nm) {
    comp <- catalog[[nm]]
    if ("dataset" %in% names(comp$args))
      stop("[codeagent] Canvas component \"", nm, "\" already declares a ",
           "`dataset` argument.", call. = FALSE)
    tool_name <- .genui_tool_name(nm)
    arguments <- c(list(dataset = dataset_type), comp$args)
    ellmer::tool(
      .genui_tool_fn(names(arguments), function(args) adapter$call(tool_name, args)),
      name = tool_name, description = comp$description, arguments = arguments,
      annotations = ellmer::tool_annotations(title = paste("Canvas:", nm)))
  })
  id_type <- ellmer::type_string(
    "The component id, as returned when it was created (for example \"c1\").")
  lifecycle <- list(
    ellmer::tool(
      .genui_tool_fn(c("id", "args"), function(args) adapter$call("canvas_update", args)),
      name = "canvas_update",
      description = paste(
        "Update a canvas component in place, keeping its position.",
        "Use this instead of creating a new component when the user refines a",
        "view that already exists. Pass only the arguments that change."),
      arguments = list(
        id = id_type,
        args = ellmer::type_string(paste(
          "A JSON object string mapping argument names to their new values,",
          "for example {\"column\": \"hp\"}. Set an optional argument to null",
          "to reset it."))),
      annotations = ellmer::tool_annotations(title = "Canvas: update")),
    ellmer::tool(
      .genui_tool_fn("id", function(args) adapter$call("canvas_remove", args)),
      name = "canvas_remove",
      description = "Remove a component from the canvas.",
      arguments = list(id = id_type),
      annotations = ellmer::tool_annotations(title = "Canvas: remove")),
    ellmer::tool(
      .genui_tool_fn(character(), function(args) adapter$call("canvas_clear", args)),
      name = "canvas_clear",
      description = paste("Remove every component from the canvas. Use only when",
                          "the user asks to start over."),
      arguments = list(),
      annotations = ellmer::tool_annotations(title = "Canvas: clear")),
    ellmer::tool(
      .genui_tool_fn(character(), function(args) adapter$call("canvas_state", args)),
      name = "canvas_state",
      description = paste(
        "Read the canvas: every component with its id, dataset, arguments and",
        "the current values of its embedded inputs (which the user may have",
        "changed). It changes nothing."),
      arguments = list(),
      annotations = ellmer::tool_annotations(title = "Canvas: read state",
                                             read_only_hint = TRUE)))
  c(component_tools, lifecycle)
}

.GENUI_STATE_SCHEMA <- "codeagent.genui-state"
.GENUI_STATE_VERSION <- 1L

# A trace op as read back from session JSON: vectors arrive as lists.
.genui_normalize_op <- function(op) {
  scalar <- function(x) if (is.null(x)) NULL else as.character(unlist(x))[[1L]]
  list(
    action     = scalar(op$action),
    id         = scalar(op$id),
    component  = scalar(op$component),
    args       = op$args,
    parent_id  = scalar(op$parent_id),
    ids        = if (is.null(op$ids)) NULL else as.character(unlist(op$ids)),
    dataset    = scalar(op$dataset),
    request_id = scalar(op$request_id) %||% NA_character_,
    present    = isTRUE(unlist(op$present)))
}

# Facade over the GenUI subsystem, shaped like DataShield: the R6 object holds
# state and lifecycle, the .genui_* functions hold the testable logic. One
# adapter belongs to one browser session; the app builds it per session.
# Internal, so it has no Rd page.
#' @noRd
GenUIAdapter <- R6::R6Class(
  "GenUIAdapter",
  cloneable = FALSE,
  public = list(
    initialize = function(prepare = TRUE, data_env = globalenv()) {
      private$data_env <- data_env
      if (isTRUE(prepare)) self$prepare()
    },

    # Build the frozen catalog. Cheap to call again; the app calls it under
    # the initialization overlay rather than on the path to first paint.
    prepare = function() {
      if (!is.null(private$catalog_)) return(invisible(self))
      missing <- .genui_missing()
      if (length(missing)) {
        refs <- ifelse(missing == "shinygenui", "nanxstats/shinygenui", missing)
        stop("[codeagent] Generative UI needs the suggested package(s) ",
             paste0("'", missing, "'", collapse = ", "), ". Install with ",
             "pak::pak(c(", paste0("\"", refs, "\"", collapse = ", "), ")).",
             call. = FALSE)
      }
      catalog <- .genui_build_catalog()
      private$digest_ <- .genui_catalog_digest(catalog)
      private$prompt_ <- .genui_prompt_fragment(catalog)
      private$catalog_ <- catalog
      invisible(self)
    },
    prepared        = function() !is.null(private$catalog_),
    catalog         = function() { self$prepare(); private$catalog_ },
    digest          = function() { self$prepare(); private$digest_ },
    tool_names      = function() .genui_tool_names(),
    prompt_fragment = function() { self$prepare(); private$prompt_ },
    tools           = function() .genui_build_tools(self),

    # Attach to a browser session. A second, different session poisons the
    # adapter: tool calls cannot be attributed to a session, so a shared
    # adapter would draw one user's canvas from another user's conversation.
    bind = function(session, ops = NULL) {
      key <- if (is.null(session)) "local"
             else if (is.character(session)) session
             else tryCatch(session$token, error = function(e) "session")
      if (!is.null(private$session_key) && !identical(private$session_key, key))
        private$poisoned_ <- TRUE
      private$session_key <- key
      private$ops <- ops %||% .genui_shiny_ops(session)
      invisible(self)
    },
    poisoned = function() isTRUE(private$poisoned_),

    begin_turn = function() {
      private$turn_open <- TRUE
      private$turn_mutations <- 0L
      private$turn_start <- length(private$trace)
      invisible(self)
    },
    cancel_turn = function() {
      private$turn_open <- FALSE
      invisible(self)
    },

    # Run one canvas tool call. Never throws: every failure becomes an error
    # tool result carrying an actionable message, so the model can correct
    # its arguments (and the Data Shield wrapper never has to withhold it).
    call = function(tool_name, args = list()) {
      request_id <- .genui_request_id()
      tryCatch(private$run(tool_name, args %||% list(), request_id),
               error = function(e) .genui_error_result(.genui_message(e)))
    },

    state   = function() private$state_,
    summary = function() .genui_state_summary(private$state_),

    # Persistable form. `present_ids` are the tool request ids in the chat at
    # save time; an op bound to a present request must still find it on
    # restore, which is what ties the canvas to the conversation it came from.
    snapshot = function(present_ids = NULL) {
      trace <- lapply(private$trace, function(op) {
        bound <- !is.na(op$request_id)
        op$present <- bound && !is.null(present_ids) &&
          op$request_id %in% present_ids
        if (!bound) op$request_id <- NULL
        op
      })
      list(schema = .GENUI_STATE_SCHEMA, version = .GENUI_STATE_VERSION,
           catalog_digest = if (self$prepared()) private$digest_ else NULL,
           trace = trace)
    },

    # Strict restore: verify, fold the whole trace through dispatch, then mount
    # only the final instances. Any failure leaves an empty canvas and says so.
    restore = function(snapshot, present_ids = character()) {
      fail <- function(reason) {
        private$clear_all()
        list(ok = FALSE, message = paste0(
          "The canvas could not be safely restored: ", reason))
      }
      if (is.null(snapshot)) { private$clear_all(); return(list(ok = TRUE, count = 0L)) }
      tryCatch(self$prepare(), error = function(e) NULL)
      if (!self$prepared()) return(fail("generative UI is unavailable."))
      if (!identical(snapshot$schema, .GENUI_STATE_SCHEMA) ||
          !identical(as.integer(unlist(snapshot$version)), .GENUI_STATE_VERSION))
        return(fail("the saved canvas has an unknown format."))
      if (!identical(as.character(unlist(snapshot$catalog_digest)), private$digest_))
        return(fail("the canvas components changed since it was saved."))
      trace <- lapply(snapshot$trace %||% list(), .genui_normalize_op)
      for (op in trace)
        if (isTRUE(op$present) && !op$request_id %in% present_ids)
          return(fail("it no longer matches the conversation."))
      err <- private$rebuild(trace)
      if (!is.null(err)) return(fail(err))
      list(ok = TRUE, count = length(private$state_$instances))
    },

    # Empty the canvas and forget its history (New, Delete, /clear).
    reset = function() {
      private$clear_all()
      invisible(self)
    },

    # Drop every op from the first one whose request left the conversation
    # (rewind removed its turn), then rebuild from what remains.
    forget_requests = function(removed_ids) {
      k <- private$first_op(function(op)
        !is.na(op$request_id) && op$request_id %in% removed_ids)
      private$truncate_at(k)
    },

    # End of a turn: ops made this turn whose request never reached the chat
    # (the turn was cancelled and ellmer dropped the round) are rolled back.
    settle_turn = function(present_ids) {
      k <- private$first_op(function(op)
        !is.na(op$request_id) && !op$request_id %in% present_ids,
        from = private$turn_start + 1L)
      private$truncate_at(k)
    }
  ),

  private = list(
    catalog_ = NULL, digest_ = NULL, prompt_ = NULL,
    data_env = NULL, ops = NULL, session_key = NULL, poisoned_ = FALSE,
    state_ = list(instances = list(), next_id = 1L),
    runtime = list(), trace = list(), mounts = list(),
    turn_open = TRUE, turn_mutations = 0L, turn_start = 0L,

    resolve = function(name) .genui_resolve_dataset(name, private$data_env),

    # A module scope id never reused within this session: Shiny destroys a
    # scope for good, so each mount of an instance gets its own.
    next_module_id = function(id) {
      n <- (private$mounts[[id]] %||% 0L) + 1L
      private$mounts[[id]] <- n
      .genui_module_id(id, n)
    },

    run = function(tool_name, args, request_id) {
      if (isTRUE(private$poisoned_))
        stop("The canvas is disabled: this client is shared by more than one ",
             "browser session. Build the app from a bare Chat or a ",
             "client_factory so each session gets its own canvas.", call. = FALSE)
      if (is.null(private$ops))
        stop("The canvas is not attached to a browser session.", call. = FALSE)
      if (!isTRUE(private$turn_open))
        stop("This turn was cancelled; the canvas was not changed.", call. = FALSE)
      self$prepare()
      if (identical(tool_name, "canvas_state")) return(private$state_result())

      dispatch <- .genui_dispatch_name(tool_name)
      action <- .genui_action(dispatch)
      dataset <- NULL
      if (identical(action, "create")) {
        dataset <- args$dataset
        args$dataset <- NULL
      }
      checked <- if (identical(action, "update"))
        c(list(id = args$id), .genui_update_delta(args$args)) else args
      msg <- .genui_validate_strings(c(checked, list(dataset = dataset)))
      if (is.null(msg))
        msg <- .genui_quota_check(action, checked,
                                  live = length(private$state_$instances),
                                  turn_mutations = private$turn_mutations,
                                  trace_len = length(private$trace))
      if (!is.null(msg)) stop(msg, call. = FALSE)

      data <- NULL
      if (identical(action, "create")) data <- private$resolve(dataset)
      if (identical(action, "update") && is.character(args$id) &&
          length(args$id) == 1L) {
        inst <- private$state_$instances[[args$id]]
        if (!is.null(inst)) {
          dataset <- inst$dataset
          data <- private$resolve(dataset)
        }
      }
      plan <- shinygenui::genui_dispatch(
        private$catalog_, shinygenui::genui_call(dispatch, args),
        private$state_, data = data)
      op <- .genui_plan_to_op(plan)
      op$dataset <- dataset
      op$request_id <- request_id
      private$execute(op, data)
      private$commit(op)
      .genui_success_result(op, private$digest_)
    },

    execute = function(op, data) {
      ops <- private$ops
      data_fn <- function() data
      switch(op$action,
        create = {
          comp <- private$catalog_[[op$component]]
          private$runtime[[op$id]] <- .genui_mount(
            comp, op$id, op$args, data_fn, ops,
            module_id = private$next_module_id(op$id))
        },
        update = {
          comp <- private$catalog_[[op$component]]
          old <- private$state_$instances[[op$id]]$args
          private$runtime[[op$id]] <- tryCatch(
            .genui_remount(comp, op$id, old, op$args,
                           private$runtime[[op$id]], data_fn, ops,
                           module_id = private$next_module_id(op$id),
                           rollback_module_id = private$next_module_id(op$id)),
            error = function(e) {
              private$runtime[[op$id]] <- attr(e, "restored")
              stop(e)
            })
        },
        remove = , clear = {
          for (id in op$ids) {
            .genui_unmount(id, private$runtime[[id]], ops)
            private$runtime[[id]] <- NULL
          }
        })
      invisible(NULL)
    },

    commit = function(op) {
      private$state_ <- .genui_apply_op(private$state_, op)
      private$trace[[length(private$trace) + 1L]] <- op[c(
        "action", "id", "component", "args", "parent_id", "ids", "dataset",
        "request_id")]
      private$turn_mutations <- private$turn_mutations + 1L
    },

    state_result = function() {
      inst <- private$state_$instances
      ops <- private$ops
      rows <- lapply(names(inst), function(id) {
        inputs <- tryCatch(ops$input_values(private$runtime[[id]]$module_id),
                           error = function(e) NULL)
        out <- list(id = id, component = inst[[id]]$component,
                    dataset = inst[[id]]$dataset, args = inst[[id]]$args,
                    inputs = inputs)
        out[!vapply(out, is.null, logical(1L))]
      })
      value <- if (!length(rows)) "The canvas is empty." else
        as.character(jsonlite::toJSON(rows, auto_unbox = TRUE, null = "null"))
      ellmer::ContentToolResult(
        value = value,
        extra = list(display = .new_tool_result_display(
          title = "Canvas: read state", icon = .icon_tag("bar-chart"),
          text = sprintf("Read %d component(s).", length(rows)),
          show_request = FALSE, open = FALSE, label = "Canvas: read state")))
    },

    clear_all = function() {
      ops <- private$ops
      if (!is.null(ops))
        for (id in names(private$runtime))
          .genui_unmount(id, private$runtime[[id]], ops)
      private$runtime <- list()
      private$state_ <- .genui_empty_state()
      private$trace <- list()
      private$turn_start <- 0L
      invisible(NULL)
    },

    first_op = function(pred, from = 1L) {
      n <- length(private$trace)
      if (from > n) return(NA_integer_)
      for (k in seq.int(from, n)) if (isTRUE(pred(private$trace[[k]]))) return(k)
      NA_integer_
    },

    truncate_at = function(k) {
      if (is.na(k)) return(invisible(NULL))
      err <- private$rebuild(utils::head(private$trace, k - 1L))
      if (!is.null(err)) private$clear_all()
      invisible(err)
    },

    # Replace the live canvas with the fold of `trace`. Returns NULL on
    # success or a reason string after leaving the canvas empty.
    rebuild = function(trace) {
      state <- tryCatch(
        .genui_fold_trace(private$catalog_, trace, private$resolve),
        error = function(e) e)
      if (inherits(state, "error")) return(.genui_message(state))
      private$clear_all()
      ops <- private$ops
      if (!is.null(ops)) {
        for (id in names(state$instances)) {
          inst <- state$instances[[id]]
          mounted <- tryCatch({
            data <- private$resolve(inst$dataset)
            .genui_mount(private$catalog_[[inst$component]], id, inst$args,
                         function() data, ops,
                         module_id = private$next_module_id(id))
          }, error = function(e) e)
          if (inherits(mounted, "error")) {
            private$clear_all()
            return(.genui_message(mounted))
          }
          private$runtime[[id]] <- mounted
        }
      }
      private$state_ <- state
      private$trace <- trace
      private$turn_start <- min(private$turn_start, length(trace))
      NULL
    }
  )
)
