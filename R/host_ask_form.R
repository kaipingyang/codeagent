# ---------------------------------------------------------------------------
# Forms asked by host tools
# ---------------------------------------------------------------------------
# AskUserForm is a tool the model calls with fields it chooses. A host tool
# that knows what to ask (e.g. "which arms go together", with the arms from
# the data) asks the same form itself, so the user always gets the right
# controls whatever the model would have picked. The form is the AskUserForm
# card: same field types, same queue, same "Answered" record in the chat.

#' Ask the user to fill in a form from a host tool
#'
#' Shows a form in the chat's interaction card (the one `AskUserForm` uses)
#' and waits for the user. Call it from a host tool passed to
#' [codeagent_server()] and return (a promise of) the tool's result from its
#' answer. Forms queue with the session's other questions and approvals.
#'
#' @param title Character(1). Heading of the form.
#' @param fields A list of fields, each a list with `name`, `label`, `type`
#'   (`"text"`, `"textarea"`, `"number"`, `"select"`, `"multiselect"`,
#'   `"checkbox"`, `"date"`, `"grouping"`), and optionally `choices`,
#'   `default`, `required` and `help` -- the `AskUserForm` field spec. A
#'   `grouping` field takes `choices` (e.g. treatment arms) and an optional
#'   `default` such as `"Mono: a, b; Combo: c"`; its value is
#'   `list(group = choices)`.
#' @param submit_label Character(1). Label of the submit button.
#' @param session The Shiny session running [codeagent_server()]; defaults to
#'   the current one.
#' @return A promise of `list(submitted = TRUE/FALSE, values = list(name =
#'   value))`; `values` is empty when the user cancelled. Without a session
#'   running [codeagent_server()] the form is answered from
#'   `getOption("codeagent.test_form_answer")` (tests), on the console when
#'   interactive, or cancelled -- and the list is returned directly.
#' @seealso [codeagent_server()], [ask_user_form_tool()]
#' @export
codeagent_ask_form <- function(title, fields, submit_label = "Submit",
                               session = shiny::getDefaultReactiveDomain()) {
  spec <- .form_validate_fields(fields)
  if (is.character(spec)) stop(spec, call. = FALSE)
  title <- as.character(title %||% "")[1]
  fn <- if (!is.null(session)) tryCatch(session$userData$codeagent_ask_form_fn, error = function(e) NULL)
  ans <- .ask_form_impl(title, spec, submit_label %||% "Submit", fn)
  if (inherits(ans, "promise")) promises::then(ans, .host_form_answer) else .host_form_answer(ans)
}

.host_form_answer <- function(answer) {
  submitted <- isTRUE(answer$submitted)
  list(submitted = submitted, values = if (submitted) answer$values %||% list() else list())
}
