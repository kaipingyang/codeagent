# Load a skill's full prompt

Reads `SKILL.md` body and substitutes `$ARGUMENTS` / `$ARG1` etc. Uses
btw's `find_skill()` when available, falls back to direct file read.

## Usage

``` r
load_skill_prompt(name, args = "", cwd = getwd(), skills = NULL)
```

## Arguments

- name:

  Character. Skill name.

- args:

  Character. Arguments passed after the skill name.

- cwd:

  Character. Project working directory.

- skills:

  The skill set, as in
  [`list_skills_meta()`](https://kaipingyang.github.io/codeagent/reference/list_skills_meta.md).

## Value

Character(1). The fully resolved prompt string.
