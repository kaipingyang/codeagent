# List skill metadata from all skill directories

Scans all configured directories for `<name>/SKILL.md` files. btw is
used as the primary backend when available; codeagent-specific paths
(.claude/, .codex/) are merged in. Results are cached per cwd;
invalidated when any SKILL.md mtime changes.

## Usage

``` r
list_skills_meta(cwd = getwd())
```

## Arguments

  - cwd:
    
    Character. Project working directory.

## Value

Named list of `SkillMeta` objects (keyed by skill name).
