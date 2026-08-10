# Statically extract external-file references from R code.

Statically extract external-file references from R code.

## Usage

``` r
.audit_r_code_refs(code)
```

## Arguments

- code:

  Character (one or more lines) of R source. Untrusted – parsed, never
  evaluated.

## Value

A list:

- `static_paths` – character vector of literal string paths passed to a
  source/load-family call.

- `dynamic` – TRUE if the code uses a dynamic primitive, calls a
  source-family function with no literal string argument (e.g.
  `source(var)`), or assigns/references a source-family function as a
  bare symbol (possible indirect call) – i.e. a static pass cannot be
  sure what it loads/runs.

- `source_calls` – which source-family functions were called (for
  audit).

- `parse_error` – TRUE if the code did not parse (treated as dynamic:
  un-analysable).
