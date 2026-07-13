# Register notebook tools to an ellmer Chat object

Register notebook tools to an ellmer Chat object

## Usage

``` r
register_notebook_tools(chat, mode = "default", rules = list(), ask_fn = NULL)
```

## Arguments

  - chat:
    
    An `ellmer::Chat` object.

  - mode:
    
    Character. Permission mode.

  - rules:
    
    List. Permission rules.

  - ask\_fn:
    
    Function or NULL.

## Value

Invisibly returns `chat`.
