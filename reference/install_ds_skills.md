# Install Posit's data-science skill collection (posit-dev/skills)

Installs the [posit-dev/skills](https://github.com/posit-dev/skills)
collection (r-lib / shiny / quarto / tidyverse / open-source domains)
via btw, into a btw skill directory that codeagent already discovers.
After installing, the skills appear in `list_skills_meta()` and as
`/name` commands.

## Usage

``` r
install_ds_skills(
  skill = NULL,
  scope = c("user", "project"),
  overwrite = FALSE
)
```

## Arguments

  - skill:
    
    Which posit-dev/skills to install: `NULL` (default) installs a
    curated R / data-science set; `"all"` installs every skill in the
    repo; or pass one or more skill names (character vector). btw
    installs one skill at a time, so multiple names are installed in a
    loop.

  - scope:
    
    Character. `"user"` (default) installs to the user-global btw skills
    dir; `"project"` installs to the project's `.btw/skills`.

  - overwrite:
    
    Logical. Overwrite an existing skill of the same name.

## Value

Invisibly `TRUE` if all requested skills installed, else `FALSE`.

## Details

This is a thin, documented wrapper over
`btw::btw_skill_install_github()` – codeagent does not vendor or re-host
the skills; it uses the upstream collection directly.

## See also

`btw::btw_skill_install_github()`, `list_skills_meta()`

## Examples

``` r
if (FALSE) { # \dontrun{
install_ds_skills()                        # curated R/data-science set
install_ds_skills("all")                   # everything in posit-dev/skills
install_ds_skills("shiny-bslib")           # a specific skill
install_ds_skills(c("cli", "quarto-authoring"))
list_skills_meta()                          # now includes the new skills
} # }
```
