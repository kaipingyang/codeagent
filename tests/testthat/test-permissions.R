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
  expect_equal(check_permission("WebFetch", "plan"), "deny")
})

test_that("network tools require approval by default and fail closed in dont_ask", {
  expect_equal(check_permission("WebFetch", "default"), "ask")
  expect_equal(check_permission("WebSearch", "default"), "ask")
  expect_equal(check_permission("WebFetch", "dont_ask"), "deny")
  expect_equal(check_permission("WebSearch", "dont_ask"), "deny")
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

test_that("default mode asks for all Bash commands", {
  allow_cmds <- c("ls -la", "cat README.md", "grep foo bar.R",
                  "git log --oneline", "git status", "echo hello")
  for (cmd in allow_cmds) {
    result <- check_permission("Bash", "default",
                               tool_input = list(command = cmd))
    expect_equal(result, "ask", info = paste("Command:", cmd))
  }
})

test_that("file permission rules match canonical paths, not traversal strings", {
  root <- withr::local_tempdir()
  allowed <- file.path(root, "allowed")
  dir.create(allowed)
  rule <- PermissionRule(
    "Write", "allow",
    rule_content = paste0(allowed, .Platform$file.sep, "*")
  )
  attack <- file.path(allowed, "..", "outside.txt")
  input <- list(file_path = attack, .permission_cwd = root)
  expect_false(codeagent:::.rule_matches(rule, "Write", input))
  expect_identical(
    check_permission("Write", "default", list(rule), input),
    "ask"
  )
})

test_that("path rules cover native, notebook, format, and btw file tools", {
  root <- withr::local_tempdir()
  denied <- file.path(root, "denied")
  dir.create(denied)
  cases <- list(
    LS = list(input = list(path = denied), pattern = denied),
    NotebookEdit = list(
      input = list(notebook_path = file.path(denied, "x.ipynb")),
      pattern = paste0(denied, .Platform$file.sep, "*")),
    Format = list(input = list(path = denied), pattern = denied),
    btw_tool_files_write = list(
      input = list(path = file.path(denied, "x.R")),
      pattern = paste0(denied, .Platform$file.sep, "*"))
  )
  for (name in names(cases)) {
    input <- codeagent:::.canonicalize_permission_input(
      name, cases[[name]]$input, root)
    input[[".permission_cwd"]] <- root
    rule <- PermissionRule(
      name, "deny", rule_content = cases[[name]]$pattern)
    expect_true(codeagent:::.rule_matches(rule, name, input), info = name)
  }
})

test_that("optional directory paths canonicalize to the captured cwd", {
  root <- codeagent:::.canonical_security_path(withr::local_tempdir())
  ls_input <- codeagent:::.canonicalize_permission_input("LS", list(), root)
  btw_input <- codeagent:::.canonicalize_permission_input(
    "btw_tool_files_list", list(path = NULL), root)
  expect_identical(ls_input$path, root)
  expect_identical(btw_input$path, root)
})

test_that("btw patch rules inspect every source and destination path", {
  root <- withr::local_tempdir()
  denied <- file.path(root, "denied")
  dir.create(denied)
  patch <- paste(
    "*** Begin Patch",
    "*** Add File: safe.txt",
    "+safe",
    "*** Update File: denied/out.txt",
    "@@",
    "-old",
    "+blocked",
    "*** Move to: denied/moved.txt",
    "*** End Patch",
    sep = "\n")
  input <- codeagent:::.canonicalize_permission_input(
    "btw_tool_files_patch", list(patch = patch), root)
  input[[".permission_cwd"]] <- root
  rule <- PermissionRule(
    "btw_tool_files_patch", "deny",
    rule_content = paste0(denied, .Platform$file.sep, "*"))
  expect_true(codeagent:::.rule_matches(
    rule, "btw_tool_files_patch", input))
})

test_that("btw patch ignores forged unified-diff markers in file content", {
  root <- withr::local_tempdir()
  denied <- file.path(root, "denied")
  dir.create(denied)
  patch <- paste(
    "*** Begin Patch",
    "*** Add File: denied/evil.txt",
    "++++ b/safe.txt",
    "*** End Patch",
    sep = "\n")
  input <- codeagent:::.canonicalize_permission_input(
    "btw_tool_files_patch", list(patch = patch), root)
  targets <- attr(input, "permission_targets")
  expect_true(any(grepl("denied/evil[.]txt$", targets)))
  expect_false(any(grepl("safe[.]txt$", targets)))
})

test_that("multi-target patch allow rules must cover every target", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "safe"))
  dir.create(file.path(root, "blocked"))
  patch <- paste(
    "*** Begin Patch",
    "*** Add File: safe/ok.txt",
    "+ok",
    "*** Add File: blocked/evil.txt",
    "+bad",
    "*** End Patch",
    sep = "\n")
  input <- codeagent:::.canonicalize_permission_input(
    "btw_tool_files_patch", list(patch = patch), root)
  input[[".permission_cwd"]] <- root
  allow <- PermissionRule(
    "btw_tool_files_patch", "allow",
    rule_content = paste0(file.path(root, "safe"), .Platform$file.sep, "*"))
  expect_false(codeagent:::.rule_matches(
    allow, "btw_tool_files_patch", input))
  expect_identical(check_permission(
    "btw_tool_files_patch", "default", list(allow), input), "ask")
})

test_that("explicit deny rules override earlier broad allow rules", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "safe"))
  dir.create(file.path(root, "denied"))
  patch <- paste(
    "*** Begin Patch",
    "*** Add File: safe/ok.txt",
    "+ok",
    "*** Add File: denied/evil.txt",
    "+bad",
    "*** End Patch",
    sep = "\n")
  input <- codeagent:::.canonicalize_permission_input(
    "btw_tool_files_patch", list(patch = patch), root)
  input[[".permission_cwd"]] <- root
  rules <- list(
    PermissionRule("btw_tool_files_patch", "allow", rule_content = "*"),
    PermissionRule(
      "btw_tool_files_patch", "deny",
      rule_content = paste0(file.path(root, "denied"),
                            .Platform$file.sep, "*"))
  )
  expect_identical(check_permission(
    "btw_tool_files_patch", "bypass", rules, input), "deny")
})

test_that("unextractable content deny rules fail closed", {
  rule <- PermissionRule("NotebookEdit", "deny", rule_content = "secret/*")
  expect_true(codeagent:::.rule_matches(
    rule, "NotebookEdit", list(.permission_cwd = getwd())))
})

test_that("glob matching treats regex metacharacters literally", {
  expect_true(codeagent:::.glob_match("safe.dir/*", "safe.dir/file.txt"))
  expect_false(codeagent:::.glob_match("safe.dir/*", "safeXdir/file.txt"))
  expect_true(codeagent:::.glob_match("dir[1]/*", "dir[1]/file.txt"))
  expect_false(codeagent:::.glob_match("dir[1]/*", "dir1/file.txt"))
})

test_that("path containment compares components instead of string prefixes", {
  root <- codeagent:::.canonical_security_path(withr::local_tempdir())
  sibling <- paste0(root, "-secret")
  dir.create(sibling)
  expect_false(codeagent:::.path_is_within(
    codeagent:::.canonical_security_path(sibling), root))
  child <- file.path(root, "child")
  dir.create(child)
  expect_true(codeagent:::.path_is_within(
    codeagent:::.canonical_security_path(child), root))
})

test_that("canonical missing paths resolve dangling symbolic links", {
  root <- withr::local_tempdir()
  outside <- tempfile("outside-")
  dir.create(outside)
  link <- file.path(root, "link")
  ok <- suppressWarnings(file.symlink(
    file.path(outside, "missing.txt"), link))
  if (!isTRUE(ok)) skip("symbolic links are unavailable")
  resolved <- codeagent:::.canonical_security_path(
    link, root, allow_missing = TRUE)
  expect_false(codeagent:::.path_is_within(resolved, root))
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

# ---------------------------------------------------------------------------
# Fine-grained rule_content matching (settings.json permissions.allow/deny)
# ---------------------------------------------------------------------------

test_that(".glob_match works for exact, wildcard, and empty patterns", {
  expect_true(codeagent:::.glob_match("npm run test", "npm run test"))
  expect_false(codeagent:::.glob_match("npm run test", "npm run lint"))
  expect_true(codeagent:::.glob_match("npm run *", "npm run test"))
  expect_true(codeagent:::.glob_match("npm run *", "npm run lint --fix"))
  expect_false(codeagent:::.glob_match("npm run *", "yarn run test"))
  expect_true(codeagent:::.glob_match("", "anything"))   # empty pattern = allow-all
  expect_true(codeagent:::.glob_match(NULL, "anything")) # NULL = allow-all
})

test_that(".rule_matches with rule_content matches Bash command", {
  rule_allow <- PermissionRule("Bash", "allow", rule_content = "npm run test *")
  rule_deny  <- PermissionRule("Bash", "deny",  rule_content = "rm -rf *")

  # Matching commands
  expect_true(codeagent:::.rule_matches(rule_allow, "Bash",
    tool_input = list(command = "npm run test foo")))
  expect_true(codeagent:::.rule_matches(rule_deny, "Bash",
    tool_input = list(command = "rm -rf /tmp/x")))

  # Non-matching commands
  expect_false(codeagent:::.rule_matches(rule_allow, "Bash",
    tool_input = list(command = "npm run lint")))
  expect_false(codeagent:::.rule_matches(rule_deny, "Bash",
    tool_input = list(command = "ls -la")))

  # Wrong tool name
  expect_false(codeagent:::.rule_matches(rule_allow, "Write",
    tool_input = list(command = "npm run test foo")))
})

test_that(".rule_matches with rule_content matches Read file path", {
  rule <- PermissionRule("Read", "allow", rule_content = "~/.zshrc")
  expect_true(codeagent:::.rule_matches(rule, "Read",
    tool_input = list(file_path = "~/.zshrc")))
  expect_false(codeagent:::.rule_matches(rule, "Read",
    tool_input = list(file_path = "~/.bashrc")))
})

test_that(".rule_matches content rule without tool_input returns FALSE", {
  rule <- PermissionRule("Bash", "allow", rule_content = "npm run test")
  expect_false(codeagent:::.rule_matches(rule, "Bash", tool_input = NULL))
})

test_that(".rule_matches tool-level rule (no rule_content) still matches without input", {
  rule <- PermissionRule("Write", "allow")  # no rule_content
  expect_true(codeagent:::.rule_matches(rule, "Write"))
  expect_true(codeagent:::.rule_matches(rule, "Write", tool_input = list(file_path = "x.R")))
  expect_false(codeagent:::.rule_matches(rule, "Read"))
})

test_that("check_permission respects fine-grained Bash allow rule", {
  rules <- list(PermissionRule("Bash", "allow", rule_content = "npm run test *"))
  # Matching command -> rule fires -> allow
  expect_equal(
    check_permission("Bash", "default", rules = rules,
                     tool_input = list(command = "npm run test --watch")),
    "allow"
  )
  # Non-matching command -> rule doesn't fire -> falls through to "ask"
  expect_equal(
    check_permission("Bash", "default", rules = rules,
                     tool_input = list(command = "rm -rf .")),
    "ask"
  )
})

test_that("check_permission respects fine-grained Bash deny rule", {
  rules <- list(PermissionRule("Bash", "deny", rule_content = "curl *"))
  expect_equal(
    check_permission("Bash", "bypass", rules = rules,
                     tool_input = list(command = "curl https://example.com")),
    "deny"
  )
  expect_equal(
    check_permission("Bash", "bypass", rules = rules,
                     tool_input = list(command = "ls -la")),
    "allow"
  )
})

test_that(".auto_classify_tool uses structured output + safe fallbacks (12E)", {
  # read-only tools short-circuit to allow (no model call)
  expect_identical(.auto_classify_tool("Read"), "allow")
  # structured decision is honoured
  testthat::local_mocked_bindings(.make_compact_chat = function(model, system_prompt = NULL)
    list(chat_structured = function(prompt, type)
      list(decision = if (grepl("rm -rf", prompt, fixed = TRUE)) "deny" else "allow")))
  expect_identical(.auto_classify_tool("Bash", list(command = "rm -rf /")), "deny")
  expect_identical(.auto_classify_tool("Bash", list(command = "ls")), "allow")
  # unexpected decision -> ask
  testthat::local_mocked_bindings(.make_compact_chat = function(model, system_prompt = NULL)
    list(chat_structured = function(prompt, type) list(decision = "maybe")))
  expect_identical(.auto_classify_tool("Bash", list(command = "x")), "ask")
  # classifier error -> ask (safe)
  testthat::local_mocked_bindings(.make_compact_chat = function(model, system_prompt = NULL)
    stop("boom"))
  expect_identical(.auto_classify_tool("Bash", list(command = "x")), "ask")
})
