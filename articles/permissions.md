# Permissions

Every tool call passes through a permission gate before it runs.

## How the gate decides

    model requests a tool
        |
        v
    chat$on_tool_request  ->  permission gate (.tool_gate_fn)
        |
        +- PreToolUse hook (fires for every call)
        |
        +- read-only tool AND no override?  -- yes -->  ALLOW (short-circuit)
        |
        v  .gate_decide  (precedence, highest first)
      1. settings$tools$overrides[tool]      -> allow / deny / ask
      2. settings$tools$capabilities[class]  -> read|write|exec|net -> allow/deny/ask
      3. fallback -> check_permission(mode, rules):
           plan          -> deny (non-read)
           user rules    -> first glob match wins (allow/deny/ask)
           accept_edits  -> edit tools allow
           bypass        -> allow
           bubble        -> ask (bubbles to parent agent)
           dont_ask      -> read-only allow, else deny
           auto          -> small-model classifier -> allow/deny/ask
           default       -> read-only (& read-only Bash) allow, else ask
        |
        v
      decision --+-- allow --> tool runs --> on_tool_result --> PostToolUse hook
                 +-- deny  --> PermissionDenied hook --> ellmer::tool_reject()
                 |                                       (loop gets an error result)
                 +-- ask   --> ask_fn():  console prompt (CLI)
                                        |  promise -> Shiny Allow/Deny bar (async)
                               approved -> run   /   rejected -> deny

`settings$tools$sets` (`"A"` = codeagent core, `"B"` = btw) decides
which tool *sets* get registered; it does not affect the per-call
decision above.

## Modes

| Mode           | Behaviour                                                                         |
| -------------- | --------------------------------------------------------------------------------- |
| `default`      | Read-only tools auto-allowed; risky tools (Write/Edit/MultiEdit/Bash/RunR) prompt |
| `plan`         | All non-read operations denied (read-only planning)                               |
| `accept_edits` | File edit tools auto-allowed; other risky tools still prompt                      |
| `bypass`       | Everything allowed (use with care)                                                |
| `dont_ask`     | Read-only allowed; anything that would prompt is denied (CI/CD)                   |
| `auto`         | A small model classifies each call                                                |
| `bubble`       | Sub-agent mode: permission bubbles up to the parent agent                         |

``` r
client <- codeagent_client(chat, permission_mode = "default")
```

## Fine-grained rules

Rules match tool arguments (mirroring Claude Code’s `Bash(git *)`
syntax) and are evaluated first, in order:

``` json
{
  "permissions": {
    "allow": ["Bash(git status)", "Read(*)"],
    "deny":  ["Bash(rm -rf *)"],
    "ask":   ["Write(*)"],
    "defaultMode": "default"
  }
}
```

## Interactive approval (Shiny)

In `default` mode the Shiny app shows an Allow/Deny bar above the input
when a risky tool is requested; the agent loop resumes on your choice.
`AskUserQuestion` similarly pauses to ask a clarifying question. Both
use an async promise mechanism; the CLI path uses a console prompt
instead.

## Hooks

`PreToolUse` / `PermissionRequest` hooks (from `settings.json`) can
return `"allow"`, `"deny"`, or fall through to the default gate — useful
for policy-as-code.
