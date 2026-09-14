# Settings System

Configuration loading for codeagent. Priority (highest to lowest):
environment variables \> trusted user settings \> non-sensitive project
settings \> CLAUDE.md.

Only the user-level `env` block is applied via
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html). Repository
settings cannot change credentials, endpoints, permissions, hooks,
sandbox policy, or the registered tool set.
