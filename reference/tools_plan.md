# Plan Mode Tools

Tools that let the model enter and exit a read-only planning mode
mid-conversation, mirroring Claude Code's EnterPlanMode/ExitPlanMode.
They flip a shared `mode_env$mode` slot that every permission checker
reads live (see `.make_permission_checker()` in `tools_builtin.R`), so
switching to `"plan"` immediately makes all write/exec tools deny while
reads still pass.
