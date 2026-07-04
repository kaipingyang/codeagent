# Tests for new features added in Batch 1+2

# ---------------------------------------------------------------------------
# Permission modes — bubble
# ---------------------------------------------------------------------------

test_that("bubble mode returns 'ask' for write tools", {
  expect_equal(check_permission("Write", "bubble"), "ask")
  expect_equal(check_permission("Bash",  "bubble"), "ask")
  expect_equal(check_permission("Edit",  "bubble"), "ask")
})

test_that("bubble mode returns 'ask' even for read-only tools", {
  # bubble always asks (passes to parent), even for reads
  expect_equal(check_permission("Read", "bubble"), "ask")
  expect_equal(check_permission("Glob", "bubble"), "ask")
})

test_that("PermissionMode includes bubble", {
  expect_true("bubble" %in% unlist(PermissionMode))
  expect_equal(PermissionMode$BUBBLE, "bubble")
})

# ---------------------------------------------------------------------------
# HookEvent constants + HookRegistry new events
# ---------------------------------------------------------------------------

test_that("HookEvent has all 7 event types", {
  expected <- c("PreToolUse", "PostToolUse", "PostToolUseFailure",
                "PermissionDenied", "PermissionRequest",
                "UserMessage", "AssistantMessage")
  for (e in expected)
    expect_true(e %in% unlist(HookEvent), info = paste("Missing:", e))
})

test_that("HookRegistry register() accepts valid events", {
  reg <- HookRegistry$new()
  expect_no_error(
    reg$register(HookEvent$USER_MESSAGE, function(msg) NULL)
  )
  expect_equal(reg$count(), 1L)
})

test_that("HookRegistry register() rejects unknown events", {
  reg <- HookRegistry$new()
  expect_error(
    reg$register("UnknownEvent", function(msg) NULL),
    "Unknown event"
  )
})

test_that("HookRegistry run_user_message fires callback", {
  reg <- HookRegistry$new()
  received <- NULL
  reg$register(HookEvent$USER_MESSAGE, function(msg) { received <<- msg })
  reg$run_user_message("hello")
  expect_equal(received, "hello")
})

test_that("HookRegistry run_assistant_message fires callback", {
  reg <- HookRegistry$new()
  received <- NULL
  reg$register(HookEvent$ASSISTANT_MESSAGE, function(msg) { received <<- msg })
  reg$run_assistant_message("world")
  expect_equal(received, "world")
})

test_that("HookRegistry run_failure fires callback", {
  reg <- HookRegistry$new()
  called <- FALSE
  reg$register(HookEvent$POST_TOOL_USE_FAILURE,
               function(name, input, err) { called <<- TRUE })
  reg$run_failure("Bash", list(), "timeout")
  expect_true(called)
})

test_that("HookRegistry run_permission_denied fires callback", {
  reg <- HookRegistry$new()
  denied_tool <- NULL
  reg$register(HookEvent$PERMISSION_DENIED,
               function(name, input, mode) { denied_tool <<- name })
  reg$run_permission_denied("Write", list(file_path = "/tmp/x"), "plan")
  expect_equal(denied_tool, "Write")
})

test_that("HookRegistry run_permission_request can grant/deny", {
  reg <- HookRegistry$new()
  reg$register(HookEvent$PERMISSION_REQUEST,
               function(name, input, mode) list(action = "allow"))
  result <- reg$run_permission_request("Write", list(), "bubble")
  expect_equal(result, "allow")
})

test_that("HookRegistry run_permission_request returns NULL when no hooks", {
  reg <- HookRegistry$new()
  result <- reg$run_permission_request("Write", list(), "bubble")
  expect_null(result)
})

test_that("HookRegistry legacy register_pre/register_post still work", {
  reg <- HookRegistry$new()
  reg$register_pre(function(n, i) list(action = "allow"))
  reg$register_post(function(n, i, o) list(action = "allow"))
  expect_equal(reg$count(), 2L)

  pre  <- reg$run_pre("Bash", list(command = "ls"))
  post <- reg$run_post("Bash", list(), "output")
  expect_equal(pre$action,  "allow")
  expect_equal(post,        "output")
})

test_that("HookRegistry clear() removes all hooks", {
  reg <- HookRegistry$new()
  reg$register(HookEvent$USER_MESSAGE, function(m) NULL)
  reg$register(HookEvent$ASSISTANT_MESSAGE, function(m) NULL)
  expect_equal(reg$count(), 2L)
  reg$clear()
  expect_equal(reg$count(), 0L)
})

# ---------------------------------------------------------------------------
# Compaction — L5 context_collapse
# ---------------------------------------------------------------------------

test_that("context_collapse truncates large ContentToolResult values", {
  skip_if_not_installed("ellmer")
  chat <- tryCatch(
    ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001",
                            system_prompt = "test"),
    error = function(e) NULL
  )
  if (is.null(chat)) skip("ellmer not available")

  # Inject a large tool result
  big_value <- paste(rep("x", 1000L), collapse = "")
  tool_req   <- ellmer::ContentToolRequest(name = "Bash", id = "r1",
                                            arguments = list(command = "ls"))
  tool_result <- ellmer::ContentToolResult(value = big_value,
                                            request = tool_req)
  user_turn  <- ellmer::Turn("user",      list(ellmer::ContentText("test")))
  asst_turn  <- ellmer::Turn("assistant", list(tool_req))
  tool_turn  <- ellmer::Turn("user",      list(tool_result))
  tryCatch(chat$set_turns(list(user_turn, asst_turn, tool_turn)),
           error = function(e) skip("set_turns not available"))

  context_collapse(chat, max_chars = 100L)

  turns    <- chat$get_turns()
  contents <- turns[[3L]]@contents
  val      <- as.character(contents[[1L]]@value)
  expect_lte(nchar(val), 200L)
  expect_match(val, "collapsed")
})

# ---------------------------------------------------------------------------
# Error classification helpers
# ---------------------------------------------------------------------------

test_that(".ERR_PTL matches prompt_too_long messages", {
  expect_true(grepl(codeagent:::.ERR_PTL, "413 error", ignore.case = TRUE))
  expect_true(grepl(codeagent:::.ERR_PTL, "prompt_too_long", ignore.case = TRUE))
  expect_false(grepl(codeagent:::.ERR_PTL, "rate limit exceeded", ignore.case = TRUE))
})

test_that(".ERR_RATE_LIMIT matches 429 messages", {
  expect_true(grepl(codeagent:::.ERR_RATE_LIMIT, "429 too many requests",
                    ignore.case = TRUE))
  expect_true(grepl(codeagent:::.ERR_RATE_LIMIT, "rate limit exceeded",
                    ignore.case = TRUE))
})

test_that(".ERR_AUTH matches 401/403 messages", {
  expect_true(grepl(codeagent:::.ERR_AUTH, "401 unauthorized", ignore.case = TRUE))
  expect_true(grepl(codeagent:::.ERR_AUTH, "invalid api key", ignore.case = TRUE))
})

# ---------------------------------------------------------------------------
# system-reminder
# ---------------------------------------------------------------------------

test_that(".build_system_reminder returns XML block", {
  reminder <- codeagent:::.build_system_reminder(list(), iteration = 5L,
                                                  cwd = "/tmp/test")
  expect_match(reminder, "<system-reminder>")
  expect_match(reminder, "iteration: 5")
  expect_match(reminder, "/tmp/test")
  expect_match(reminder, "</system-reminder>")
})

test_that(".build_system_reminder includes current date", {
  reminder <- codeagent:::.build_system_reminder(list())
  expect_match(reminder, format(Sys.Date(), "%Y-%m-%d"))
})

# ---------------------------------------------------------------------------
# .BTW_GROUPS completeness
# ---------------------------------------------------------------------------

test_that(".BTW_GROUPS covers all 10 expected groups", {
  expected <- c("agent", "cran", "docs", "env", "files", "git",
                "ide", "pkg", "sessioninfo", "web")
  for (g in expected)
    expect_true(g %in% names(codeagent:::.BTW_GROUPS),
                info = paste("Missing group:", g))
})

# ---------------------------------------------------------------------------
# verify_r_tests factory
# ---------------------------------------------------------------------------

test_that("verify_r_tests() returns a function", {
  fn <- verify_r_tests()
  expect_true(is.function(fn))
})

test_that("verify_r_tests() passes when devtools not available", {
  fn <- verify_r_tests()
  # If devtools is not installed, should pass through
  if (!requireNamespace("devtools", quietly = TRUE)) {
    result <- fn("response", NULL, tempdir())
    expect_true(result$passed)
  } else {
    skip("devtools available — skip pass-through test")
  }
})

# ---------------------------------------------------------------------------
# Shiny UI helpers
# ---------------------------------------------------------------------------

test_that("chat_codeagent_ui includes upload, voice, and skill picker controls", {
  sm <- data.frame(key = "plan", label = "/plan", desc = "x",
                   stringsAsFactors = FALSE)
  html <- as.character(chat_codeagent_ui(sm))

  expect_match(html, "ca_upload_local_btn")
  expect_match(html, "ca_voice_btn")
  expect_match(html, "ca_server_btn")
  # Skill pickerInput was replaced by shinychat's slash-command typeahead; the
  # footer now shows a hint instead of a picker (see .skill_picker_footer).
  expect_match(html, "Type / for commands")
  expect_match(html, "ca_file_hidden")
})

test_that("head_assets includes styles.css, agent.js, and inlined voice JS", {
  html <- as.character(htmltools::renderTags(head_assets())$head)

  expect_true(grepl("codeagent-www/styles.css", html, fixed = TRUE))
  expect_true(grepl("codeagent-www/agent.js", html, fixed = TRUE))
  # voice.js is inlined (not a src reference) so its handlers survive footer render
  expect_true(grepl("SpeechRecognition", html, fixed = TRUE))
  expect_false(grepl("data-theme", html, fixed = TRUE))
})

test_that("sidebar Sessions row uses plain actionButtons (no toolbar)", {
  f <- test_path("..", "..", "R", "ui_panels.R")
  skip_if_not(file.exists(f), "source tree only (skipped in R CMD check)")
  src <- paste(readLines(f), collapse = "\n")
  expect_true(grepl('actionButton\\("new_session"', src))
  expect_true(grepl('actionButton\\("delete_session_btn"', src))
})

test_that("skills use shinychat native input update", {
  f <- test_path("..", "..", "R", "server_skills.R")
  skip_if_not(file.exists(f), "source tree only (skipped in R CMD check)")
  src <- paste(readLines(f), collapse = "\n")
  expect_true(grepl("shinychat::update_chat_user_input", src, fixed = TRUE))
})

test_that("styles.css carries no theme variables or data-theme overrides", {
  css_path <- system.file("www", "styles.css", package = "codeagent")
  if (!nzchar(css_path) || !file.exists(css_path))
    css_path <- test_path("..", "..", "inst", "www", "styles.css")
  skip_if_not(file.exists(css_path), "styles.css not found")
  css <- paste(readLines(css_path), collapse = "\n")
  expect_false(grepl("data-theme", css, fixed = TRUE))
  expect_false(grepl("--ca-accent", css, fixed = TRUE))
  expect_false(grepl("glassmorphism", css, fixed = TRUE))
})

test_that("server_chat isolates shared state access inside ExtendedTask", {
  f <- test_path("..", "..", "R", "server_chat.R")
  skip_if_not(file.exists(f), "source tree only (skipped in R CMD check)")
  src <- paste(readLines(f), collapse = "\n")
  expect_match(src, "shiny::isolate\\(state\\$compaction_ctrl\\$maybe_compact")
  expect_match(src, "shiny::isolate\\(state\\$resource_state\\$maybe_replace")
})

# ---------------------------------------------------------------------------
# Worktree helpers (mock — no real git needed for unit tests)
# ---------------------------------------------------------------------------

test_that(".create_worktree returns NULL when not in a git repo", {
  # Use a temp dir that is not a git repo
  tmp <- tempfile("no-git-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  result <- codeagent:::.create_worktree(base_dir = tmp)
  expect_null(result)
})

test_that(".cleanup_worktree silently handles NULL path", {
  expect_no_error(codeagent:::.cleanup_worktree(NULL))
})

test_that(".cleanup_worktree silently handles nonexistent path", {
  expect_no_error(codeagent:::.cleanup_worktree("/tmp/nonexistent-wt-xyz"))
})
