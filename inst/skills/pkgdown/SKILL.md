---
name: pkgdown
description: Build or update a pkgdown documentation website for an R package, including reference grouping and vignette articles
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
---

Build or update the pkgdown site for this R package.

Steps:

1. Ensure a `_pkgdown.yml` exists at the package root. If not, create a minimal one:
   ```yaml
   url: ~
   template:
     bootstrap: 5
   ```
2. Organise the reference index by subsystem using `reference:` sections with
   `title` + `contents` (list exported functions per group). Group by role
   (e.g. core, tools, permissions, sessions, ui) rather than alphabetically.
3. Register vignettes under `articles:` when there are more than a few.
4. Build the site and fix any warnings:
   ```r
   pkgdown::build_site()          # full build
   pkgdown::build_reference()     # reference only (faster while iterating)
   pkgdown::check_pkgdown()       # verify every exported topic is listed
   ```
5. Report any functions missing from the reference index (from
   `check_pkgdown()`) and add them to the appropriate section.

Prefer editing `_pkgdown.yml` over ad-hoc scripts. Do not commit the generated
`docs/` directory unless the project already tracks it.
