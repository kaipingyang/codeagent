# Skill metadata (frontmatter-only, no full content)

Skill metadata (frontmatter-only, no full content)

## Usage

``` r
SkillMeta(
  name,
  description = "",
  argument_hint = "",
  auto_trigger = TRUE,
  allowed_tools = NULL,
  base_dir = NULL,
  path = NULL
)
```

## Arguments

  - name:
    
    Character. Skill name.

  - description:
    
    Character. One-line description shown in skill list.

  - argument\_hint:
    
    Character. Hint shown after skill name (e.g. "
    
    ").

  - auto\_trigger:
    
    Logical. Whether LLM may auto-invoke this skill.

  - allowed\_tools:
    
    Character vector or NULL. Tools this skill may use.

  - base\_dir:
    
    Character. Directory containing SKILL.md.

  - path:
    
    Character. Absolute path to SKILL.md.

## Value

Object of class `SkillMeta`.
