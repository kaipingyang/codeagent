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

- session_id:

  Character. UUID.

- summary:

  Character. Short summary.

- last_modified:

  Numeric. mtime in ms.

- file_size:

  Numeric or NULL. File size in bytes.

- custom_title:

  Character or NULL.

- first_prompt:

  Character or NULL.

- git_branch:

  Character or NULL.

- cwd:

  Character or NULL.

- tag:

  Character or NULL.

- created_at:

  Numeric or NULL. Creation timestamp in ms.

## Value

Object of class `SessionInfo`.
