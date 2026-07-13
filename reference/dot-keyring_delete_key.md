# Delete a key from the OS keyring

No-op (with a warning) if the key does not exist or keyring is
unavailable.

## Usage

``` r
.keyring_delete_key(key_name)
```

## Arguments

  - key\_name:
    
    Character. Environment variable / keyring username.

## Value

Invisibly `TRUE` if deleted, `FALSE` if not found or unavailable.
