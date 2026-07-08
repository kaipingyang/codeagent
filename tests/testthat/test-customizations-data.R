test_that(".extract_yaml_field parses quoted + unquoted values", {
  lines <- c("---", "name: my-agent", "description: 'Does things'",
             'model: "gpt-4o"', "---")
  expect_equal(codeagent:::.extract_yaml_field(lines, "name"), "my-agent")
  expect_equal(codeagent:::.extract_yaml_field(lines, "description"), "Does things")
  expect_equal(codeagent:::.extract_yaml_field(lines, "model"), "gpt-4o")
  expect_null(codeagent:::.extract_yaml_field(lines, "missing"))
})

test_that(".load_agents discovers .md agents and parses front matter", {
  withr::local_envvar(HOME = withr::local_tempdir())   # isolate ~/.claude/agents
  cwd <- withr::local_tempdir()
  d   <- file.path(cwd, ".claude", "agents")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("---", "description: A reviewer", "model: gpt-4o", "---", "body"),
             file.path(d, "reviewer.md"))
  writeLines(c("---", "description: A planner", "---"),
             file.path(d, "planner.md"))

  agents <- codeagent:::.load_agents(cwd)
  expect_length(agents, 2L)
  names <- vapply(agents, function(a) a$name, character(1))
  expect_setequal(names, c("reviewer", "planner"))
  rev <- Filter(function(a) a$name == "reviewer", agents)[[1]]
  expect_equal(rev$description, "A reviewer")
  expect_equal(rev$model, "gpt-4o")
})

test_that(".load_agents returns empty when no agent dirs exist", {
  withr::local_envvar(HOME = withr::local_tempdir())   # isolate ~/.claude/agents
  cwd <- withr::local_tempdir()
  expect_equal(codeagent:::.load_agents(cwd), list())
})

test_that(".load_mcp_servers reads mcp.json into server records", {
  cwd <- withr::local_tempdir()
  jsonlite::write_json(
    list(mcpServers = list(
      fs  = list(command = "npx", args = list("-y", "server-fs")),
      web = list(url = "http://localhost:3000")
    )),
    file.path(cwd, "mcp.json"), auto_unbox = TRUE)

  servers <- codeagent:::.load_mcp_servers(cwd)
  expect_length(servers, 2L)
  fs <- Filter(function(s) s$name == "fs", servers)[[1]]
  expect_equal(fs$command, "npx -y server-fs")
  web <- Filter(function(s) s$name == "web", servers)[[1]]
  expect_equal(web$url, "http://localhost:3000")
})

test_that(".load_mcp_servers is empty for missing/invalid config", {
  cwd <- withr::local_tempdir()
  expect_equal(codeagent:::.load_mcp_servers(cwd), list())
  writeLines("not json {", file.path(cwd, "mcp.json"))
  expect_equal(codeagent:::.load_mcp_servers(cwd), list())
})

test_that(".load_instructions finds existing instruction files only", {
  withr::local_envvar(HOME = withr::local_tempdir())   # isolate ~/.claude/CLAUDE.md
  cwd <- withr::local_tempdir()
  writeLines("# Project rules", file.path(cwd, "CLAUDE.md"))

  ins <- codeagent:::.load_instructions(cwd)
  expect_true(length(ins) >= 1L)
  paths <- vapply(ins, function(i) i$path, character(1))
  expect_true(any(grepl("CLAUDE.md$", paths)))
  expect_true(all(vapply(ins, function(i) isTRUE(i$active), logical(1))))
})

test_that(".reset_session_state resets slots + controllers on a stub state", {
  st <- new.env(parent = emptyenv())
  st$session_id      <- "old-id"
  st$iteration       <- 7L
  st$main_output     <- list(title = "x")
  st$compaction_ctrl <- CompactionController$new()
  st$resource_state  <- ContentReplacementState$new()
  st$budget_tracker  <- BudgetTracker$new()

  codeagent:::.reset_session_state(st)

  expect_equal(st$iteration, 0L)
  expect_null(st$main_output)
  expect_false(identical(st$session_id, "old-id"))
  expect_true(nzchar(st$session_id))
})
