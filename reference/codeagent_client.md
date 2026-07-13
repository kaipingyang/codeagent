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
  register_tools = TRUE
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

  Character vector or NULL. btw tool groups to register (e.g.
  `c("docs","git","pkg")`). NULL = all available groups.

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

## Value

Object of class `CodeagentClient` with slots `$chat` and `$settings`.
