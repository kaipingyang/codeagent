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

# Components codeagent admits: everything shinygenui provides today (its bslib
# starter pack plus card_row). A component upstream adds later is a candidate,
# left out until reviewed, never rejected. markdown_card is safe here only
# because .genui_validate_strings() refuses markup, links and URLs in every
# model-authored string before shiny::markdown() ever sees it.
.GENUI_ADMITTED <- c("value_box", "data_table", "scatter_plot", "histogram",
                     "markdown_card", "card_row")

# Argument types shinygenui re-validates completely on every dispatch,
# including replay. Any other ellmer type would be trusted to the provider on
# a live call and checked by nobody on restore (research 5.3).
.GENUI_TYPE_CLASSES <- c("ellmer::TypeBasic", "ellmer::TypeEnum",
                         "ellmer::TypeArray", "ellmer::TypeObject")

#' @keywords internal
.genui_type_supported <- function(type) {
  cls <- intersect(class(type), .GENUI_TYPE_CLASSES)
  if (!length(cls)) return(FALSE)
  if (identical(cls[[1L]], "ellmer::TypeArray"))
    return(.genui_type_supported(type@items))
  if (identical(cls[[1L]], "ellmer::TypeObject"))
    return(all(vapply(type@properties, .genui_type_supported, logical(1L))))
  TRUE
}

# Build the frozen catalog from a candidate component list. An admitted
# component that is missing is an error -- the prompt would otherwise promise a
# component the catalog cannot build -- and so is an admitted component with
# an argument type the local validator does not cover.
#' @keywords internal
.genui_admit_catalog <- function(components, admitted = .GENUI_ADMITTED) {
  names_ <- vapply(components, function(x) as.character(x$name), character(1L))
  missing <- setdiff(admitted, names_)
  if (length(missing))
    stop("[codeagent] shinygenui no longer provides admitted component(s): ",
         paste0("\"", missing, "\"", collapse = ", "),
         ". The installed shinygenui does not match the reviewed contract.",
         call. = FALSE)
  admitted <- components[names_ %in% admitted]
  for (comp in admitted) {
    bad <- names(Filter(Negate(.genui_type_supported), comp$args))
    if (length(bad))
      stop("[codeagent] Canvas component \"", comp$name, "\" has argument(s) ",
           paste0("\"", bad, "\"", collapse = ", "), " of a type codeagent ",
           "cannot validate on replay; it is not admitted.", call. = FALSE)
  }
  do.call(shinygenui::genui_catalog, admitted)
}

# Bumped when codeagent changes how a trace is executed or replayed.
.GENUI_ADAPTER_VERSION <- "3"

# Implementation identity of a saved canvas (research 8.3): component names,
# each argument's full type (nested items and properties included), the
# ui/server/check implementations, the shinygenui version and the adapter
# version. Sorted, so component order does not matter. Functions enter as
# deparsed text -- closures and S7 objects do not hash stably across processes.
#' @keywords internal
.genui_catalog_digest <- function(catalog, version = NULL) {
  version <- version %||% tryCatch(
    as.character(utils::packageVersion("shinygenui")), error = function(e) "?")
  describe_arg <- function(type) list(
    type       = class(type)[[1L]],
    values     = tryCatch(type@values, error = function(e) NULL),
    required   = tryCatch(type@required, error = function(e) NULL),
    items      = tryCatch(describe_arg(type@items), error = function(e) NULL),
    properties = tryCatch(lapply(type@properties, describe_arg),
                          error = function(e) NULL))
  # A builder such as canvas_component_output() keeps the real implementation
  # in its closure (render_fn, widget_fn, ...), so closures are followed: the
  # function-valued bindings of a non-namespace enclosing environment count too.
  code <- function(f, depth = 3L) {
    if (!is.function(f)) return("")
    own <- paste(c(deparse(formals(f)), deparse(body(f))), collapse = "\n")
    env <- environment(f)
    if (depth <= 0L || !is.environment(env) || isNamespace(env) ||
        identical(env, globalenv()) || identical(env, baseenv()) ||
        identical(env, emptyenv()))
      return(own)
    nms <- sort(ls(env, all.names = TRUE))
    inner <- vapply(nms, function(nm) {
      val <- get0(nm, envir = env, inherits = FALSE)
      if (is.function(val) && !identical(val, f))
        paste0(nm, "=", code(val, depth - 1L)) else ""
    }, character(1L))
    paste(c(own, inner[nzchar(inner)]), collapse = "\n")
  }
  comps <- lapply(sort(names(catalog)), function(nm) {
    comp <- catalog[[nm]]
    arg_names <- sort(names(comp$args))
    list(name = nm, container = isTRUE(comp$container), width = comp$width,
         args = stats::setNames(lapply(arg_names, function(a)
           describe_arg(comp$args[[a]])), arg_names),
         impl = vapply(list(comp$ui, comp$server, comp$check), code, ""))
  })
  rlang::hash(list(components = comps, shinygenui = version,
                   adapter = .GENUI_ADAPTER_VERSION))
}

# A component reads a data frame when it has a server or a check; only those
# tools take a `dataset` argument.
.genui_needs_data <- function(component) {
  if (!is.null(component$needs_data)) return(isTRUE(component$needs_data))
  !is.null(component$server) || !is.null(component$check)
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
                      canvas_state  = NA_character_,
                      canvas_refresh = NA_character_)

#' @keywords internal
.genui_tool_name <- function(component) paste0(.GENUI_PREFIX, component)

# The shinygenui call name for a tool, or NULL for the adapter-owned
# canvas_state and canvas_refresh.
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
.genui_tool_names <- function(components = .GENUI_ADMITTED) {
  c(.genui_tool_name(components), names(.GENUI_LIFECYCLE))
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
.genui_available <- function(options = canvas_options())
  !length(.genui_missing(.genui_required_packages(options)))

#' @noRd
.genui_build_catalog <- function(options = canvas_options()) {
  starter <- .genui_starter_names(options)
  # Unbound (data = NULL): column names stay out of the tool schema and the
  # catalog survives the conversation moving between data sets.
  pool <- if (length(starter))
    Filter(function(x) x$name %in% starter,
           c(shinygenui::genui_components_bslib(data = NULL),
             list(shinygenui::genui_card_row())))
  else list()
  host <- vapply(options$components, function(x) as.character(x$name), character(1L))
  .genui_admit_catalog(c(pool, options$components), admitted = c(starter, host))
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
      else "The canvas was already empty.",
    refresh = if (length(op$ids))
      sprintf("Redrew %s from the current data.", paste(op$ids, collapse = ", "))
      else "No canvas component reads a data frame; nothing to refresh.")
  title <- switch(op$action,
    create = paste("Canvas: added", op$component),
    update = paste("Canvas: updated", op$id),
    remove = paste("Canvas: removed", op$id),
    clear  = "Canvas: cleared",
    refresh = "Canvas: refreshed")
  artifact <- .genui_artifact(op, digest, title)
  display <- .new_tool_result_display(
    title = .safe_tool_display_title(title), icon = .icon_tag("bar-chart"),
    text = value, show_request = FALSE, open = FALSE,
    # shinychat shows "title: label"; the label names the instance instead of
    # repeating the title.
    label = switch(op$action,
                   create = paste(op$id, op$component),
                   clear = paste(length(op$ids), "removed"),
                   refresh = paste(op$ids, collapse = ", "),
                   op$id),
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
  has_containers <- any(vapply(catalog, function(x) isTRUE(x$container), logical(1L)))
  parent_type <- ellmer::type_string(paste(
    "Optional id of an existing container component (for example \"c1\") to",
    "place this component into. Omit to place it directly on the canvas."),
    required = FALSE)
  component_tools <- lapply(names(catalog), function(nm) {
    comp <- catalog[[nm]]
    reserved <- intersect(c("dataset", "parent_id"), names(comp$args))
    if (length(reserved))
      stop("[codeagent] Canvas component \"", nm, "\" already declares ",
           paste0("`", reserved, "`", collapse = ", "), ".", call. = FALSE)
    tool_name <- .genui_tool_name(nm)
    arguments <- c(if (.genui_needs_data(comp)) list(dataset = dataset_type),
                   comp$args,
                   if (has_containers) list(parent_id = parent_type))
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
      .genui_tool_fn("id", function(args) adapter$call("canvas_refresh", args)),
      name = "canvas_refresh",
      description = paste(
        "Redraw canvas components from the current contents of their data",
        "frames. Call it after you change a data frame a component shows.",
        "Pass an id to refresh one component, or omit it to refresh them all."),
      arguments = list(id = ellmer::type_string(
        "The component id to refresh. Omit to refresh every data component.",
        required = FALSE)),
      annotations = ellmer::tool_annotations(title = "Canvas: refresh")),
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
    initialize = function(prepare = TRUE, data_env = NULL,
                          options = canvas_options()) {
      if (!inherits(options, "codeagent_canvas_options"))
        stop("`options` must come from canvas_options().", call. = FALSE)
      private$options <- options
      private$data_env <- data_env %||% options$data_env
      if (isTRUE(prepare)) self$prepare()
    },

    # Build the frozen catalog. Cheap to call again; the app calls it under
    # the initialization overlay rather than on the path to first paint.
    prepare = function() {
      if (!is.null(private$catalog_)) return(invisible(self))
      missing <- .genui_missing(.genui_required_packages(private$options))
      if (length(missing)) {
        refs <- ifelse(missing == "shinygenui", "nanxstats/shinygenui", missing)
        stop("[codeagent] Generative UI needs the suggested package(s) ",
             paste0("'", missing, "'", collapse = ", "), ". Install with ",
             "pak::pak(c(", paste0("\"", refs, "\"", collapse = ", "), ")).",
             call. = FALSE)
      }
      catalog <- .genui_build_catalog(private$options)
      # Host components become canvas tools too: declare each read-only by its
      # exact name, as the built-in ones are in .TOOL_META.
      for (nm in setdiff(names(catalog), .GENUI_ADMITTED))
        register_tool_meta(.genui_tool_name(nm), "read")
      private$digest_ <- .genui_catalog_digest(catalog)
      private$prompt_ <- .genui_prompt_fragment(catalog)
      private$catalog_ <- catalog
      invisible(self)
    },
    prepared        = function() !is.null(private$catalog_),
    catalog         = function() { self$prepare(); private$catalog_ },
    digest          = function() { self$prepare(); private$digest_ },
    tool_names      = function() .genui_tool_names(names(self$catalog())),
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
    summary = function() .genui_state_summary(private$state_,
                                              stale = self$stale_ids()),

    # Components whose data frame changed (or vanished) since they were drawn.
    stale_ids = function() {
      inst <- private$state_$instances
      ids <- names(inst)[vapply(inst, function(x) !is.null(x$dataset), logical(1L))]
      ids[vapply(ids, function(id) {
        now <- tryCatch(.genui_fingerprint(private$resolve(inst[[id]]$dataset)),
                        error = function(e) NA_character_)
        !identical(now, private$fingerprints[[id]])
      }, logical(1L))]
    },

    # Tell the browser which components are out of date (a badge per shell).
    mark_stale = function() {
      ops <- private$ops
      if (is.function(ops$mark_stale))
        tryCatch(ops$mark_stale(self$stale_ids()), error = function(e) NULL)
      invisible(self)
    },

    # Redraw data components from the current data. Not a trace op: the args
    # do not change, and restore always reads the current data anyway.
    # Returns the ids refreshed; failures are collected and rethrown together.
    refresh = function(id = NULL) {
      self$prepare()
      inst <- private$state_$instances
      data_ids <- names(inst)[vapply(inst, function(x) !is.null(x$dataset), logical(1L))]
      if (!is.null(id)) {
        if (!is.character(id) || length(id) != 1L || is.null(inst[[id]]))
          stop("No canvas component with id \"", paste(id, collapse = ""), "\". ",
               .genui_state_summary(private$state_), call. = FALSE)
        if (!id %in% data_ids)
          stop("Canvas component \"", id, "\" does not read a data frame.",
               call. = FALSE)
        data_ids <- id
      }
      problems <- character()
      for (one in data_ids) {
        err <- tryCatch({ private$refresh_one(one); NULL },
                        error = function(e) .genui_message(e))
        if (!is.null(err)) problems <- c(problems, paste0(one, ": ", err))
      }
      self$mark_stale()
      if (length(problems))
        stop("Could not refresh ", paste(problems, collapse = " "),
             " The previous view is still shown.", call. = FALSE)
      invisible(data_ids)
    },

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
           trace = trace, fingerprints = private$fingerprints)
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
      saved <- lapply(snapshot$fingerprints %||% list(),
                      function(x) as.character(unlist(x))[[1L]])
      changed <- names(saved)[vapply(names(saved), function(id)
        !is.null(private$fingerprints[[id]]) &&
          !identical(saved[[id]], private$fingerprints[[id]]), logical(1L))]
      list(ok = TRUE, count = length(private$state_$instances),
           changed = changed,
           message = if (length(changed)) paste0(
             "The data behind canvas component(s) ", paste(changed, collapse = ", "),
             " changed since this session was saved; the canvas shows the ",
             "current data."))
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
    options = NULL, data_env = NULL, ops = NULL, session_key = NULL,
    poisoned_ = FALSE,
    state_ = list(instances = list(), next_id = 1L),
    runtime = list(), trace = list(), mounts = list(), fingerprints = list(),
    turn_open = TRUE, turn_mutations = 0L, turn_start = 0L,

    resolve = function(name) .genui_resolve_dataset(name, private$data_env),

    remember_data = function(id, data) {
      if (!is.null(data)) private$fingerprints[[id]] <- .genui_fingerprint(data)
    },

    # Re-validate one data component against its current data frame and
    # remount it. shinygenui's own check runs first, so a column that is gone
    # fails before the DOM changes; the old view then stays and reads stale.
    refresh_one = function(id) {
      inst <- private$state_$instances[[id]]
      data <- private$resolve(inst$dataset)
      shinygenui::genui_dispatch(
        private$catalog_,
        shinygenui::genui_call("update_component", list(id = id, args = list())),
        private$state_, data = data)
      comp <- private$catalog_[[inst$component]]
      private$runtime[[id]] <- tryCatch(
        .genui_remount(comp, id, inst$args, inst$args, private$runtime[[id]],
                       .genui_data_fn(data), private$ops,
                       module_id = private$next_module_id(id),
                       rollback_module_id = private$next_module_id(id)),
        error = function(e) {
          private$runtime[[id]] <- attr(e, "restored")
          stop(e)
        })
      if (isTRUE(comp$container)) private$remount_children(id)
      private$remember_data(id, data)
    },

    # Where a new component's shell goes: the canvas, or its container's slot.
    target = function(parent_id) {
      if (is.null(parent_id)) return(paste0("#", .GENUI_CANVAS_ID))
      paste0("#", private$runtime[[parent_id]]$module_id, "-slot")
    },

    check_depth = function(parent_id) {
      depth <- 1L
      id <- parent_id
      while (is.character(id) && !is.null(private$state_$instances[[id]])) {
        depth <- depth + 1L
        id <- private$state_$instances[[id]]$parent_id
      }
      if (depth > .GENUI_LIMITS$max_depth)
        stop(sprintf("Canvas containers nest at most %d levels deep.",
                     .GENUI_LIMITS$max_depth), call. = FALSE)
    },

    # Mount every descendant of `id` again, parents before children, into the
    # slots of its freshly mounted container.
    remount_children = function(id) {
      inst <- private$state_$instances
      ops <- private$ops
      for (child in .genui_descendants(inst, id)) {
        .genui_unmount(child, private$runtime[[child]], ops)
        ci <- inst[[child]]
        data <- if (!is.null(ci$dataset)) private$resolve(ci$dataset)
        private$runtime[[child]] <- .genui_mount(
          private$catalog_[[ci$component]], child, ci$args, .genui_data_fn(data), ops,
          module_id = private$next_module_id(child),
          target = private$target(ci$parent_id))
        private$remember_data(child, data)
      }
      invisible(NULL)
    },

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
      if (identical(tool_name, "canvas_refresh")) {
        msg <- .genui_quota_check("refresh", args, live = 0L,
                                  turn_mutations = private$turn_mutations,
                                  trace_len = 0L)
        if (!is.null(msg)) stop(msg, call. = FALSE)
        private$turn_mutations <- private$turn_mutations + 1L
        ids <- self$refresh(args$id)
        return(.genui_success_result(
          list(action = "refresh", id = args$id, ids = ids), private$digest_))
      }

      dispatch <- .genui_dispatch_name(tool_name)
      action <- .genui_action(dispatch)
      dataset <- NULL
      component <- if (identical(action, "create")) private$catalog_[[dispatch]]
      needs_data <- !is.null(component) && .genui_needs_data(component)
      if (isTRUE(needs_data)) {
        dataset <- args$dataset
        args$dataset <- NULL
      }
      if (identical(action, "create") && !is.null(args$parent_id))
        private$check_depth(args$parent_id)
      checked <- if (identical(action, "update"))
        c(list(id = args$id), .genui_update_delta(args$args)) else args
      msg <- if (isTRUE(private$options$validate_text))
        .genui_validate_strings(c(checked, list(dataset = dataset)))
      if (is.null(msg))
        msg <- .genui_quota_check(action, checked,
                                  live = length(private$state_$instances),
                                  turn_mutations = private$turn_mutations,
                                  trace_len = length(private$trace))
      if (!is.null(msg)) stop(msg, call. = FALSE)

      data <- NULL
      if (isTRUE(needs_data)) data <- private$resolve(dataset)
      if (identical(action, "update") && is.character(args$id) &&
          length(args$id) == 1L) {
        inst <- private$state_$instances[[args$id]]
        if (!is.null(inst$dataset)) {
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
      data_fn <- .genui_data_fn(data)
      switch(op$action,
        create = {
          comp <- private$catalog_[[op$component]]
          private$runtime[[op$id]] <- .genui_mount(
            comp, op$id, op$args, data_fn, ops,
            module_id = private$next_module_id(op$id),
            target = private$target(op$parent_id))
          private$remember_data(op$id, data)
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
              if (isTRUE(comp$container)) private$remount_children(op$id)
              stop(e)
            })
          # The container's slot was rebuilt under a new scope, so its
          # children are mounted again into it. If that fails, the canvas is
          # rebuilt from the trace, which does not contain this update yet.
          if (isTRUE(comp$container)) {
            err <- tryCatch({ private$remount_children(op$id); NULL },
                            error = function(e) e)
            if (!is.null(err)) {
              private$rebuild(private$trace)
              stop(err)
            }
          }
          private$remember_data(op$id, data)
        },
        remove = , clear = {
          for (id in op$ids) {
            .genui_unmount(id, private$runtime[[id]], ops)
            private$runtime[[id]] <- NULL
            private$fingerprints[[id]] <- NULL
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
      private$fingerprints <- list()
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
          data <- NULL
          mounted <- tryCatch({
            data <- if (!is.null(inst$dataset)) private$resolve(inst$dataset)
            .genui_mount(private$catalog_[[inst$component]], id, inst$args,
                         .genui_data_fn(data), ops,
                         module_id = private$next_module_id(id),
                         target = private$target(inst$parent_id))
          }, error = function(e) e)
          if (inherits(mounted, "error")) {
            private$clear_all()
            return(.genui_message(mounted))
          }
          private$runtime[[id]] <- mounted
          private$remember_data(id, data)
        }
      }
      private$state_ <- state
      private$trace <- trace
      private$turn_start <- min(private$turn_start, length(trace))
      NULL
    }
  )
)
