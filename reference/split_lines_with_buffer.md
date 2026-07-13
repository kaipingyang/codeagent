# Split buffered output into complete lines

Split buffered output into complete lines

## Usage

``` r
split_lines_with_buffer(buf, new_output)
```

## Arguments

  - buf:
    
    Character(1). Current carry-over buffer.

  - new\_output:
    
    Character(1). New raw text to append.

## Value

Named list: `complete_lines` (character vector) and `remaining`
(character(1)).
