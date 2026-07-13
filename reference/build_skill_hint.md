# Build skill hint for system prompt

Returns skill listing for the system prompt. Uses btw's system prompt
format when available; falls back to simple list.

## Usage

``` r
build_skill_hint(cwd = getwd(), max_tokens = 1000L)
```

## Arguments

  - cwd:
    
    Character. Project working directory.

  - max\_tokens:
    
    Integer. Approximate token budget.

## Value

Character(1). The skill hint block, or `""` if no skills found.
