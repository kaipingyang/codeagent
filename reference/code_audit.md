# Code Audit – static reference extraction (31w step 1)

Deterministic, LLM-free, filesystem-free static analysis of R code to
find where it pulls in *external* scripts/data. This is the first layer
of the code-audit defence (see references/plan/31w): it walks the AST
via base [`getParseData()`](https://rdrr.io/r/utils/getParseData.html)
and reports which external files the code references by literal path,
plus whether it uses dynamic primitives that a static pass cannot
resolve.

Threat model split (31w):

- **Threat A (static)** – `source("x.R")` / `load("x.rds")` / `readRDS`
  / `sourceCpp` with a *literal string path*. Statically extractable -\>
  the path is returned in `static_paths` for downstream whitelist +
  review.

- **Threat B (dynamic)** – `source(var)`, `eval(parse())`,
  `get(paste0())`, [`do.call()`](https://rdrr.io/r/base/do.call.html)
  etc. Undecidable statically (halting problem) -\> flagged
  `dynamic = TRUE`; the real defence is the sandbox (31n), not this
  audit.

This function reads NO files and calls NO LLM – it only parses the code
text. It is safe to run on fully untrusted code (parsing != evaluating).
