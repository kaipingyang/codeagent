#!/usr/bin/env Rscript
# inst/examples/demo_03_skills.R
#
# Demo: progressive skill disclosure and skill invocation
#
# Skill system uses btw as backend (btw_skills_list() for discovery).
# Skill format: <name>/SKILL.md directories.
# Discovery: codeagent built-ins + btw skills + .claude/ + .codex/ + .codeagent/
#
# Two trigger paths:
#   1. User types /name  → .preprocess_input() injects full body
#   2. LLM semantic match → calls use_skill(name) tool automatically
#
# Run from package root: Rscript inst/examples/demo_03_skills.R

devtools::load_all(quiet = TRUE)

cat("=== Demo 3: Skills ===\n\n")

# --- Level 1: skill hint (name + description only, no body) ---
cat("--- Level 1: system prompt hint (metadata only, no body) ---\n")
hint <- build_skill_hint(max_tokens = 1000L)
cat(hint, "\n\n")

# --- Level 2: full skill body loaded on demand ---
cat("--- Level 2: full /plan skill body (loaded on demand) ---\n")
body <- load_skill_prompt("plan", args = "refactor the utils module")
cat(substr(body, 1, 400), "...\n\n")

# --- Invoke /plan via codeagent() (user /name trigger) ---
cat("--- Invoking /plan via codeagent() (user /name trigger) ---\n")
resp <- codeagent(
  "/plan refactor the utils module",
  model           = "gsds-gpt41",
  permission_mode = "bypass"
)
cat(resp, "\n\n")

# --- Invoke /compact (user /name trigger) ---
cat("--- Invoking /compact via codeagent() ---\n")
resp2 <- codeagent(
  "/compact",
  model           = "gsds-gpt41",
  permission_mode = "bypass"
)
cat(resp2, "\n\n")

# --- LLM semantic trigger demo ---
# Ask something that matches /verify without using /verify explicitly
cat("--- LLM semantic trigger: 'check if my code is correct' → use_skill(verify) ---\n")
resp3 <- codeagent(
  "Can you check if the last code I wrote is correct and complete?",
  model           = "gsds-gpt41",
  permission_mode = "bypass"
)
cat(resp3, "\n")
