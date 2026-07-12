---
# codeagent.md — project configuration for codeagent
#
# Single client:
#   client: openai/gpt-4.1
#
# Multiple clients with aliases:
client:
  gpt41:    openai/gpt-4.1
  gpt55:    openai/gpt-4o
  deepseek: openai/deepseek-r1

# btw tool groups to enable (docs, env, files, git, ide, pkg, cran, sessioninfo, web, agent)
btw_groups:
  - docs
  - env
  - git

# Permission mode: default, plan, accept_edits, bypass, dont_ask, auto, bubble
permission_mode: default

# Maximum agent loop turns
max_turns: 100
---

# Project Instructions

Follow these guidelines when working in this project:

- Use tidyverse patterns and native pipe `|>`
- Prefer `<-` for assignment
- Write tests for new functions
