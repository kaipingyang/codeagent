# Load codeagent settings

Merges configuration from all sources in priority order. The trusted
user-level `env` block is applied before the environment-variable layer;
security-sensitive project settings are ignored.

## Usage

``` r
load_settings(cwd = getwd(), setting_sources = c("user", "project"))
```

## Arguments

- cwd:

  Character. Working directory (used to locate
  `.codeagent/settings.json` and `CLAUDE.md`). Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

- setting_sources:

  Which filesystem sources to load, as in the Claude Agent SDK's
  `setting_sources`: `"user"` – `~/.codeagent/settings.json` (including
  its `env` block) and the user-level `~/.claude/CLAUDE.md` /
  `~/.codeagent/CLAUDE.md`; `"project"` –
  `<cwd>/.codeagent/settings.json` and the `CLAUDE.md` / `AGENTS.md` /
  `btw.md` / `llms.txt` files from `cwd` upwards. Default both. A host
  app that ships its own instructions in `cwd` uses `"project"`, so the
  runtime user's personal `settings.json` and `CLAUDE.md` files never
  reach the app (also when the model is switched). Not covered:
  `CODEAGENT_*` variables in `~/.Renviron`, auto-memory and user-level
  skill directories, which follow `CODEAGENT_HOME` and the btw skill
  paths.

## Value

A named list of settings.
