# Run R Code Tool (permission-gated)

Wraps
[`btw::btw_tool_run_r()`](https://posit-dev.github.io/btw/reference/btw_tool_run_r.html)
behind codeagent's permission gate. Executing arbitrary R code is
dangerous (no sandbox, runs in the global environment), so this tool is
treated like Bash: `destructive_hint = TRUE`, never read-only, and every
call must be confirmed via `ask_fn` in `default` mode (or a permission
rule / `bypass`).
