# Read codeagent configuration from codeagent.md / .codeagent/config.md

Searches the project directory and user home for a configuration file.
Returns a named list with fields: `client_spec`, `btw_groups`,
`permission_mode`, `max_turns`, `system_prompt`.

## Usage

``` r
.read_codeagent_config(cwd = getwd())
```

## Arguments

- cwd:

  Character. Project directory to search.

## Value

Named list of config fields, or empty list if no file found.
