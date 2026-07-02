---
name: roxygen
description: Generate roxygen2 documentation skeleton for R functions
argument-hint: "<function name or file>"
allowed-tools:
  - Read
  - Glob
  - Grep
  - LS
  - Edit
  - Write
---

Generate roxygen2 documentation for R functions. Given a function name or file:

1. Read the function signature and body carefully
2. Generate a complete roxygen2 block with:
   - `@title` (one line, sentence case)
   - `@description` (what it does, 1-3 sentences)
   - `@param` for EVERY parameter (type + what it does)
   - `@return` describing what is returned
   - `@examples` with at least one runnable example
   - `@export` if it should be part of the public API
   - `@keywords internal` if it is an internal helper
3. Place the block immediately above the function definition
4. Use markdown formatting in descriptions (backticks for code, `[function()]` for links)

R documentation conventions:
- Parameter descriptions start with capital letter, no period at end
- `@return` describes the object class and key contents
- Examples must be runnable without side effects (use `\dontrun{}` if needed)
- Use `@inheritParams other_function` to avoid repeating shared params
