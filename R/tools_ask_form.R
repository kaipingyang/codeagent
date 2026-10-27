#' @title AskUserForm Tool
#' @description Lets the LLM pause the agentic loop and ask the user to fill in
#'   or confirm a small structured form (text, number, choice, multi-choice,
#'   checkbox, date fields) before continuing. Where `AskUserQuestion` asks one
#'   question, a form collects several values at once -- e.g. confirming the
#'   parameters of an action before the agent runs it.
#'
#'   - **Shiny path**: an injected `ask_form_fn` shows the form in the chat's
#'     interaction area (above the input) and resolves when the user submits
#'     or cancels.
#'   - **CLI path**: asks field by field with `readline()`;
#'     `getOption("codeagent.test_form_answer")` (a named list, or `FALSE` to
#'     cancel) answers without prompting, for tests.
#' @name tools_ask_form
#' @keywords internal
NULL

.FORM_FIELD_TYPES <- c("text", "textarea", "number", "select", "multiselect",
                       "checkbox", "date")
.FORM_MAX_FIELDS <- 20L

#' Create the AskUserForm tool
#'
#' @param ask_form_fn Function or NULL. If provided, called with
#'   `(title, fields, submit_label)` and returns (a promise of) a list with
#'   `submitted` (logical) and `values` (named list). Used by the Shiny UI.
#' @param async Logical. Build the `coro::async` variant that awaits the
#'   promise from `ask_form_fn` (Shiny, `stream_async()`); `FALSE` for the
#'   synchronous CLI path.
#' @return An `ellmer::ToolDef`.
#' @seealso [ask_user_tool()]
#' @export
ask_user_form_tool <- function(ask_form_fn = NULL, async = FALSE) {
  force(ask_form_fn)
  force(async)

  fun <- if (isTRUE(async)) {
    # coro cannot assign the result of an `if` expression: branch with
    # side-effecting assignments.
    coro::async(function(title, fields, submit_label = "Submit", `_intent` = NULL) {
      spec <- .form_validate_fields(fields)
      if (is.character(spec)) return(.form_spec_error(spec))
      ans <- .ask_form_impl(title, spec, submit_label, ask_form_fn)
      if (inherits(ans, "promise")) {
        answer <- await(ans)
      } else {
        answer <- ans
      }
      .form_tool_result(answer, title, spec)
    })
  } else {
    function(title, fields, submit_label = "Submit", `_intent` = NULL) {
      spec <- .form_validate_fields(fields)
      if (is.character(spec)) return(.form_spec_error(spec))
      .form_tool_result(.ask_form_impl(title, spec, submit_label, ask_form_fn),
                        title, spec)
    }
  }

  ellmer::tool(
    name = "AskUserForm",
    fun  = fun,
    description = paste0(
      "Show the user a small form and wait for them to submit or cancel it. ",
      "Use it to collect or confirm several related values at once before ",
      "acting (e.g. the parameters of an analysis, a set of options to apply). ",
      "Pre-fill `default` with your best guess so the user mostly confirms. ",
      "For a single question use AskUserQuestion instead. Do NOT use it for ",
      "permission requests -- those are handled automatically. The result is ",
      "JSON: {\"submitted\": true|false, \"values\": {name: value}}; if ",
      "submitted is false the user cancelled, so do not proceed with the action."
    ),
    arguments = list(
      title = ellmer::type_string(
        "Short heading shown above the form.", required = TRUE),
      fields = ellmer::type_array(
        paste0("Form fields, at most ", .FORM_MAX_FIELDS, "."),
        items = ellmer::type_object(
          name     = ellmer::type_string(
            "Machine name of the field (letters, digits, underscore); the key in the result."),
          label    = ellmer::type_string("Label shown to the user.", required = FALSE),
          type     = ellmer::type_enum(
            values = .FORM_FIELD_TYPES,
            description = "Input type. select/multiselect need `choices`."),
          choices  = ellmer::type_array(
            "Options for select / multiselect.",
            items = ellmer::type_string(), required = FALSE),
          default  = ellmer::type_string(
            paste0("Pre-filled value as text. multiselect: comma-separated; ",
                   "checkbox: \"true\"/\"false\"; date: YYYY-MM-DD."),
            required = FALSE),
          required = ellmer::type_boolean(
            "Whether the user must fill it in.", required = FALSE),
          help     = ellmer::type_string("Short hint under the field.", required = FALSE)
        ),
        required = TRUE),
      submit_label = ellmer::type_string(
        "Text of the submit button (default \"Submit\").", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of why the form is needed.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "AskUserForm",
      read_only_hint = TRUE
    )
  )
}

#' Register the AskUserForm tool on a Chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param ask_form_fn Function or NULL. Shiny callback (see [ask_user_form_tool()]).
#' @param async Logical. Build the async (promise-awaiting) variant (Shiny).
#' @return Invisibly `chat`.
#' @export
register_ask_user_form_tool <- function(chat, ask_form_fn = NULL, async = FALSE) {
  chat$register_tool(ask_user_form_tool(ask_form_fn, async = async))
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Field specification
# ---------------------------------------------------------------------------

# One scalar from a model-supplied field attribute, or `default` when it is
# absent. ellmer delivers an array of objects as a tibble, where an omitted
# optional attribute is NA (not NULL), so NA counts as absent too. PURE.
.form_scalar <- function(x, default) {
  x <- unlist(x, use.names = FALSE)
  if (!length(x) || is.na(x[1L])) return(default)
  x[1L]
}

# Normalise the model-supplied fields into a list of complete field specs, or
# return a character error message the model can act on. PURE.
.form_validate_fields <- function(fields) {
  if (is.data.frame(fields)) fields <- split(fields, seq_len(nrow(fields)))
  if (!is.list(fields) || !length(fields)) return("`fields` must be a non-empty list of field objects.")
  if (length(fields) > .FORM_MAX_FIELDS)
    return(sprintf("A form can have at most %d fields.", .FORM_MAX_FIELDS))
  out <- vector("list", length(fields))
  for (i in seq_along(fields)) {
    f <- as.list(fields[[i]])
    name <- as.character(.form_scalar(f$name, ""))
    if (is.na(name) || !grepl("^[A-Za-z][A-Za-z0-9_]{0,63}$", name))
      return(sprintf("Field %d: `name` must start with a letter and use letters, digits or underscores.", i))
    type <- as.character(.form_scalar(f$type, "text"))
    if (!type %in% .FORM_FIELD_TYPES)
      return(sprintf("Field `%s`: unknown type \"%s\" (use one of %s).", name, type,
                     paste(.FORM_FIELD_TYPES, collapse = ", ")))
    choices <- as.character(unlist(f$choices %||% character(0), use.names = FALSE))
    choices <- choices[!is.na(choices)]
    if (type %in% c("select", "multiselect") && !length(choices))
      return(sprintf("Field `%s`: type \"%s\" needs `choices`.", name, type))
    default <- unlist(f$default, use.names = FALSE)
    default <- default[!is.na(default)]
    default <- if (!length(default)) "" else paste(as.character(default), collapse = ",")
    out[[i]] <- list(
      name     = name,
      label    = as.character(.form_scalar(f$label, name)),
      type     = type,
      choices  = choices,
      default  = default,
      required = isTRUE(as.logical(.form_scalar(f$required, FALSE))),
      help     = as.character(.form_scalar(f$help, ""))
    )
  }
  names_ <- vapply(out, `[[`, character(1L), "name")
  if (anyDuplicated(names_))
    return(sprintf("Field names must be unique (repeated: %s).",
                   paste(unique(names_[duplicated(names_)]), collapse = ", ")))
  out
}

# Coerce one raw submitted value to the field's type. PURE.
.form_coerce <- function(field, raw) {
  switch(field$type,
    number = {
      v <- suppressWarnings(as.numeric(raw %||% NA))
      if (length(v) && !is.na(v[1])) v[1] else NULL
    },
    checkbox = isTRUE(as.logical(raw %||% FALSE)),
    multiselect = {
      v <- as.character(unlist(raw %||% character(0)))
      if (length(v) == 1L && grepl(",", v)) v <- trimws(strsplit(v, ",", fixed = TRUE)[[1]])
      v[nzchar(v)]
    },
    date = {
      v <- as.character(unlist(raw %||% ""))[1]
      if (is.na(v) || !nzchar(v)) NULL else v
    },
    {
      v <- as.character(unlist(raw %||% ""))[1]
      if (is.na(v)) "" else v
    }
  )
}

.form_is_empty <- function(field, value) {
  if (identical(field$type, "checkbox")) return(FALSE)
  is.null(value) || !length(value) || (is.character(value) && !any(nzchar(value)))
}

# Coerce a raw named list of submitted values and check required fields.
# Returns list(values=, missing=) where `missing` names unfilled required
# fields. PURE.
.form_collect <- function(spec, raw) {
  values <- list()
  missing <- character(0)
  for (f in spec) {
    v <- .form_coerce(f, raw[[f$name]])
    if (isTRUE(f$required) && .form_is_empty(f, v)) missing <- c(missing, f$label)
    values[f$name] <- list(v)
  }
  list(values = values, missing = missing)
}

# ---------------------------------------------------------------------------
# CLI / test path
# ---------------------------------------------------------------------------

.ask_form_impl <- function(title, spec, submit_label, ask_form_fn) {
  if (is.function(ask_form_fn))
    return(tryCatch(ask_form_fn(title, spec, submit_label),
                    error = function(e) list(submitted = FALSE)))
  test_ans <- getOption("codeagent.test_form_answer", default = NULL)
  if (isFALSE(test_ans)) return(list(submitted = FALSE))
  if (is.list(test_ans))
    return(list(submitted = TRUE, values = .form_collect(spec, test_ans)$values))
  if (!interactive()) {
    cli::cli_alert_warning(
      "AskUserForm called in non-interactive session. Returning a cancelled form.")
    return(list(submitted = FALSE))
  }
  cli::cli_text("{.strong {title}}")
  raw <- list()
  for (f in spec) {
    hint <- if (length(f$choices)) paste0(" [", paste(f$choices, collapse = " / "), "]") else ""
    def  <- if (nzchar(f$default)) paste0(" (", f$default, ")") else ""
    ans  <- trimws(readline(paste0(f$label, hint, def, ": ")))
    raw[[f$name]] <- if (nzchar(ans)) ans else f$default
  }
  list(submitted = TRUE, values = .form_collect(spec, raw)$values)
}

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

.form_spec_error <- function(message) {
  .artifact_tool_result(
    paste0("[AskUserForm] ", message),
    kind = "error", status = "error", icon = "exclamation-triangle",
    title = "AskUserForm -- invalid form", payload = list(message = message))
}

.form_tool_result <- function(answer, title, spec) {
  submitted <- isTRUE(answer$submitted)
  values <- if (submitted) answer$values %||% list() else list()
  text <- as.character(jsonlite::toJSON(
    list(submitted = submitted, values = values),
    auto_unbox = TRUE, null = "null", na = "null"))
  shown <- if (!submitted) "(cancelled)" else paste(vapply(spec, function(f) {
    v <- values[[f$name]]
    paste0(f$label, ": ", if (is.null(v)) "" else paste(v, collapse = ", "))
  }, character(1L)), collapse = "\n")
  .artifact_tool_result(
    text,
    kind    = "text",
    icon    = "clipboard-check",
    title   = htmltools::HTML(sprintf(
      "<code>AskUserForm</code> -- %s%s",
      htmltools::htmlEscape(substr(title %||% "", 1L, 80L)),
      if (submitted) "" else " (cancelled)")),
    payload = list(text = shown))
}
