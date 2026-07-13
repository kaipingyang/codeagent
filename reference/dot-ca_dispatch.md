# Dispatch CLI arguments to a command + rest vector.

Determines which subcommand to run given raw positional argv and the
`print_mode` flag. Used by `exec/codeagent.R` to keep dispatch logic
testable.

## Usage

``` r
.ca_dispatch(argv = character(), print_mode = FALSE)
```

## Arguments

- argv:

  Character vector of positional arguments (no flags).

- print_mode:

  Logical. TRUE when `-p`/`--print` was passed.

## Value

Named list: `cmd` (character), `rest` (character vector).

## Details

Rules (in order):

1.  If `argv[[1]]` is a known subcommand name, use it.

2.  If `print_mode = TRUE` or `argv` is non-empty, treat as a one-shot
    `run` (the prompt comes from `argv`).

3.  Otherwise default to `chat` (interactive REPL).
