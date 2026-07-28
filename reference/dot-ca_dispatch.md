# Dispatch CLI arguments to a command + rest vector.

Dispatch CLI arguments to a command + rest vector.

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
