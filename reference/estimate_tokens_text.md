# Estimate token count from text

Uses a char/3.5 heuristic which gives better accuracy than char/4 for
mixed natural-language + code content. Rounding is conservative
(ceiling).

## Usage

``` r
estimate_tokens_text(text)
```

## Arguments

- text:

  Character vector or single string.

## Value

Integer. Estimated token count.
