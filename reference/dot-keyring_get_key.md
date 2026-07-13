# Retrieve an API key from keyring or the environment

Looks up `key_name` in order:

1.  OS keyring (service = "codeagent"), if available

2.  Environment variable `key_name`

3.  Returns `""` (not found)

## Usage

``` r
.keyring_get_key(key_name)
```

## Arguments

  - key\_name:
    
    Character. Environment variable / keyring username.

## Value

The key value as a string, or `""` if not found.
