# List skill metadata from all skill directories

Scans all configured directories for `<name>/SKILL.md` files. btw is
used as the primary backend when available; codeagent-specific paths
(.claude/, .codex/) are merged in. Results are cached per cwd;
invalidated when any SKILL.md mtime changes.

## Usage

``` r
list_skills_meta(cwd = getwd(), skills = NULL)
```

## Arguments

- cwd:

  Character. Project working directory.

- skills:

  Which skills to use: `NULL` (default) every skill discovered as above;
  `FALSE` none; or a character vector whose entries are skill
  directories (every `<name>/SKILL.md` inside; relative paths are
  resolved against `cwd`) and/or names of discovered skills. See the
  `skills` argument of
  [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md).

## Value

Named list of `SkillMeta` objects (keyed by skill name).
