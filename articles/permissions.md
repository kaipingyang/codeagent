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

### What happens if the human approves something dangerous anyway

The `ask` step exists so a human can decide — and a human can always say
yes to something they shouldn’t. If the model requests
`Bash: rm -rf ./data` and the operator clicks Allow, **the gate itself
has no opinion about whether that was a good idea**; it already did its
job by asking. If you want certain operations to be blocked *regardless
of what gets clicked*, that veto has to live upstream of `ask_fn`, at
one of these layers (weakest/simplest to strongest/most general):

| Layer | Where | Blocks before a human ever sees a prompt? |
|----|----|----|
| `rules` deny glob | `settings.json` / `codeagent_client(rules=)`, e.g. `Bash(rm -rf *)` | Yes — matches in `.gate_decide`’s fallback step, so `ask_fn` is never called |
| Data Shield `shield_ingress(patterns=, on_fail="block")` | Repurposing Data Shield’s ingress scanner for a non-confidentiality rule | Yes — `block` rejects unconditionally |
| Data Shield `shield_tool_policy(rules=list(X=list(execution="deny")))` | Same DataShield instance | Yes — the whole tool is disabled |
| `PreToolUse` hook returning `action="deny"` | `HookRegistry$register_pre()` / `settings.json` hooks | Yes — fires before `.gate_decide` resolves to `ask` at all |

All four fire *before* the human is asked, so an operator’s later “yes”
can never override them — that is the actual backstop this vignette’s
diagram implies but doesn’t spell out.

### Why none of these are a complete answer

Every one of the four is, underneath, a **syntactic match** — a glob, a
regex, or whatever logic you put in the hook. That has the exact same
blind spot as Data Shield’s own ingress scanner (see
[`vignette("data-shield")`](https://kaipingyang.github.io/codeagent/articles/data-shield.md)):
a rule written for `Bash(rm -rf *)` does not catch the model routing the
same intent through `RunR`’s `system("rm -rf /x")` or R’s own
`unlink(dir, recursive = TRUE)` (no literal “rm -rf” anywhere), a
differently-destructive command (`git reset --hard`, `DROP TABLE`,
`find . -delete`), a string built at runtime
(`paste0("r","m ","-","r","f")`), or a script written to disk in one
(innocuous-looking) step and executed in a second. Static rules are
defense-in-depth, not a guarantee, for the same reason Data Shield’s own
Honest Limits section gives.

The two approaches that actually hold up against rewording are,
symmetrically with Data Shield’s own design:

- **A semantic reviewer** (the same idea as
  [`shield_reviewer()`](https://kaipingyang.github.io/codeagent/reference/shield_reviewer.md),
  applied to operation intent instead of data exfiltration) — classifies
  whether code *intends* something destructive regardless of syntax.
  Still an LLM, still evadable by a sufficiently adversarial prompt, but
  raises the bar past simple rewording.
- **OS-level sandboxing**
  ([`shield_sandbox()`](https://kaipingyang.github.io/codeagent/reference/shield_sandbox.md)’s
  full adapter, still roadmap) — a read-only or scoped-writable
  filesystem mount means the kernel refuses the underlying
  `unlink`/`rmdir`/`truncate` syscall no matter what language or
  obfuscation produced it. This is the only guarantee that does not
  depend on recognizing the command at all.

Productizing this as a curated, cross-language rule set — rather than
each host writing its own hook/rules from scratch — is an open design
question, not yet implemented; the most consistent shape would reuse
Data Shield’s own pipeline/audit-log/`install()` machinery (e.g. a
`shield_destructive_ops()` strategy) rather than a second, competing
“shield” concept.
