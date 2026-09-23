# Create a codeagent client from any ellmer Chat

Injects codeagent tools (Bash, Read, Write, Edit, Glob, Grep, LS, btw
tools, skill tool) and rebuilds the system prompt. The returned
`CodeagentClient` is the single object passed to
[`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
and
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md).

## Usage

``` r
codeagent_client(
  chat = NULL,
  permission_mode = "default",
  rules = list(),
  cwd = getwd(),
  max_turns = 100L,
  btw_groups = NULL,
  worktree_isolation = FALSE,
  verify_fn = NULL,
  mcp_config = NULL,
  register_tools = TRUE,
  data_shield = NULL,
  max_budget_usd = NULL,
  tools = NULL,
  disallowed_tools = NULL
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object – any backend supported by ellmer: `chat_openai_compatible()`,
  `chat_anthropic()`, `chat_ollama()`, etc. If NULL, a chat is
  auto-built from `CODEAGENT_BASE_URL`/`CODEAGENT_MODEL` env vars (or
  Anthropic defaults).

- permission_mode:

  Character. One of
  [PermissionMode](https://kaipingyang.github.io/codeagent/reference/PermissionMode.md).

- rules:

  List of
  [`PermissionRule()`](https://kaipingyang.github.io/codeagent/reference/PermissionRule.md)
  objects.

- cwd:

  Character. Working directory (used for CLAUDE.md, skills, sessions).

- max_turns:

  Integer. Maximum agentic loop turns.

- btw_groups:

  Character vector or NULL. Superseded by `tools`: btw group names are
  ordinary `tools` entries. Still honoured on its own (NULL = all
  available groups), but supplying both `tools` and `btw_groups` is an
  error.

- worktree_isolation:

  Logical. Run sub-agents in isolated git worktrees.

- verify_fn:

  Function or NULL. Optional output verifier; re-enters the loop when it
  reports failures (e.g.
  [`verify_r_tests()`](https://kaipingyang.github.io/codeagent/reference/verify_r_tests.md)).

- mcp_config:

  MCP client config (JSON path or inline list) to connect external MCP
  servers; see
  [`register_mcp_client()`](https://kaipingyang.github.io/codeagent/reference/register_mcp_client.md).
  NULL disables.

- register_tools:

  Logical. If `TRUE` (default) register all tools now. `FALSE` returns a
  lightweight shell (chat + settings + system prompt, no tools) so
  callers (e.g.
  [`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md))
  can render UI first and defer the expensive tool registration; call
  [`.register_all_tools()`](https://kaipingyang.github.io/codeagent/reference/dot-register_all_tools.md)
  later.

- data_shield:

  `NULL` (off), a strategy list from `shield_*()` (creates a private
  [DataShield](https://kaipingyang.github.io/codeagent/reference/DataShield.md)
  R6), or an explicit
  [DataShield](https://kaipingyang.github.io/codeagent/reference/DataShield.md)
  instance shared by selected chat threads. For a harness-only client,
  attach tools then call `client$data_shield$install(client$chat)`.

- max_budget_usd:

  Numeric or NULL (default). Hard dollar-cost cap for this client's
  `chat` (mirrors Claude Code's `maxBudgetUsd`), checked alongside the
  token budget in
  [`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md)
  via `chat$get_cost()`. NULL (default) means no cap. Only takes effect
  where ellmer has price data for the provider/model; unpriced custom
  endpoints (e.g. a Databricks/Azure serving endpoint ellmer doesn't
  recognize) report cost `$0` forever, so the cap silently never fires
  there – this is a known limitation, not a bug (see
  `CODEAGENT_MAX_BUDGET_USD` env var / `max_budget_usd` in settings.json
  for the same knob without a client-code change).

- tools:

  Tool selection, in one capability namespace shared by codeagent-native
  and btw groups.

  - `NULL` (default) registers everything, exactly as before.

  - `FALSE` registers no codeagent tool; tools the host registered on
    `chat` itself are untouched.

  - A character vector of capability groups (`"files"`, `"shell"`,
    `"docs"`, `"git"`, ...), individual tool names (`"Read"`, `"Bash"`),
    or both. Two capabilities have parallel implementations and take an
    `@` suffix: `"files@core"` (codeagent's, any absolute path),
    `"files@btw"` (btw's hash-anchored, cwd-only Path A),
    `"files@both"`, and the same for `"web"`. Unknown names are an error
    listing the valid groups, never a silent drop. An entry that is
    valid but registers nothing – a btw group whose optional dependency
    is missing, or one you also passed to `disallowed_tools` – warns and
    names the entry, rather than leaving you to notice the gap.
    Resource-driven tools stay on their own arguments (`mcp_config`,
    `data_shield`) and are never removed by this selection.

- disallowed_tools:

  Character vector or NULL. Carries two meanings in one vector,
  mirroring the Claude Agent SDK's public contract. A bare name – a tool
  (`"Bash"`) or a capability group (`"lint"`) – removes those tool
  definitions, so the model never sees them. A scoped entry
  (`"Bash(rm *)"`) keeps the tool and becomes an ordinary deny rule,
  which is absolute in every permission mode including `bypass`.

## Value

Object of class `CodeagentClient` with `$chat`, `$settings`, and
`$data_shield` (NULL when disabled).
