# Create a new shared task board

Create a new shared task board

## Usage

``` r
board_create(db_path = tempfile(fileext = ".sqlite"))
```

## Arguments

  - db\_path:
    
    Character. Path to the SQLite file. Defaults to a temp file.

## Value

Character. The `db_path` (pass it to the other board functions).
