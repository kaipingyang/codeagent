# Repository Guidelines

`codeagent` is an R package that reimplements an agentic coding harness (agent loop,
permissions, compaction, hooks, skills, tools, sessions, Shiny UI) on top of `ellmer`
and `btw`. It does **not** wrap an external CLI — the harness is reimplemented in R.

> **Read `CLAUDE.md` first** before touching any core subsystem. It holds the detailed
> architecture, data-flow diagram, subsystem map, and design decisions. This file is the
> shorter day-to-day contributor guide; `CLAUDE.md` is the deep reference.

## Project Structure & Module Organization
- `R/`: package source — agent loop, tools, sessions, permissions, and Shiny server/UI modules.
- `tests/testthat/`: unit and integration tests; entrypoint is `tests/testthat.R`.
- `inst/examples/`: runnable examples and demos; update these when public behavior changes.
- `inst/skills/`: built-in skills (`name/SKILL.md` format).
- `references/`: exploratory scripts and provider-specific experiments (e.g. Databricks, thinking demos).
- `exec/`: CLI entrypoints such as `exec/codeagent.R`.
- `man/`, `NAMESPACE`: generated documentation; refresh via roxygen.

## Build, Test, and Development Commands
- `devtools::load_all()`: load the package for interactive development.
- `devtools::document()`: regenerate `man/` files and `NAMESPACE`.
- `devtools::test()`: run the full test suite.
- `testthat::test_file("tests/testthat/test-permissions.R")`: run one focused test file.
- `devtools::check()`: run full package checks; target zero errors and warnings.
- `Rscript -e 'codeagent::codeagent_app(client)'`: launch the Shiny app once a `client` is configured.

## Security (hard rule): never upload or print secrets
Real API keys/tokens/passwords and concrete infrastructure endpoints (real
`base_url` values, Databricks/serving-endpoint hosts, workspace IDs/hosts like
`adb-<id>.azuredatabricks.net`, internal hostnames/IPs) must **never** appear in
git-tracked files (source, tests, examples, docs, templates). Use placeholders
(`YOUR-WORKSPACE.cloud.databricks.net`, `sk-...`, `<workspace-id>`); keep real
values only in `.Renviron`/keyring (git-ignored). Scan the staged diff before
committing (`git diff --cached | grep -iE 'api[_-]?key|token|secret|sk-|ghp_|dapi|azuredatabricks\.net|serving-endpoints'`),
mask tokens in printed remote URLs (`sed -E 's#//[^@]*@#//***@#g'`), and never
echo a full token/key. If a secret was committed, rotate it first, then purge
with `git filter-repo`. See the `no-secrets` skill.

## Coding Style & Naming Conventions
Use the existing base-R style in `R/`: small focused functions, descriptive snake_case names,
and minimal diffs. Match surrounding indentation and spacing exactly. Keep public APIs stable
unless the change requires it. When modifying exported functions, update roxygen comments and
regenerate docs.

**Non-ASCII:** R CMD check rejects non-ASCII characters in R source. Use `\uXXXX` escapes only
inside string literals — never in roxygen `#'` comments.

**Tool functions use the closure-factory pattern:** external resources (connection, checker)
are captured via the factory function. See `CLAUDE.md` → Development Rules for the template and
`R/tool_run_sql.R`-style reference.

**Async (`coro::async`) rules:** never `x <- if (...)` inside a coro body — coro can't assign
the result of an `if` (assign inside branches, or compute before the async body); avoid bare
`!!!` (use `do.call()`); and `coro::async()` needs a *literal* anonymous function (can't wrap a
built function — return a `promises::then()` promise from a plain function instead). See
`lessons/2026-07-03-shiny-async-interaction.md`.

**Compaction — turn-boundary + mid-loop (two-tier):** compaction runs before each
`chat$chat()`. Between tool rounds (ellmer's released `on_tool_result`,
`register_midloop_compaction()`), a **budget-aware micro snip** runs by default
(`settings$midloop_compact`, ON) and an **opt-in full two-level compact**
(`settings$midloop_full_compact`, OFF) escalates when snip isn't enough. Cleaner
target: upstream `on_turn_start` (fires before *every* request; `on_tool_request`
can't substitute — it fires after the request, per-tool). See
`references/plan/13-mid-loop-compaction.md` (PR tidyverse/ellmer#1052).

**Env vars:** prefer `CODEAGENT_*` (`CODEAGENT_BASE_URL`, `CODEAGENT_MODEL`,
`CODEAGENT_API_KEY`) over `OPENAI_*` names. Keep provider-specific experiments in `references/`
unless they are part of the supported package API.

## Testing Guidelines
Tests use `testthat`. Place tests in `tests/testthat/test-*.R` and group by subsystem
(e.g. `test-permissions.R`). Any change to public APIs, tools, or examples should include or
update tests covering both the main path and any fallback/degraded path. Prefer targeted tests
first, then broader runs with `devtools::test()`.

> **测试无误 = 要装到本地才算数。** `devtools::load_all()` 只在当前 R session 生效；CLI/launcher
> (`--vanilla`) 和真实验证跑的是**已安装**的包。改完代码、跑完测试后，务必用
> `pak::local_install(".", ask = FALSE, upgrade = FALSE)` 把**当前版本装到本地**，否则你验的不是最新代码。

## Keep-in-Sync Rules (do this on every code change)
1. **Rebuild the installed package** after code changes — launcher/CLI entry points run the
   installed package, not `load_all()`:
   ```r
   pak::local_install(".", ask = FALSE, upgrade = FALSE)
   ```
   Then `codegraph sync` to refresh the symbol index for AI/code-review tooling.
2. **Update `README.md`** — new exported functions/features get a line in the matching section;
   important behavior changes update the relevant description.
3. **Update tests and examples** — new/changed functions get `tests/testthat/test-*.R` coverage;
   public-API changes update `inst/examples/demo_*.R` / `test_databricks.R`.
4. **Wire new exported tools** — confirm whether they need registering in `.register_all_tools()`
   and its call chain.

## Commit & Pull Request Guidelines
Use Conventional Commit prefixes (`feat:`, `refactor:`, `docs:`). Keep commit subjects short and
scoped, e.g. `feat: add Databricks thinking example`. PRs should explain the user-visible change,
list affected paths, mention test coverage, and include screenshots for Shiny UI updates.

## Shiny UI Rules
Reference docs live in `.claude/docs/` (project) — read before changing a subsystem.
- **Layout:** before changing chat/sidebar layout, read `bslib-shinychat-layout.md`. Treat
  `shinychat::chat_ui(fill = TRUE)` as fill-sensitive — it must live inside a truly fillable
  parent (e.g. `bslib::sidebar(fillable = TRUE, ...)`); extra wrappers/CSS often break
  sticky-bottom input behavior.
- **Components:** prefer `bslib::toolbar()` for horizontal action groups and
  `bslib::show_toast()` over `shiny::showNotification()` for user-facing notifications. Read
  `bslib-toolbar-toast.md` and `bslib-toast-vs-notification.md` before adding action bars or
  notifications.
- **State:** consolidate shared session state into a single `shiny::reactiveValues()` container
  (see `ui.R` `state <- reactiveValues(...)`); do not scatter standalone `reactiveVal()` objects.
- **Slash-command grouping:** when mimicking `shinyAssistantUI`, use the canonical 6 sections —
  `Context`, `Model`, `Customize`, `Slash Commands`, `Settings`, `Support`. Do not invent
  replacement group labels unless the user requests a different taxonomy.
