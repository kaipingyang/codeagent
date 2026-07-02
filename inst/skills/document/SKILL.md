---
name: document
description: Run devtools::document() to rebuild NAMESPACE and man/ from roxygen2
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Glob
---

Rebuild R package documentation from roxygen2 comments.

```r
devtools::document()
```

This regenerates:
- `NAMESPACE` (exports, imports, S3/S4 methods)
- `man/*.Rd` files from `#'` roxygen comments

After running, check for:
1. Undocumented exported functions (R CMD check will warn)
2. Missing `@param` or `@return` tags
3. Broken `[function()]` cross-references

Then reinstall the package so the updated help pages are available:
```r
pak::local_install(".", ask = FALSE, upgrade = FALSE)
```
