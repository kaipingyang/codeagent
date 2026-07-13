# Register btw file tools with permission control

Replaces codeagent's built-in Read/Write/Edit/Glob/Grep/LS tools with
btw's superior equivalents. Write tools get the permission gate; read
tools are registered directly.

## Usage

``` r
register_btw_file_tools(chat, mode = "default", rules = list(), ask_fn = NULL)
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

Invisibly returns the number of tools registered.

## Details

**Experimental – not loaded by default.**
