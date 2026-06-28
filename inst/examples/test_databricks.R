#!/usr/bin/env Rscript
# inst/examples/test_databricks.R
#
# End-to-end smoke tests for codeagent with Databricks OpenAI-compatible endpoints.
# Tests gsds-gpt41, gsds-gpt-54, gsds-gpt-55 models.
# No ANTHROPIC_API_KEY needed.
#
# Prerequisites (set in ~/.Renviron or export in shell):
#   CODEAGENT_BASE_URL=https://adb-7234442748962802.2.azuredatabricks.net/serving-endpoints
#   CODEAGENT_API_KEY=<your-databricks-token>
#
# Run from the package root:
#   Rscript inst/examples/test_databricks.R

# ---------------------------------------------------------------------------
# Minimal test harness
# ---------------------------------------------------------------------------

.n_pass <- 0L
.n_fail <- 0L

ok <- function(cond, label) {
  if (isTRUE(cond)) {
    cat(sprintf("  \033[32mPASS\033[0m  %s\n", label))
    .n_pass <<- .n_pass + 1L
  } else {
    cat(sprintf("  \033[31mFAIL\033[0m  %s\n", label))
    .n_fail <<- .n_fail + 1L
  }
}

section <- function(title) cat(sprintf("\n\033[1m== %s ==\033[0m\n", title))
skip_section <- function(reason) cat(sprintf("  [SKIP] %s\n", reason))

# ---------------------------------------------------------------------------
# Load package
# ---------------------------------------------------------------------------

section("Load package")
if (file.exists("DESCRIPTION") && grepl("^Package: codeagent", readLines("DESCRIPTION", 1L))) {
  suppressMessages(devtools::load_all(quiet = TRUE))
} else {
  library(codeagent)
}
ok(isNamespaceLoaded("codeagent"), "codeagent namespace loaded")

# ---------------------------------------------------------------------------
# Check env vars
# ---------------------------------------------------------------------------

base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
api_key  <- Sys.getenv("CODEAGENT_API_KEY",  "")

if (!nzchar(base_url) || !nzchar(api_key)) {
  cat("\n[SKIP] CODEAGENT_BASE_URL or CODEAGENT_API_KEY not set.\n")
  cat("  Set them in ~/.Renviron and re-run.\n\n")
  cat(sprintf("=== Results: %d passed  %d failed (env missing) ===\n",
              .n_pass, .n_fail))
  quit(status = 0L)
}

cat(sprintf("  CODEAGENT_BASE_URL = %s\n", base_url))
cat(sprintf("  CODEAGENT_API_KEY  = %s***\n", substr(api_key, 1L, 6L)))

# ---------------------------------------------------------------------------
# A. Settings: CODEAGENT_BASE_URL picked up automatically
# ---------------------------------------------------------------------------

section("A. Settings -- CODEAGENT_BASE_URL auto-detection")

s <- codeagent:::load_settings(tempdir())
ok(!is.null(s$base_url) && nzchar(s$base_url),   "settings$base_url populated from env")
ok(identical(s$base_url, base_url),               "settings$base_url matches CODEAGENT_BASE_URL")

# ---------------------------------------------------------------------------
# B. codeagent_client() factory
# ---------------------------------------------------------------------------

section("B. codeagent_client() -- chat_openai_compatible branch")

chat_raw <- tryCatch(
  ellmer::chat_openai_compatible(
    base_url    = base_url,
    model       = "gsds-gpt41",
    credentials = function() api_key
  ),
  error = function(e) { cat("  [ERROR]", conditionMessage(e), "\n"); NULL }
)
ok(!is.null(chat_raw), "ellmer::chat_openai_compatible() returns non-NULL")

client_b <- tryCatch(
  codeagent:::codeagent_client(chat_raw, permission_mode = "bypass",
                                cwd = tempdir()),
  error = function(e) { cat("  [ERROR]", conditionMessage(e), "\n"); NULL }
)
ok(!is.null(client_b),                          "codeagent_client() returns non-NULL")
ok(inherits(client_b, "CodagentClient"),        "codeagent_client() returns CodagentClient")
ok(inherits(client_b$chat, "Chat"),             "client$chat is an ellmer Chat")
ok(is.list(client_b$settings),                  "client$settings is a list")

# ---------------------------------------------------------------------------
# C. One-shot query: three models
# ---------------------------------------------------------------------------

section("C. codeagent() one-shot -- gsds-gpt41 / gsds-gpt-54 / gsds-gpt-55")

models <- c("gsds-gpt41", "gsds-gpt-54", "gsds-gpt-55")

for (model in models) {
  # New style: explicit client
  chat_m <- ellmer::chat_openai_compatible(
    base_url    = base_url, model = model,
    credentials = function() api_key
  )
  cl_m <- codeagent:::codeagent_client(chat_m, permission_mode = "bypass",
                                        cwd = tempdir())
  resp <- tryCatch(
    codeagent:::codeagent(cl_m, "Reply with exactly the token DATABRICKS_OK and nothing else."),
    error = function(e) paste0("[Error] ", conditionMessage(e))
  )
  ok(is.character(resp) && !startsWith(resp, "[Error]"),
     sprintf("%s: no error", model))
  ok(grepl("DATABRICKS_OK", resp, fixed = TRUE),
     sprintf("%s: response contains DATABRICKS_OK", model))
}

# ---------------------------------------------------------------------------
# D. agent_loop() multi-turn with iteration and max_turns
# ---------------------------------------------------------------------------

section("D. agent_loop() multi-turn and max_turns enforcement")

chat_loop_raw <- ellmer::chat_openai_compatible(
  base_url    = base_url, model = "gsds-gpt41",
  credentials = function() api_key
)
client_loop <- codeagent:::codeagent_client(
  chat_loop_raw, permission_mode = "bypass",
  cwd = tempdir(), max_turns = 3L
)

result1 <- codeagent:::agent_loop("Say TURN1_OK", client_loop, iteration = 1L)
ok(identical(result1$stop_reason, "completed"), "turn 1: stop_reason = completed")
ok(grepl("TURN1_OK", result1$response),         "turn 1: response contains TURN1_OK")

result2 <- codeagent:::agent_loop("Say TURN2_OK", client_loop, iteration = 2L)
ok(identical(result2$stop_reason, "completed"), "turn 2: stop_reason = completed")

# iteration > max_turns → max_turns stop
result_over <- codeagent:::agent_loop("Say SHOULD_NOT_REACH", client_loop,
                                       iteration = 4L)   # > max_turns = 3
ok(identical(result_over$stop_reason, "max_turns"),
   "iteration > max_turns: stop_reason = max_turns")
ok(grepl("Max turns", result_over$response),
   "max_turns response mentions 'Max turns'")

# ---------------------------------------------------------------------------
# E. Skill system: progressive disclosure
# ---------------------------------------------------------------------------

section("E. Skills -- progressive disclosure (metadata-only hint, body on demand)")

metas <- codeagent:::list_skills_meta(cwd = tempdir())
ok(is.list(metas) && length(metas) > 0L,  "list_skills_meta returns non-empty list")

# Hint: XML format with name + description only, no body content
hint <- codeagent:::build_skill_hint(cwd = tempdir(), max_tokens = 1000L)
ok(is.character(hint) && nzchar(hint),     "build_skill_hint returns non-empty string")
ok(grepl("compact", hint),                 "hint mentions compact skill")
ok(grepl("plan",    hint),                 "hint mentions plan skill")
# Hint should not contain body content (progressive disclosure)
body_snippet <- "Only use read-only tools"   # from plan/SKILL.md body
ok(!grepl(body_snippet, hint),             "hint does not include skill body (progressive disclosure)")
# Hint should mention use_skill tool (LLM auto-trigger instruction)
ok(grepl("use_skill", hint),               "hint instructs LLM to use use_skill tool")

# Skill invocation via /compact in codeagent() one-shot
skill_resp <- tryCatch(
  codeagent:::codeagent(
    "/compact",
    model           = "gsds-gpt41",
    permission_mode = "bypass",
    cwd             = tempdir()
  ),
  error = function(e) paste0("[Error] ", conditionMessage(e))
)
ok(!startsWith(skill_resp, "[Error]"), "/compact skill invocation: no error")
ok(nzchar(skill_resp),                 "/compact skill invocation: non-empty response")

# ---------------------------------------------------------------------------
# F. Compaction: .make_compact_chat() uses OpenAI-compatible branch
# ---------------------------------------------------------------------------

section("F. Compaction -- .make_compact_chat() uses Databricks endpoint")

compact_chat <- tryCatch(
  codeagent:::.make_compact_chat("databricks-claude-haiku-4-5"),
  error = function(e) { cat("  [ERROR]", conditionMessage(e), "\n"); NULL }
)
ok(!is.null(compact_chat),                ".make_compact_chat() returns non-NULL")
ok(inherits(compact_chat, "Chat"),        ".make_compact_chat() returns ellmer Chat")

# Smoke-test a real compaction call
compact_resp <- tryCatch(
  compact_chat$chat("Summarise: user asked for file list, assistant ran ls, returned 3 files."),
  error = function(e) paste0("[Error] ", conditionMessage(e))
)
ok(is.character(compact_resp) && !startsWith(compact_resp, "[Error]"),
   ".make_compact_chat() can make a real API call")

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

cat(sprintf(
  "\n\033[1m=== Results: %d passed  %d failed ===\033[0m\n",
  .n_pass, .n_fail
))
if (.n_fail > 0L) {
  cat("\033[31mSome tests FAILED -- check output above.\033[0m\n")
  quit(status = 1L)
} else {
  cat("\033[32mAll tests passed.\033[0m\n")
}
