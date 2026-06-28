#!/usr/bin/env Rscript
# inst/examples/test_shiny_app.R
#
# Shiny app smoke test: static structure checks + interactive test checklist.
#
# Run from the package root:
#   Rscript inst/examples/test_shiny_app.R           # structure checks only
#   LAUNCH=1 Rscript inst/examples/test_shiny_app.R  # checks + launch app
# Or inside RStudio:
#   source("inst/examples/02_shiny_app_test.R")         # auto-launches if API key set
#
# Requires ANTHROPIC_API_KEY to launch the app.

# ---------------------------------------------------------------------------
# Test harness (same as 01_non_shiny_test.R)
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

section <- function(title) {
  cat(sprintf("\n\033[1m== %s ==\033[0m\n", title))
}

# ---------------------------------------------------------------------------
# Load package
# ---------------------------------------------------------------------------

section("Load package")
if (file.exists("DESCRIPTION") && grepl("^Package: codeagent", readLines("DESCRIPTION", 1L))) {
  suppressMessages(devtools::load_all(quiet = TRUE))
} else {
  library(codeagent)
}
existsFunction <- function(f) is.function(tryCatch(
  get(f, envir = asNamespace("codeagent")), error = function(e) NULL))

ok(isNamespaceLoaded("codeagent"), "codeagent namespace loaded")
ok(existsFunction("codeagent_app"), "codeagent_app() is exported")

# ---------------------------------------------------------------------------
# A. Static structure checks (no API key needed)
# ---------------------------------------------------------------------------

section("A. Static UI/server structure checks")

# Verify all expected exported symbols exist
exports <- getNamespaceExports("codeagent")
for (fn in c("codeagent_app", "codeagent", "query_loop",
             "list_sessions", "save_session", "get_session_messages",
             "rename_session", "tag_session", "fork_session",
             "delete_session", "migrate_sessions",
             "list_skills_meta", "build_skill_hint", "load_skill_prompt",
             "load_settings", "save_user_settings",
             "HookRegistry", "BudgetTracker",
             "CompactionController", "ContentReplacementState",
             "StreamingToolExecutor",
             "PermissionRule", "PermissionMode")) {
  ok(fn %in% exports, paste0("exported: ", fn))
}

# Verify PermissionMode values
pm <- codeagent:::PermissionMode
ok(is.list(pm) || is.character(pm),             "PermissionMode is defined")
expected_modes <- c("default", "plan", "accept_edits", "bypass", "dont_ask", "auto")
for (m in expected_modes) {
  ok(m %in% unlist(pm), paste0("PermissionMode includes '", m, "'"))
}

# Verify inst/www assets exist (required for Shiny)
www <- system.file("www", package = "codeagent")
ok(nzchar(www) && dir.exists(www),              "inst/www directory exists")
ok(file.exists(file.path(www, "styles.css")),   "inst/www/styles.css exists")
ok(file.exists(file.path(www, "agent.js")),     "inst/www/agent.js exists")

# Verify inst/skills built-ins exist (new format: subdirectories with SKILL.md)
skills_dir <- system.file("skills", package = "codeagent")
ok(nzchar(skills_dir) && dir.exists(skills_dir), "inst/skills directory exists")
skill_dirs <- list.dirs(skills_dir, full.names = FALSE, recursive = FALSE)
ok(length(skill_dirs) >= 3L,                   "at least 3 built-in skill directories present")
for (expected in c("compact", "plan")) {
  ok(expected %in% skill_dirs, paste0("built-in skill dir: ", expected))
  ok(file.exists(file.path(skills_dir, expected, "SKILL.md")),
     paste0("built-in skill has SKILL.md: ", expected))
}

# codeagent_app() with launch.browser=FALSE returns a shiny.appobj
# (this does NOT open a browser; requires the API key to be set in env
#  so that ellmer::chat_anthropic() can be constructed)
api_key <- Sys.getenv("ANTHROPIC_API_KEY", "")
app_obj <- NULL

if (!nzchar(api_key)) {
  cat("  [SKIP] ANTHROPIC_API_KEY not set; skipping app object construction test\n")
} else {
  app_obj <- tryCatch(
    codeagent_app(permission_mode = "bypass", launch.browser = FALSE),
    error = function(e) {
      cat(sprintf("  [ERROR] codeagent_app() failed: %s\n", conditionMessage(e)))
      NULL
    }
  )
  ok(!is.null(app_obj),                         "codeagent_app() returns without error")
  ok(inherits(app_obj, "shiny.appobj"),          "return value is a shiny.appobj")
  ok(is.function(app_obj$server),               "shiny app has a server function")
  ok(!is.null(app_obj$ui),                      "shiny app has a ui component")
}

# ---------------------------------------------------------------------------
# B. Manual test checklist (printed for the tester to follow)
# ---------------------------------------------------------------------------

section("B. Manual test checklist (launch the app and verify each item)")

checklist <- c(
  "",
  "  Launch with:  codeagent_app(permission_mode = 'bypass')",
  "  (or:          LAUNCH=1 Rscript inst/examples/02_shiny_app_test.R)",
  "",
  "  CORE CHAT",
  "  [ ] App opens in browser without JS errors in the console",
  "  [ ] Sidebar shows: token budget, permission mode selector, session buttons",
  "  [ ] Type 'Hello, please reply with OK' -- response streams in",
  "  [ ] Token budget counter in sidebar updates after the response",
  "",
  "  ESC INTERRUPT",
  "  [ ] Type a long prompt ('Write a 500-word essay on recursion')",
  "  [ ] Press ESC while streaming -- output stops mid-sentence",
  "  [ ] Subsequent message still works normally",
  "",
  "  PERMISSION MODE",
  "  [ ] Switch selector to 'plan'",
  "  [ ] Ask 'Create a file called test.txt' -- should be denied",
  "  [ ] Ask 'List files in the current directory' -- should work (ls)",
  "  [ ] Switch back to 'bypass' -- all tools work again",
  "",
  "  SKILL INVOCATION",
  "  [ ] Type '/compact' -- skill prompt is injected and model responds",
  "  [ ] Type '/plan refactor the utils module' -- plan skill fires with args",
  "  [ ] Type '/no-such-skill' -- graceful fallback (prompt sent as-is)",
  "",
  "  SESSION SAVE / LOAD",
  "  [ ] Click 'Save session' -- notification appears with truncated UUID",
  "  [ ] Reload the browser tab -- session list appears in sidebar",
  "  [ ] Click the saved session button -- conversation replays in chat",
  "  [ ] Token budget updates to reflect the loaded session size",
  "",
  "  NEW SESSION",
  "  [ ] Click 'New session' -- chat is cleared",
  "  [ ] Token budget resets to 0",
  "  [ ] A fresh message gets a fresh response (no memory of old chat)",
  "",
  "  MULTI-TURN TOOL USE (bypass mode)",
  "  [ ] Ask 'List all .R files in R/' -- Glob or Bash tool is invoked",
  "  [ ] Ask 'Read R/utils.R and tell me how many lines it has' -- Read tool used",
  "  [ ] Confirm tool calls are logged in the R console",
  "",
  "  ACCEPT_EDITS MODE",
  "  [ ] Switch to 'accept_edits'",
  "  [ ] Ask 'Append a comment to R/utils.R' -- Edit tool is approved",
  "  [ ] Ask 'Run: date' via Bash -- should be denied (non-readonly)",
  "  [ ] Switch back to 'bypass'",
  "",
  "  CONTEXT COMPACTION (long session)",
  "  [ ] Have a long multi-turn conversation (10+ exchanges with tool use)",
  "  [ ] Observe console for '[codeagent] L1 compaction triggered' messages",
  "  [ ] App continues working after compaction (no crash)",
  "",
  "  STATIC ASSETS",
  "  [ ] Open browser DevTools > Network -- styles.css and agent.js load (200)",
  "  [ ] Token budget bar changes colour at high usage (orange/red CSS classes)",
  ""
)
cat(paste(checklist, collapse = "\n"))

# ---------------------------------------------------------------------------
# Summary of structural checks
# ---------------------------------------------------------------------------

cat(sprintf(
  "\n\033[1m=== Structural checks: %d passed  %d failed ===\033[0m\n",
  .n_pass, .n_fail
))
if (.n_fail > 0L) {
  cat("\033[31mStructural checks FAILED -- fix before manual testing.\033[0m\n")
}

# ---------------------------------------------------------------------------
# Optional launch
# ---------------------------------------------------------------------------

launch <- identical(Sys.getenv("LAUNCH", ""), "1") ||
          (interactive() && nzchar(api_key))

if (launch) {
  if (!nzchar(api_key)) {
    cat("\n[SKIP] Cannot launch: ANTHROPIC_API_KEY not set.\n")
  } else {
    cat("\n\033[1mLaunching codeagent_app() in default browser...\033[0m\n")
    cat("Press Ctrl-C in the terminal (or stop the R process) to quit.\n\n")
    codeagent_app(permission_mode = "bypass")
  }
} else if (!interactive()) {
  cat("\nTo launch the app, re-run with:  LAUNCH=1 Rscript inst/examples/02_shiny_app_test.R\n")
}
