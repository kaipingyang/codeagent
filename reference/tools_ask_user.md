# AskUserQuestion Tool

Lets the LLM pause the agentic loop and ask the user a clarifying
question, waiting for their answer before continuing. Available in all
permission modes (read-only, no side effects).

  - **CLI path**: uses `readline()` (or
    `getOption("codeagent.test_ask_answer")` for tests/non-interactive
    fallback).

  - **Shiny path**: delegates to an injected `ask_question_fn` callback
    that shows an input bar and resolves asynchronously (Phase 3).
