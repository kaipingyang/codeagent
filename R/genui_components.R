#' Configure the generative UI canvas
#'
#' Choose which components the canvas in [codeagent_app()] offers and how
#' strictly model-authored text is checked. Components are the same objects
#' shinygenui uses ([shinygenui::genui_component()]); build your own with
#' [canvas_component_output()] or [canvas_component_widget()], or pass any
#' existing `genui_component`.
#'
#' Host components are trusted code: codeagent registers them as canvas tools
#' (read-only, behind the central permission gate), runs them through the same
#' transactional executor, Data Shield scanning and strict session restore as
#' the built-in ones, and leaves what they render to you.
#'
#' @param components A list of `genui_component` objects supplied by the host.
#' @param starter Which of shinygenui's own components to offer: `TRUE` (all of
#'   them, the default), `FALSE` (none), or a character vector of their names
#'   (`"value_box"`, `"data_table"`, `"scatter_plot"`, `"histogram"`,
#'   `"markdown_card"`, `"card_row"`).
#' @param data_env Environment in which `dataset` names are looked up.
#' @param csp Content Security Policy for the page while the canvas is
#'   available: `TRUE` (default; images, media, frames and plugins only from
#'   the app itself), `FALSE` (none), or a policy string of your own -- for
#'   example when a component loads map tiles from another origin.
#' @param validate_text If `TRUE` (default), every string the model passes to
#'   a canvas tool is refused when it contains markup, links, URLs or control
#'   characters, before anything reaches the browser. This guards against the
#'   model (or a prompt injection) placing data in a URL the browser would
#'   fetch. Set `FALSE` when your components need the model to supply URLs.
#' @return A `codeagent_canvas_options` object for `codeagent_app(canvas = )`.
#' @seealso [canvas_component_output()], [canvas_component_widget()]
#' @examples
#' \dontrun{
#' boxplot_card <- canvas_component_output(
#'   "boxplot", "Box plot of a numeric column by group.",
#'   args = list(y = ellmer::type_string("Numeric column."),
#'               by = ellmer::type_string("Grouping column.")),
#'   output = shiny::plotOutput,
#'   render = function(args, data) shiny::renderPlot(
#'     boxplot(reformulate(args$by, args$y), data = data())))
#' codeagent_app(chat, canvas = canvas_options(
#'   components = list(boxplot_card), starter = c("data_table", "histogram")))
#' }
#' @export
canvas_options <- function(components = list(), starter = TRUE,
                           data_env = globalenv(), csp = TRUE,
                           validate_text = TRUE) {
  if (inherits(components, "genui_component")) components <- list(components)
  if (!is.list(components) ||
      !all(vapply(components, inherits, logical(1L), "genui_component")))
    stop("`components` must be a list of genui_component objects (build them ",
         "with canvas_component_output(), canvas_component_widget() or ",
         "shinygenui::genui_component()).", call. = FALSE)
  if (!(isTRUE(starter) || isFALSE(starter) ||
        (is.character(starter) && !anyNA(starter))))
    stop("`starter` must be TRUE, FALSE or a character vector of component names.",
         call. = FALSE)
  if (is.character(starter)) {
    unknown <- setdiff(starter, .GENUI_ADMITTED)
    if (length(unknown))
      stop("Unknown `starter` component(s): ",
           paste0("\"", unknown, "\"", collapse = ", "), ". shinygenui provides ",
           paste0("\"", .GENUI_ADMITTED, "\"", collapse = ", "), ".", call. = FALSE)
  }
  if (!is.environment(data_env))
    stop("`data_env` must be an environment.", call. = FALSE)
  if (!(isTRUE(csp) || isFALSE(csp) ||
        (is.character(csp) && length(csp) == 1L && !is.na(csp))))
    stop("`csp` must be TRUE, FALSE or a single policy string.", call. = FALSE)
  if (!(isTRUE(validate_text) || isFALSE(validate_text)))
    stop("`validate_text` must be TRUE or FALSE.", call. = FALSE)

  host <- vapply(components, function(x) as.character(x$name), character(1L))
  bad <- host[!grepl("^[A-Za-z][A-Za-z0-9_]*$", host)]
  if (length(bad))
    stop("Canvas component names must start with a letter and use only letters, ",
         "digits and underscores: ", paste0("\"", bad, "\"", collapse = ", "), ".",
         call. = FALSE)
  reserved <- intersect(host, sub("^canvas_", "", names(.GENUI_LIFECYCLE)))
  if (length(reserved))
    stop("Canvas component name(s) ", paste0("\"", reserved, "\"", collapse = ", "),
         " are reserved for canvas lifecycle tools.", call. = FALSE)
  if (anyDuplicated(host))
    stop("Canvas component \"", host[anyDuplicated(host)], "\" is given more than once.",
         call. = FALSE)
  starter_names <- if (isTRUE(starter)) .GENUI_ADMITTED else
    if (isFALSE(starter)) character() else starter
  clash <- intersect(host, starter_names)
  if (length(clash))
    stop("Canvas component(s) ", paste0("\"", clash, "\"", collapse = ", "),
         " clash with shinygenui's own; rename them or leave the starter ",
         "component out with `starter = `.", call. = FALSE)

  structure(list(components = components, starter = starter,
                 data_env = data_env, csp = csp, validate_text = validate_text),
            class = "codeagent_canvas_options")
}

#' Build a canvas component from a Shiny output
#'
#' Wraps any `*Output()` / `render*()` pair -- base Shiny, or a package such
#' as plotly (`plotlyOutput` / `renderPlotly`) -- as a canvas component.
#'
#' @param name Component name; the model calls it as `canvas_<name>`.
#' @param description What the component shows; the model reads it.
#' @param args Named list of ellmer types (`ellmer::type_string()`,
#'   `type_enum()`, `type_integer()`, `type_array()`, ...) for the arguments the
#'   model fills in. Other ellmer types cannot be re-validated on restore and
#'   are refused.
#' @param output An output constructor taking an output id, e.g.
#'   `shiny::plotOutput`.
#' @param render `function(args, data)` returning a render function, e.g.
#'   `shiny::renderPlot(...)`. `data` is a function returning the data frame
#'   the model named in `dataset` (or `NULL` when `data = FALSE`).
#' @param check Optional `function(args, data)` returning `NULL` when the
#'   arguments fit the data, or a message the model sees when they do not.
#'   `data` is the data frame itself.
#' @param width One of `"auto"`, `"wide"`, `"full"`.
#' @param data If `TRUE` (default) the tool takes a `dataset` argument naming a
#'   data frame.
#' @param code Optional `function(args, dataset)` returning standalone R code
#'   that reproduces the component, used when the canvas is exported.
#' @return A `genui_component`.
#' @seealso [canvas_options()], [canvas_component_widget()]
#' @export
canvas_component_output <- function(name, description, args = list(), output,
                                    render, check = NULL,
                                    width = c("auto", "wide", "full"),
                                    data = TRUE, code = NULL) {
  .genui_check_builder(name, description, args, check, code)
  if (!is.function(output)) stop("`output` must be an output function.", call. = FALSE)
  if (!is.function(render)) stop("`render` must be a function(args, data).", call. = FALSE)
  width <- match.arg(width)
  out_fn <- output
  render_fn <- render
  comp <- shinygenui::genui_component(
    name = name, description = description, args = args,
    ui = function(id, args) out_fn(shiny::NS(id)("out")),
    server = function(id, args, data) {
      force(args)
      force(data)
      shiny::moduleServer(id, function(input, output, session) {
        output$out <- render_fn(args, data)
      })
    },
    check = check, width = width)
  comp$needs_data <- isTRUE(data)
  comp$code <- code
  comp
}

#' Build a canvas component from an htmlwidget or HTML
#'
#' `widget` returns any htmlwidget (plotly, leaflet, reactable, ...) or
#' htmltools tag; it is rendered with `shiny::renderUI()`, so no
#' widget-specific output function is needed.
#'
#' @inheritParams canvas_component_output
#' @param widget `function(args, data)` returning an htmlwidget or tag. `data`
#'   is the data frame the model named in `dataset` (or `NULL` when
#'   `data = FALSE`).
#' @return A `genui_component`.
#' @seealso [canvas_options()], [canvas_component_output()]
#' @export
canvas_component_widget <- function(name, description, args = list(), widget,
                                    check = NULL,
                                    width = c("wide", "auto", "full"),
                                    data = TRUE, code = NULL) {
  if (!is.function(widget)) stop("`widget` must be a function(args, data).", call. = FALSE)
  widget_fn <- widget
  canvas_component_output(
    name = name, description = description, args = args,
    output = shiny::uiOutput,
    render = function(args, data) shiny::renderUI(
      widget_fn(args, if (is.function(data)) data() else NULL)),
    check = check, width = match.arg(width), data = data, code = code)
}

.genui_check_builder <- function(name, description, args, check, code) {
  if (!is.character(name) || length(name) != 1L || !nzchar(name))
    stop("`name` must be a single string.", call. = FALSE)
  if (!is.character(description) || length(description) != 1L || !nzchar(description))
    stop("`description` must be a single string.", call. = FALSE)
  if (!is.list(args) || (length(args) && is.null(names(args))))
    stop("`args` must be a named list of ellmer types.", call. = FALSE)
  if (!is.null(check) && !is.function(check))
    stop("`check` must be NULL or a function(args, data).", call. = FALSE)
  if (!is.null(code) && !is.function(code))
    stop("`code` must be NULL or a function(args, dataset).", call. = FALSE)
  invisible(NULL)
}

# Names of the shinygenui components an options object keeps.
.genui_starter_names <- function(options) {
  s <- options$starter
  if (isTRUE(s)) .GENUI_ADMITTED else if (isFALSE(s)) character() else s
}

# Packages a canvas built from `options` needs: shinygenui always; ggplot2 and
# DT only when shinygenui's own starter components are offered.
#' @keywords internal
.genui_required_packages <- function(options = canvas_options()) {
  c("shinygenui", if (length(.genui_starter_names(options))) .GENUI_STARTER_DEPS)
}

#' @export
print.codeagent_canvas_options <- function(x, ...) {
  host <- vapply(x$components, function(c) as.character(c$name), character(1L))
  cat("<codeagent canvas options>\n")
  cat("  starter:   ", paste(.genui_starter_names(x), collapse = ", ") %||% "", "\n")
  cat("  host:      ", if (length(host)) paste(host, collapse = ", ") else "(none)", "\n")
  cat("  csp:       ", if (isTRUE(x$csp)) "default" else if (isFALSE(x$csp)) "off" else x$csp, "\n")
  cat("  validate_text:", x$validate_text, "\n")
  invisible(x)
}
