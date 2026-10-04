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

#' @noRd
.genui_missing <- function(pkgs = c("shinygenui", .GENUI_STARTER_DEPS)) {
  pkgs[!vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)]
}

#' @noRd
.genui_available <- function() !length(.genui_missing())

# Facade over the GenUI subsystem, shaped like DataShield: the R6 object holds
# state and lifecycle, the .genui_* functions above hold the testable logic.
# Phase 0 freezes the catalog and exposes what the rest of codeagent needs from
# it; the executor, install(chat) and canvas state arrive with Phase 1. Internal
# until then, so it has no Rd page.
#' @noRd
GenUIAdapter <- R6::R6Class(
  "GenUIAdapter",
  cloneable = FALSE,
  public = list(
    initialize = function() {
      missing <- .genui_missing()
      if (length(missing)) {
        refs <- ifelse(missing == "shinygenui", "nanxstats/shinygenui", missing)
        stop("[codeagent] Generative UI needs the suggested package(s) ",
             paste0("'", missing, "'", collapse = ", "), ". Install with ",
             "pak::pak(c(", paste0("\"", refs, "\"", collapse = ", "), ")).",
             call. = FALSE)
      }
      # Unbound (data = NULL): column names stay out of the tool schema and the
      # catalog survives the conversation moving between data sets.
      private$catalog_ <- .genui_admit_catalog(
        shinygenui::genui_components_bslib(data = NULL))
      private$digest_ <- .genui_catalog_digest(private$catalog_)
      private$prompt_ <- .genui_prompt_fragment(private$catalog_)
    },
    catalog         = function() private$catalog_,
    digest          = function() private$digest_,
    tool_names      = function() .genui_tool_names(),
    prompt_fragment = function() private$prompt_
  ),
  private = list(catalog_ = NULL, digest_ = NULL, prompt_ = NULL)
)
