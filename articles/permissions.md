# Permissions

Every tool call passes through a permission gate before it runs.

## Modes

| Mode | Behaviour |
|----|----|
| `default` | Read-only tools auto-allowed; risky tools (Write/Edit/MultiEdit/Bash/RunR) prompt |
| `plan` | All non-read operations denied (read-only planning) |
| `accept_edits` | File edit tools auto-allowed; other risky tools still prompt |
| `bypass` | Everything allowed (use with care) |
| `dont_ask` | Read-only allowed; anything that would prompt is denied (CI/CD) |
| `auto` | A small model classifies each call |
| `bubble` | Sub-agent mode: permission bubbles up to the parent agent |

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
