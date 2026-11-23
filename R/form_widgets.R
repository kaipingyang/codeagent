#' @title AskUserForm widgets
#' @description How each AskUserForm field type is drawn. The model only names
#'   the type (`select`, `date`, ...); the host picks the widget with
#'   `form_widgets =` on [codeagent_app()] / [codeagent_server()]. A widget is
#'   `function(id, label, value, choices, field)` returning UI whose value comes
#'   back as `input[[id]]` in the shape the native Shiny control gives, so
#'   collection and validation (`.form_collect()`) do not depend on it.
#' @name form_widgets
#' @keywords internal
NULL

.FORM_WIDGET_TYPES <- c("text", "textarea", "number", "select", "multiselect",
                        "checkbox", "date")

# A field's default as the value its widget starts with. PURE.
.form_default_value <- function(field) {
  def <- field$default %||% ""
  switch(field$type,
    number      = { v <- suppressWarnings(as.numeric(def)); if (length(v) && !is.na(v)) v else NULL },
    checkbox    = isTRUE(as.logical(def)),
    multiselect = if (nzchar(def)) trimws(strsplit(def, ",", fixed = TRUE)[[1]]) else character(0),
    select      = if (nzchar(def)) def else if (length(field$choices)) field$choices[[1]] else NULL,
    date        = if (nzchar(def)) def else NULL,
    def)
}

.form_ph <- function(field) if (nzchar(field$placeholder %||% "")) field$placeholder else NULL

# ---- presets ------------------------------------------------------------------

.form_preset_native <- function() list(
  text = function(id, label, value, choices, field)
    shiny::textInput(id, label, value = value, width = "100%", placeholder = .form_ph(field)),
  textarea = function(id, label, value, choices, field)
    shiny::textAreaInput(id, label, value = value, width = "100%", rows = 3,
                         placeholder = .form_ph(field)),
  number = function(id, label, value, choices, field)
    shiny::numericInput(id, label, value = value, width = "100%",
                        min = field$min %||% NA, max = field$max %||% NA, step = field$step %||% NA),
  select = function(id, label, value, choices, field)
    if (isTRUE(field$allow_other))
      shiny::selectizeInput(id, label, choices = choices, selected = value, width = "100%",
                            options = list(create = TRUE))
    else shiny::selectInput(id, label, choices = choices, selected = value, width = "100%"),
  multiselect = function(id, label, value, choices, field)
    if (isTRUE(field$allow_other))
      shiny::selectizeInput(id, label, choices = choices, selected = value, multiple = TRUE,
                            width = "100%", options = list(create = TRUE))
    else shiny::selectInput(id, label, choices = choices, selected = value, multiple = TRUE,
                            width = "100%"),
  checkbox = function(id, label, value, choices, field)
    shiny::checkboxInput(id, label, value = isTRUE(value)),
  date = function(id, label, value, choices, field)
    shiny::dateInput(id, label, value = value, width = "100%"))

# shinyWidgets: searchable pickers, a switch, an air datepicker. Values come
# back as the native controls' do (picker: character, switch: logical,
# airDatepicker: Date).
.form_preset_shinyWidgets <- function() {
  sw <- function(f) getExportedValue("shinyWidgets", f)
  list(
    select = function(id, label, value, choices, field) {
      if (isTRUE(field$allow_other)) return(.form_preset_native()$select(id, label, value, choices, field))
      sw("pickerInput")(id, label, choices = choices, selected = value, width = "100%",
                        options = list(`live-search` = length(choices) > 7))
    },
    multiselect = function(id, label, value, choices, field) {
      if (isTRUE(field$allow_other)) return(.form_preset_native()$multiselect(id, label, value, choices, field))
      sw("pickerInput")(id, label, choices = choices, selected = value, multiple = TRUE,
                        width = "100%", options = list(`actions-box` = TRUE,
                                                       `live-search` = length(choices) > 7))
    },
    checkbox = function(id, label, value, choices, field)
      sw("prettySwitch")(id, label, value = isTRUE(value), status = "primary", fill = TRUE),
    date = function(id, label, value, choices, field)
      sw("airDatepickerInput")(id, label, value = value, width = "100%", autoClose = TRUE,
                               dateFormat = "yyyy-MM-dd"))
}

# shiny.element: compact Element Plus inputs, each with its own label (the
# standalone inputs, not el_form(): see .claude/specs/form-widgets.md).
.form_preset_shiny.element <- function() {
  el <- function(f) getExportedValue("shiny.element", f)
  lab <- function(label, x) htmltools::tags$div(class = "ca-form-el mb-2",
    htmltools::tags$label(class = "form-label ca-form-el-label", label), x)
  list(
    text = function(id, label, value, choices, field)
      lab(label, el("el_input")(id, value = value, placeholder = .form_ph(field), clearable = TRUE)),
    textarea = function(id, label, value, choices, field)
      lab(label, el("el_input")(id, value = value, type = "textarea", rows = 3,
                                placeholder = .form_ph(field))),
    number = function(id, label, value, choices, field) {
      args <- list(id, value = value %||% 0)
      if (!is.null(field$min)) args$min <- field$min
      if (!is.null(field$max)) args$max <- field$max
      if (!is.null(field$step)) args$step <- field$step
      lab(label, do.call(el("el_input_number"), args))
    },
    select = function(id, label, value, choices, field)
      lab(label, el("el_select")(id, choices = choices, selected = value,
                                 filterable = TRUE, allow_create = isTRUE(field$allow_other),
                                 width = "100%")),
    multiselect = function(id, label, value, choices, field)
      lab(label, el("el_select")(id, choices = choices, selected = value, multiple = TRUE,
                                 filterable = TRUE, allow_create = isTRUE(field$allow_other),
                                 width = "100%")),
    checkbox = function(id, label, value, choices, field)
      lab(label, el("el_switch")(id, value = isTRUE(value))),
    date = function(id, label, value, choices, field)
      lab(label, el("el_date_picker")(id, value = value, value_format = "YYYY-MM-DD",
                                      width = "100%")))
}

.FORM_PRESETS <- list(
  native = list(package = NULL, make = .form_preset_native),
  shinyWidgets = list(package = "shinyWidgets", make = .form_preset_shinyWidgets),
  shiny.element = list(package = "shiny.element", make = .form_preset_shiny.element))

# ---- resolution -----------------------------------------------------------------

# `form_widgets` -> one widget function per field type. Entries without a name
# are presets (a built-in name, or a named list of type -> function), tried in
# order; named entries override one type (a function, or a built-in preset's
# name). Errors on an unknown preset or type; a preset whose package is not
# installed is skipped with one warning. Native Shiny fills what is left.
.form_widgets_resolve <- function(form_widgets = NULL) {
  out <- .form_preset_native()
  if (is.null(form_widgets)) return(out)
  if (is.character(form_widgets)) form_widgets <- as.list(form_widgets)
  if (!is.list(form_widgets))
    stop("`form_widgets` must be NULL, preset names, or a list of presets and ",
         "per-type widgets.", call. = FALSE)
  nm <- names(form_widgets) %||% rep("", length(form_widgets))
  check_type <- function(t) if (!t %in% .FORM_WIDGET_TYPES)
    stop(sprintf("`form_widgets`: unknown field type \"%s\" (use %s).", t,
                 paste(.FORM_WIDGET_TYPES, collapse = ", ")), call. = FALSE)
  preset <- function(x) {
    if (is.character(x) && length(x) == 1L) {
      p <- .FORM_PRESETS[[x]]
      if (is.null(p))
        stop(sprintf("`form_widgets`: no preset \"%s\" (built in: %s). Pass a list of ",
                     x, paste(names(.FORM_PRESETS), collapse = ", ")),
             "type -> function for another package.", call. = FALSE)
      if (!is.null(p$package) && !requireNamespace(p$package, quietly = TRUE)) {
        warning(sprintf("[codeagent] form_widgets: package '%s' is not installed; its fields use the next choice.",
                        p$package), call. = FALSE)
        return(list())
      }
      return(p$make())
    }
    if (is.list(x) && !is.null(names(x)) && all(nzchar(names(x)))) {
      for (t in names(x)) {
        check_type(t)
        if (!is.function(x[[t]]))
          stop(sprintf("`form_widgets`: the widget for \"%s\" must be a function.", t), call. = FALSE)
      }
      return(x)
    }
    stop("`form_widgets`: an unnamed entry must be a preset name or a named list ",
         "of type -> function.", call. = FALSE)
  }
  chosen <- list()
  # per-type overrides first, then presets in order
  for (i in which(nzchar(nm))) {
    check_type(nm[[i]])
    w <- form_widgets[[i]]
    if (is.character(w)) w <- preset(w)[[nm[[i]]]]
    else if (!is.function(w))
      stop(sprintf("`form_widgets`: the widget for \"%s\" must be a function or a preset name.",
                   nm[[i]]), call. = FALSE)
    if (is.function(w)) chosen[[nm[[i]]]] <- w
  }
  for (i in which(!nzchar(nm))) {
    p <- preset(form_widgets[[i]])
    for (t in setdiff(names(p), names(chosen))) chosen[[t]] <- p[[t]]
  }
  for (t in names(chosen)) out[[t]] <- chosen[[t]]
  out
}

# ---- one field -------------------------------------------------------------------

.form_field_input <- function(field, i, widgets = .form_preset_native()) {
  id <- .form_input_id(i)
  label <- if (isTRUE(field$required)) paste0(field$label, " *") else field$label
  input <- if (identical(field$type, "grouping")) {
    .grouping_ui(id, label, field$choices, field$default)
  } else {
    w <- widgets[[field$type]] %||% .form_preset_native()[[field$type]]
    w(id, label, .form_default_value(field), field$choices, field)
  }
  htmltools::tagList(
    input,
    if (nzchar(field$help %||% ""))
      htmltools::tags$small(class = "form-text text-muted d-block mb-2", field$help))
}

# Wide types always take a whole row; short ones share rows with as many
# columns as the card's width allows (a CSS grid, inst/www/styles.css).
.FORM_WIDE_TYPES <- c("textarea", "multiselect", "grouping")

# All fields: each section is a heading plus an auto-fitting grid of its
# fields. The width is the page's business, the grouping the model's.
.form_fields_ui <- function(fields, widgets = .form_preset_native()) {
  if (!length(fields)) return(NULL)
  sec <- vapply(fields, function(f) f$section %||% "", "")
  runs <- cumsum(c(TRUE, sec[-1] != sec[-length(sec)]))
  htmltools::tagList(lapply(unique(runs), function(r) {
    idx <- which(runs == r)
    htmltools::tagList(
      if (nzchar(sec[idx[1]])) htmltools::tags$div(class = "ca-form-section", sec[idx[1]]),
      htmltools::tags$div(class = "ca-form-grid", lapply(idx, function(i) {
        f <- fields[[i]]
        wide <- identical(f$width, "full") || f$type %in% .FORM_WIDE_TYPES
        htmltools::tags$div(class = paste("ca-form-cell", if (wide) "ca-form-cell--wide"),
                            `data-type` = f$type, `data-i` = i, .form_field_input(f, i, widgets))
      })))
  }))
}

# A refused submit, shown in the form by inst/www/interaction.js.
.send_form_feedback <- function(session, msg)
  tryCatch(session$sendCustomMessage("ca_form_feedback", msg), error = function(e) NULL)
