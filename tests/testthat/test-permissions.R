test_that("bypass mode allows everything", {
  for (tool in c("Bash", "Read", "Write", "Edit", "MultiEdit", "Glob", "Grep")) {
    expect_equal(check_permission(tool, "bypass"), "allow",
                 info = paste("Tool:", tool))
  }
})

test_that("dont_ask mode denies non-readonly tools", {
  expect_equal(check_permission("Bash",  "dont_ask"), "deny")
  expect_equal(check_permission("Write", "dont_ask"), "deny")
  # Read-only tools are still allowed
  expect_equal(check_permission("Read",  "dont_ask"), "allow")
  expect_equal(check_permission("Glob",  "dont_ask"), "allow")
})

test_that("plan mode blocks write/bash but allows read-only tools", {
  expect_equal(check_permission("Bash",     "plan"), "deny")
  expect_equal(check_permission("Write",    "plan"), "deny")
  expect_equal(check_permission("Edit",     "plan"), "deny")
  expect_equal(check_permission("Read",     "plan"), "allow")
  expect_equal(check_permission("Glob",     "plan"), "allow")
  expect_equal(check_permission("Grep",     "plan"), "allow")
  expect_equal(check_permission("WebFetch", "plan"), "allow")
})

test_that("accept_edits mode allows file edits but asks for Bash", {
  expect_equal(check_permission("Edit",      "accept_edits"), "allow")
  expect_equal(check_permission("Write",     "accept_edits"), "allow")
  expect_equal(check_permission("MultiEdit", "accept_edits"), "allow")
  expect_equal(check_permission("Bash",      "accept_edits"), "ask")
})

test_that("default mode asks for write/bash, allows read-only", {
  expect_equal(check_permission("Read",  "default"), "allow")
  expect_equal(check_permission("Glob",  "default"), "allow")
  expect_equal(check_permission("Write", "default"), "ask")
  expect_equal(check_permission("Edit",  "default"), "ask")
})

test_that("default mode auto-allows bash readonly commands", {
  allow_cmds <- c("ls -la", "cat README.md", "grep foo bar.R",
                  "git log --oneline", "git status", "echo hello")
  for (cmd in allow_cmds) {
    result <- check_permission("Bash", "default",
                               tool_input = list(command = cmd))
    expect_equal(result, "allow", info = paste("Command:", cmd))
  }
})

test_that("default mode asks for bash write commands", {
  write_cmds <- c("rm -rf /tmp/test", "touch newfile.txt",
                  "mkdir newdir", "npm install")
  for (cmd in write_cmds) {
    result <- check_permission("Bash", "default",
                               tool_input = list(command = cmd))
    expect_equal(result, "ask", info = paste("Command:", cmd))
  }
})

test_that(".rule_matches handles exact, wildcard, and catch-all patterns", {
  rule_exact <- PermissionRule(tool_name = "Bash",    behavior = "allow")
  rule_wild  <- PermissionRule(tool_name = "Bash:*",  behavior = "deny")
  rule_all   <- PermissionRule(tool_name = "*",       behavior = "allow")

  expect_true(codeagent:::.rule_matches(rule_exact, "Bash"))
  expect_false(codeagent:::.rule_matches(rule_exact, "Write"))
  expect_true(codeagent:::.rule_matches(rule_all,   "anything"))

  # Wildcard pattern "Bash:*" should match "Bash:readonly"
  expect_true(codeagent:::.rule_matches(rule_wild, "Bash:readonly"))
  expect_false(codeagent:::.rule_matches(rule_wild, "Write"))
})

test_that("user rules take priority over default mode but not plan mode", {
  rules <- list(PermissionRule(tool_name = "Write", behavior = "allow"))
  # In default mode, user rules override
  expect_equal(check_permission("Write", "default", rules = rules), "allow")
  # Plan mode is enforced before rules are checked
  expect_equal(check_permission("Write", "plan", rules = rules), "deny")
})

test_that(".is_bash_readonly correctly identifies readonly commands", {
  expect_true(codeagent:::.is_bash_readonly("ls -la"))
  expect_true(codeagent:::.is_bash_readonly("cat README.md"))
  expect_true(codeagent:::.is_bash_readonly("  git log --oneline -5"))
  expect_true(codeagent:::.is_bash_readonly("grep -r pattern ."))
  expect_true(codeagent:::.is_bash_readonly("rg 'foo' src/"))
  expect_false(codeagent:::.is_bash_readonly("rm -rf /tmp"))
  expect_false(codeagent:::.is_bash_readonly("touch newfile"))
  expect_false(codeagent:::.is_bash_readonly("npm install"))
  expect_false(codeagent:::.is_bash_readonly(""))
})

test_that("DenialTracker emits warnings at correct thresholds", {
  tracker <- DenialTracker$new()

  # No warning before threshold
  expect_no_warning(for (i in seq_len(2L)) tracker$record_denial())

  # Warning at consecutive threshold
  expect_warning(tracker$record_denial(), "consecutive")

  # record_success resets consecutive counter
  tracker$record_success()
  expect_equal(tracker$counts()$consecutive, 0L)

  # Total count is not reset by record_success
  expect_gt(tracker$counts()$total, 0L)
})
