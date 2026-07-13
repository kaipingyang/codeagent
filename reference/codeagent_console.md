# Run the interactive REPL

Run the interactive REPL

## Usage

``` r
codeagent_console(
  client,
  stream = TRUE,
  prompt_str = "› ",
  con = NULL,
  session_id = NULL,
  quiet = FALSE
)
```

## Arguments

- client:

  A `CodeagentClient`.

- stream:

  Logical. Stream responses token-by-token.

- prompt_str:

  Character. The input prompt shown each turn.

- con:

  Connection to read lines from (default stdin; override in tests).

- session_id:

  Character or NULL. Session id for auto-save (generated if NULL).

- quiet:

  Logical. Suppress the startup banner and settings warnings (used in
  tests and non-interactive contexts where the output would be noise).

## Value

Invisibly the session id. Loops until `/exit` or EOF.
