# Parse a client spec string ("provider/model") into chat factory args

Supports:

  - `"openai/model-name"` -\> `chat_openai_compatible()` using
    `CODEAGENT_BASE_URL`

  - `"anthropic/model-name"` -\> `chat_anthropic(model = "model-name")`

  - `"alias"` -\> looked up in `aliases` named list

## Usage

``` r
.parse_client_spec(spec, aliases = list(), cwd = getwd())
```

## Arguments

  - spec:
    
    Character. Client spec string or alias key.

  - aliases:
    
    Named list. Alias -\> spec mapping.

  - cwd:
    
    Character. Working directory (for settings).

## Value

An `ellmer::Chat` object.
