---
name: plan
description: Enter planning mode — read-only analysis and step-by-step implementation plan
argument-hint: "<task description>"
allowed-tools:
  - Read
  - Glob
  - Grep
  - LS
---

Enter planning mode. In this mode:
- Only use read-only tools (Read, Glob, Grep, LS)
- Do NOT make any changes to files
- Analyse the codebase thoroughly before proposing changes

Task to plan: $ARGUMENTS

Produce a structured implementation plan with:
1. **Goal** -- What needs to be achieved
2. **Exploration** -- What files / code you examined
3. **Approach** -- The strategy and why
4. **Steps** -- Numbered list of concrete implementation steps
5. **Risks** -- Potential issues and mitigations
6. **Estimated scope** -- Files to change, lines of code

End with: "Ready to implement. Type /go to proceed."
