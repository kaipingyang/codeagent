# Create the skill tool for LLM auto-triggering

Registers an ellmer tool that allows the LLM to semantically match user
intent to skills and load them automatically – even without explicit
`/name` syntax from the user.

## Usage

``` r
.make_skill_tool(cwd = getwd(), skills = NULL)
```

## Arguments

- cwd:

  Character. Project working directory.

- skills:

  The skill set, as in
  [`list_skills_meta()`](https://kaipingyang.github.io/codeagent/reference/list_skills_meta.md).

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object, or `NULL` if no skills exist.
