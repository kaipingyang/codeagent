# Repository Guidelines

## Project Structure & Module Organization
`codeagent` is an R package that reimplements an agentic coding harness on top of `ellmer` and `btw`.
- `R/`: package source, including agent loop, tools, sessions, permissions, and Shiny server/UI modules.
- `tests/testthat/`: unit and integration tests; test entrypoint is `tests/testthat.R`.
- `inst/examples/`: runnable examples and demos; update these when public behavior changes.
- `references/`: exploratory scripts and provider-specific experiments (for example Databricks and thinking demos).
- `man/`, `NAMESPACE`: generated documentation; refresh via roxygen.
- `exec/`: CLI entrypoints such as `exec/codeagent.R`.

## Build, Test, and Development Commands
- `devtools::document()`: regenerate `man/` files and `NAMESPACE`.
- `devtools::test()`: run the full test suite.
- `testthat::test_file("tests/testthat/test-permissions.R")`: run one focused test file.
- `devtools::check()`: run full package checks; target zero errors and warnings.
- `devtools::load_all()`: load the package for interactive development.
- `Rscript -e 'codeagent::codeagent_app(client)'`: launch the Shiny app once a `client` is configured.

## Coding Style & Naming Conventions
Use the existing base-R style in `R/`: small focused functions, descriptive snake_case names, and minimal diffs. Match surrounding indentation and spacing exactly. Keep public APIs stable unless the change requires it. Avoid non-ASCII characters in R source except escaped string literals. When modifying exported functions, update roxygen comments and regenerate docs.

## Testing Guidelines
Tests use `testthat`. Place tests in `tests/testthat/test-*.R` and group by subsystem, such as `test-permissions.R`. Any change to public APIs, tools, or examples should include or update tests. Prefer targeted tests first, then broader runs with `devtools::test()`.

## Commit & Pull Request Guidelines
Recent history favors Conventional Commit prefixes like `feat:`, `refactor:`, and `docs:`. Keep commit subjects short and scoped, for example `feat: add Databricks thinking example`. PRs should explain the user-visible change, list affected paths, mention test coverage, and include screenshots for Shiny UI updates.

## Agent-Specific Instructions
Read `CLAUDE.md` before touching core subsystems. If you change code, also update the relevant tests and examples. Prefer `CODEAGENT_*` environment variables over `OPENAI_*` names, and keep provider-specific experiments in `references/` unless they are part of the supported package API.

Before changing Shiny chat/sidebar layout, read `~/.claude/docs/bslib-shinychat-layout.md`. Treat `shinychat::chat_ui(fill = TRUE)` as fill-sensitive: verify the parent is truly fillable before adding wrappers or CSS.

Prefer `bslib::toolbar()` for horizontal action groups and `bslib::show_toast()` for user-facing notifications. Before adding ad-hoc button rows or notification UI, read `~/.claude/docs/bslib-toolbar-toast.md` and `~/.claude/docs/bslib-toast-vs-notification.md`.

When mimicking `shinyAssistantUI` slash-command groupings, use the canonical 6 sections from its examples/source: `Context`, `Model`, `Customize`, `Slash Commands`, `Settings`, `Support`. Do not invent replacement group labels unless the user requests a different taxonomy.
