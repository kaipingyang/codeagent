# Reads `codeagent.md` or `.codeagent/config.md` in the project directory and constructs a [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md) from the declared settings. Supports multi-client aliases (pick interactively or by name).

Reads `codeagent.md` or `.codeagent/config.md` in the project directory
and constructs a
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
from the declared settings. Supports multi-client aliases (pick
interactively or by name).

## Usage

``` r
codeagent_client_config(alias = NULL, cwd = getwd(), ...)
```

## Arguments

- alias:

  Character or NULL. Select a specific alias from `client:` section.
  NULL uses the first/only defined client.

- cwd:

  Character. Project directory.

- ...:

  Additional arguments passed to
  [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md).

## Value

A `CodeagentClient` object, or NULL if no config file found.
