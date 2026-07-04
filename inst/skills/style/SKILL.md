---
name: style
description: Format and lint R code to a consistent style using styler and lintr (or air), reporting and fixing style issues
argument-hint: "[file or directory, default: R/]"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Glob
---

Normalise R code style and surface lint issues for the given path (default `R/`).

1. Format with whichever formatter the project uses:
   - `air format .` if an `air.toml` / air is configured (fast, opinionated), OR
   - `styler::style_pkg()` for a package, or `styler::style_dir("R")` /
     `styler::style_file("<path>")` for a subset.
2. Lint and report remaining issues:
   ```r
   lintr::lint_package()          # whole package
   lintr::lint("<path>")          # single file/dir
   ```
3. Summarise the lint findings grouped by linter (e.g. object naming, line
   length, assignment operator), then fix the actionable ones with Edit.
4. Respect the project's existing conventions: match surrounding base-R vs
   tidyverse style, and honour any `.lintr` config. Do not introduce a new
   style regime unless asked.

Note: this package's R sources must stay ASCII-only (R CMD check); flag any
non-ASCII characters found outside `\uXXXX` string escapes.
