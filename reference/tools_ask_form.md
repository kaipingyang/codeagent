# AskUserForm Tool

Lets the LLM pause the agentic loop and ask the user to fill in or
confirm a small structured form (text, number, choice, multi-choice,
checkbox, date fields) before continuing. Where `AskUserQuestion` asks
one question, a form collects several values at once – e.g. confirming
the parameters of an action before the agent runs it.

- **Shiny path**: an injected `ask_form_fn` shows the form in the chat's
  interaction area (above the input) and resolves when the user submits
  or cancels.

- **CLI path**: asks field by field with
  [`readline()`](https://rdrr.io/r/base/readline.html);
  `getOption("codeagent.test_form_answer")` (a named list, or `FALSE` to
  cancel) answers without prompting, for tests.
