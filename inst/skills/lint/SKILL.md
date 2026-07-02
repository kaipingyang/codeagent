---
name: lint
description: Lint and style R code with lintr and styler
argument-hint: "<file or directory>"
allowed-tools:
  - Bash
  - Read
  - Edit
---

Lint and style R code.

**Step 1 — Style with styler** (auto-fix formatting):
```r
styler::style_file("R/my_file.R")
# or entire package:
styler::style_pkg()
```

**Step 2 — Lint with lintr** (static analysis, does not auto-fix):
```r
lintr::lint("R/my_file.R")
# or entire package:
lintr::lint_package()
```

Common issues to fix:
- `object_name_linter`: use `snake_case` for variables/functions
- `line_length_linter`: keep lines under 100 chars
- `trailing_whitespace_linter`: remove trailing spaces
- `no_tab_linter`: use spaces, not tabs
- `assignment_linter`: use `<-` not `=` for assignment

After fixing, run:
```r
devtools::check(args = "--no-tests")   # check for 0 warnings
```

Non-ASCII characters in R source files will cause R CMD check to fail — use `\uXXXX` escapes inside string literals only.
