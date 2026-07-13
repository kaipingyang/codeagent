# Tag a session

Appends a `tag` JSONL entry. Pass `NULL` to clear the tag.

## Usage

``` r
tag_session(session_id, tag = NULL, directory = NULL)
```

## Arguments

  - session\_id:
    
    Character. UUID.

  - tag:
    
    Character or NULL. Tag string (NULL clears).

  - directory:
    
    Character or NULL. Project working directory.

## Value

Invisibly NULL.
