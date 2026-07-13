# Create the MultiEdit tool

Applies multiple `old_string -> new_string` replacements sequentially to
a single file in one call.

## Usage

``` r
multi_edit_tool(mode = "default", rules = list(), ask_fn = NULL)
```

## Arguments

  - mode:
    
    Character. Permission mode.

  - rules:
    
    List. Permission rules.

  - ask\_fn:
    
    Function or NULL.

## Value

An `ellmer::tool()` object.
