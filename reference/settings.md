# Settings System

Configuration loading for codeagent. Priority (highest to lowest):
environment variables \> `~/.codeagent/settings.json` \>
`.codeagent/settings.json` \> CLAUDE.md.

The `env` block in settings.json is applied via
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) before the
environment-variable layer is read, so it works even under
`Rscript --vanilla` (which skips `.Renviron`). This mirrors Claude
Code's behaviour.
