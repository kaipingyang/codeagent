# Skills and slash commands

**Language:** English \|
[简体中文](https://kaipingyang.github.io/codeagent/articles/skills-usage-cn.md)

## What are skills?

Skills are reusable prompt templates stored as `<name>/SKILL.md`. A user
can type `/name arguments` to load one directly. The model can also
semantically match the names and descriptions in its system hint and
call the `use_skill` tool, which loads the full body only when needed.

Local slash commands take precedence over skills with the same name. In
particular, `/compact [instructions]` is handled locally by the REPL or
Shiny server and invokes the compaction controller; it is not sent as a
skill prompt. The package also ships a `compact/SKILL.md` for semantic
tool invocation.

## Skills shipped by codeagent

The installed package currently contains these 17 skill directories:

| Skill | Description |
|----|----|
| `/plan` | Produce analysis and a step-by-step implementation plan without editing files |
| `/verify` | Verify the previous action for correctness and completeness |
| `/simplify` | Review and simplify recent code or output |
| `/compact` | Request a structured conversation summary; direct `/compact` syntax is the local command described above |
| `/remember` | Save durable information to cross-session memory |
| `/loop` | Interpret a periodic task request such as `/loop 5m /verify` |
| `/document` | Run package documentation workflow, including [`devtools::document()`](https://devtools.r-lib.org/reference/document.html) |
| `/roxygen` | Generate a roxygen2 documentation skeleton |
| `/testthat` | Create testthat unit tests |
| `/style` | Format and lint R code consistently |
| `/lint` | Lint and style R code with lintr and styler |
| `/news` | Update `NEWS.md` for a release |
| `/pkgdown` | Build or update a pkgdown site, reference index, and vignette articles |
| `/explore` | Explore and analyze a data frame in natural language |
| `/report` | Export an exploration session to a Quarto document |
| `/no-secrets` | Guard against printing or committing secrets and concrete infrastructure identifiers |
| `/posit-dev-packages` | Update the project’s pinned core development packages and report versions |

The live list may be larger because btw, installed packages (including
Shiny), and user/project directories contribute skills. Inspect it with
[`list_skills_meta()`](https://kaipingyang.github.io/codeagent/reference/list_skills_meta.md)
or open the slash-command typeahead by typing `/` in the chat.

## Using skills from the chat

    # In the Shiny app or REPL:
    /plan add a new summarise_by_group() function
    /roxygen summarise_by_group
    /testthat summarise_by_group

An unknown `/name` is parsed as a skill request, but if loading fails
the REPL and Shiny paths keep the original slash text and send it as an
ordinary prompt. A direct programmatic
[`load_skill_prompt()`](https://kaipingyang.github.io/codeagent/reference/load_skill_prompt.md)
call instead raises “Skill not found” and lists the currently available
names.

## Creating custom skills

Use a directory, not a flat Markdown file. These user and project
locations are supported:

    # User-global (btw native):
    ~/.btw/skills/my-skill/SKILL.md
    ~/.config/btw/skills/my-skill/SKILL.md

    # Project-local:
    .btw/skills/my-skill/SKILL.md          # btw native
    .agents/skills/my-skill/SKILL.md       # btw agents dir
    .claude/skills/my-skill/SKILL.md       # Claude Code compatibility
    .codex/skills/my-skill/SKILL.md        # Codex compatibility

btw also contributes its built-ins and skills from packages it
discovers. codeagent supplements those results with the installed
codeagent skills, installed Shiny package skills, and the four
project-local compatibility paths above. For custom skills, prefer
`~/.btw/skills` globally and `.btw/skills` inside a project.

**SKILL.md format**:

``` markdown
---
name: my-skill
description: Short description shown in skill picker
metadata:
  argument-hint: "<what to type after /my-skill>"
allowed-tools:
  - Read
  - Bash
---

Skill body — instructions for the agent.

Use $ARGUMENTS to insert the user-supplied arguments.
```

`name` and `description` are the key discovery fields. Current
btw-compatible skills place `argument-hint` under `metadata`; codeagent
reparses the file so the hint remains available even when the backend
omits non-core frontmatter. `allowed-tools` is retained as skill
metadata and does not bypass the central permission gate.

In the body, `$ARGUMENTS` expands to the complete argument string.
Available `$ARG1`, `$ARG2`, and later placeholders expand from
whitespace-separated tokens.

## Architecture and flow

codeagent uses btw for primary discovery/loading, adds compatibility
paths, and uses progressive disclosure: metadata enters the system
prompt, while the body is loaded on demand.

                        User types /name args
                                |
                                v
                       .preprocess_input()
            +-------------------+--------------------+
     recognized local command                 otherwise -> skill request
     (for example /compact)                         |
            |                                       v
     handled by REPL/Shiny                load_skill_prompt(name, args, cwd)
     (not sent as a skill prompt)                    ^
                                                     | use_skill tool call
     System prompt <- build_skill_hint()             |
     <available_skills> = name, description, hint    |
            |                                         |
            v                                         |
          model -- semantic match --> use_skill ------+  .make_skill_tool()
                                                     |
                                                     v
                 btw:::find_skill() + frontmatter body when available
                 otherwise read the discovered path and strip frontmatter
                                                     |
                                                     v
                           substitute $ARGUMENTS and $ARG1 ...
                                                     |
                                                     v
                           full body injected for the agent to follow

     Discovery and two-level metadata cache: list_skills_meta(cwd)

       in-memory .skill_cache, keyed by canonical cwd
            | miss or signature mismatch
            v
       on-disk <codeagent-config>/cache/skills/<cwd-key>.rds
            | miss, corruption, or signature mismatch
            v
       btw:::btw_skills_list()
         + btw built-ins, package, user, and native project directories
         + installed codeagent and Shiny package skills
         + cwd/.btw, .agents, .claude, and .codex skill directories
            |
            v
       named SkillMeta list -> best-effort atomic disk write + memory cache

The signature is the sum, across discovered directories, of each
directory’s recursive `SKILL.md` count plus file modification times.
This detects ordinary add/remove/edit changes. Cache I/O is best effort:
an absent, corrupt, or unwritable cache falls back to discovery rather
than breaking skill listing.

## Public signatures and defaults

``` r

list_skills_meta(cwd = getwd())

load_skill_prompt(name, args = "", cwd = getwd())

build_skill_hint(cwd = getwd(), max_tokens = 1000L)

install_ds_skills(
  skill = NULL,
  scope = c("user", "project"),
  overwrite = FALSE
)
```

[`build_skill_hint()`](https://kaipingyang.github.io/codeagent/reference/build_skill_hint.md)
truncates its generated metadata block to approximately `max_tokens * 4`
characters.
[`install_ds_skills()`](https://kaipingyang.github.io/codeagent/reference/install_ds_skills.md)
installs a curated Posit R/data-science set when `skill = NULL`, every
upstream skill for `"all"`, or the specified names; its default scope is
user-global.

## Skill discovery

``` r

# List all available skills
list_skills_meta()

# Load a skill prompt programmatically
load_skill_prompt("plan", args = "add feature X", cwd = getwd())
```
