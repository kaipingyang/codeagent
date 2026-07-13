# Session info object

Session info object

## Usage

``` r
SessionInfo(
  session_id,
  summary,
  last_modified,
  file_size = NULL,
  custom_title = NULL,
  first_prompt = NULL,
  git_branch = NULL,
  cwd = NULL,
  tag = NULL,
  created_at = NULL
)
```

## Arguments

  - session\_id:
    
    Character. UUID.

  - summary:
    
    Character. Short summary.

  - last\_modified:
    
    Numeric. mtime in ms.

  - file\_size:
    
    Numeric or NULL. File size in bytes.

  - custom\_title:
    
    Character or NULL.

  - first\_prompt:
    
    Character or NULL.

  - git\_branch:
    
    Character or NULL.

  - cwd:
    
    Character or NULL.

  - tag:
    
    Character or NULL.

  - created\_at:
    
    Numeric or NULL. Creation timestamp in ms.

## Value

Object of class `SessionInfo`.
