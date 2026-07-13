# Create a codeagent client from any ellmer Chat

Injects codeagent tools (Bash, Read, Write, Edit, Glob, Grep, LS, btw
tools, skill tool) and rebuilds the system prompt. The returned
`CodeagentClient` is the single object passed to `codeagent()` and
`codeagent_app()`.

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
    
    An `ellmer::Chat` object – any backend supported by ellmer:
    `chat_openai_compatible()`, `chat_anthropic()`, `chat_ollama()`,
    etc. If NULL, a chat is auto-built from
    `CODEAGENT_BASE_URL`/`CODEAGENT_MODEL` env vars (or Anthropic
    defaults).

  - permission\_mode:
    
    Character. One of
    [PermissionMode](https://kaipingyang.github.io/codeagent/reference/PermissionMode.md).

  - rules:
    
    List of `PermissionRule()` objects.

  - cwd:
    
    Character. Working directory (used for CLAUDE.md, skills, sessions).

  - max\_turns:
    
    Integer. Maximum agentic loop turns.

  - btw\_groups:
    
    Character vector or NULL. btw tool groups to register (e.g.
    `c("docs","git","pkg")`). NULL = all available groups.

  - worktree\_isolation:
    
    Logical. Run sub-agents in isolated git worktrees.

  - verify\_fn:
    
    Function or NULL. Optional output verifier; re-enters the loop when
    it reports failures (e.g. `verify_r_tests()`).

  - mcp\_config:
    
    MCP client config (JSON path or inline list) to connect external MCP
    servers; see `register_mcp_client()`. NULL disables.

  - register\_tools:
    
    Logical. If `TRUE` (default) register all tools now. `FALSE` returns
    a lightweight shell (chat + settings + system prompt, no tools) so
    callers (e.g. `codeagent_app()`) can render UI first and defer the
    expensive tool registration; call `.register_all_tools()` later.

## Value

Object of class `CodeagentClient` with slots `$chat` and `$settings`.
