# Ask the user to fill in a form from a host tool

Shows a form in the chat's interaction card (the one `AskUserForm` uses)
and waits for the user. Call it from a host tool passed to
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
and return (a promise of) the tool's result from its answer. Forms queue
with the session's other questions and approvals.

## Usage

``` r
codeagent_ask_form(
  title,
  fields,
  submit_label = "Submit",
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- title:

  Character(1). Heading of the form.

- fields:

  A list of fields, each a list with `name`, `label`, `type` (`"text"`,
  `"textarea"`, `"number"`, `"select"`, `"multiselect"`, `"checkbox"`,
  `"date"`, `"grouping"`), and optionally `choices`, `default`,
  `required` and `help` – the `AskUserForm` field spec. A `grouping`
  field takes `choices` (e.g. treatment arms) and an optional `default`
  such as `"Mono: a, b; Combo: c"`; its value is
  `list(group = choices)`.

- submit_label:

  Character(1). Label of the submit button.

- session:

  The Shiny session running
  [`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md);
  defaults to the current one.

## Value

A promise of
`list(submitted = TRUE/FALSE, values = list(name = value))`; `values` is
empty when the user cancelled. Without a session running
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
the form is answered from `getOption("codeagent.test_form_answer")`
(tests), on the console when interactive, or cancelled – and the list is
returned directly.

## See also

[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md),
[`ask_user_form_tool()`](https://kaipingyang.github.io/codeagent/reference/ask_user_form_tool.md)
