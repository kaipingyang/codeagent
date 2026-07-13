# btw task reuse (skill / README / project-context creation)

codeagent reuses btw's task + agent helpers instead of reinventing them.
btw exposes each task in several modes; `mode = "tool"` returns an
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html) the
agent can call, `mode = "console"` runs an interactive guided task. See
`btw::btw_task*`.
