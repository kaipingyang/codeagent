# tests/testthat/test-p2.R
# Tests for P2 features: TodoWrite, sandbox, team, worktree cleanup,
# subagent sidechain persistence, MCP server transport.

library(ellmer)

# ---------------------------------------------------------------------------
# TodoWrite
# ---------------------------------------------------------------------------

test_that(".render_todos renders checkboxes by status", {
  items <- list(
    list(content = "a", status = "completed"),
    list(content = "b", status = "in_progress", active_form = "Doing b"),
    list(content = "c", status = "pending")
  )
  md <- codeagent:::.render_todos(items)
  expect_true(grepl("\\[x\\] a", md))
  expect_true(grepl("\\[~\\] b", md))
  expect_true(grepl("Doing b", md))
  expect_true(grepl("\\[ \\] c", md))
})

test_that(".render_todos handles empty list", {
  expect_match(codeagent:::.render_todos(list()), "no todos")
})

test_that("todo_write_tool writes and read_todos reads back", {
  sid <- paste0("test_", as.integer(Sys.time()))
  on.exit(unlink(codeagent:::.todo_path(sid)), add = TRUE)
  t <- codeagent:::todo_write_tool(sid)
  res <- t(todos = list(list(content = "x", status = "pending")))
  expect_true(S7::S7_inherits(res, ellmer::ContentToolResult))
  back <- read_todos(sid)
  expect_true(grepl("\\[ \\] x", back))
})

test_that(".coerce_todos handles list and data.frame", {
  l <- codeagent:::.coerce_todos(list(list(content = "a", status = "pending")))
  expect_equal(length(l), 1L)
  df <- data.frame(content = c("a", "b"), status = c("pending", "completed"),
                   stringsAsFactors = FALSE)
  l2 <- codeagent:::.coerce_todos(df)
  expect_equal(length(l2), 2L)
  expect_equal(length(codeagent:::.coerce_todos(NULL)), 0L)
})

# ---------------------------------------------------------------------------
# Sandbox
# ---------------------------------------------------------------------------

test_that(".sandbox_profile defaults to disabled, network allowed", {
  p <- codeagent:::.sandbox_profile(NULL)
  expect_false(p$enabled)
  expect_true(p$allow_network)
})

test_that(".sandbox_profile reads settings$sandbox", {
  p <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = TRUE, allow_network = FALSE)))
  expect_true(p$enabled)
  expect_false(p$allow_network)
})

test_that(".sandbox_block_reason blocks network cmds only when enabled + no network", {
  p_off <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = FALSE)))
  expect_null(codeagent:::.sandbox_block_reason("curl http://x", p_off))

  p_net <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = TRUE, allow_network = TRUE)))
  expect_null(codeagent:::.sandbox_block_reason("curl http://x", p_net))

  p_block <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = TRUE, allow_network = FALSE)))
  expect_match(codeagent:::.sandbox_block_reason("curl http://x", p_block), "network")
  expect_match(codeagent:::.sandbox_block_reason("wget x", p_block), "network")
  expect_match(codeagent:::.sandbox_block_reason("git clone x", p_block), "network")
  # Non-network command passes
  expect_null(codeagent:::.sandbox_block_reason("ls -la", p_block))
})

test_that(".sandbox_env returns NULL when disabled, scrubbed vector when enabled", {
  p_off <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = FALSE)))
  expect_null(codeagent:::.sandbox_env(p_off))

  withr::with_envvar(c(SECRET_TOKEN = "shh", PATH = Sys.getenv("PATH")), {
    p_on <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = TRUE)))
    env <- codeagent:::.sandbox_env(p_on)
    expect_true(is.character(env))
    # SECRET_TOKEN must not leak (not in keep_env)
    expect_false(any(grepl("^SECRET_TOKEN=", env)))
    # PATH is kept
    expect_true(any(grepl("^PATH=", env)))
  })
})

test_that("bash_tool blocks network command under sandbox", {
  t <- bash_tool(mode = "bypass",
                 sandbox = list(enabled = TRUE, allow_network = FALSE))
  res <- t(command = "curl http://example.com")
  val <- tryCatch(as.character(res@value), error = function(e) "")
  expect_true(grepl("[Ss]andbox", val))
})

# ---------------------------------------------------------------------------
# Team
# ---------------------------------------------------------------------------

test_that("team_run returns empty list for no tasks", {
  expect_equal(team_run(character(0)), list())
})

test_that("team_run_tool builds a valid ellmer tool", {
  skip_if_not_installed("mirai")
  t <- codeagent:::team_run_tool(model = "claude-sonnet-4-6")
  expect_true(inherits(t, "ellmer::ToolDef"))
})

# ---------------------------------------------------------------------------
# Worktree cleanup signature
# ---------------------------------------------------------------------------

test_that(".cleanup_worktree accepts base_dir and is null-safe", {
  expect_silent(codeagent:::.cleanup_worktree(NULL))
  expect_true("base_dir" %in% names(formals(codeagent:::.cleanup_worktree)))
})

# ---------------------------------------------------------------------------
# Subagent sidechain persistence
# ---------------------------------------------------------------------------

test_that(".run_subagent_loop accepts persist/cwd/description args", {
  fm <- names(formals(codeagent:::.run_subagent_loop))
  expect_true(all(c("persist", "cwd", "description") %in% fm))
})

# ---------------------------------------------------------------------------
# MCP server transport
# ---------------------------------------------------------------------------

test_that("codeagent_mcp_server validates transport argument", {
  expect_error(codeagent_mcp_server(transport = "bogus"))
})

# ---------------------------------------------------------------------------
# parallelly: cgroup-aware worker cap
# ---------------------------------------------------------------------------

test_that(".team_default_workers caps at availableCores and #tasks", {
  n <- codeagent:::.team_default_workers(100L)
  expect_true(n >= 1L)
  # Must not exceed the cgroup-aware core count when parallelly is present.
  if (requireNamespace("parallelly", quietly = TRUE)) {
    expect_lte(n, parallelly::availableCores())
  } else {
    expect_lte(n, 4L)
  }
})

test_that(".team_default_workers never exceeds the task count", {
  expect_equal(codeagent:::.team_default_workers(1L), 1L)
  expect_lte(codeagent:::.team_default_workers(2L), 2L)
})

# ---------------------------------------------------------------------------
# ragnar: codebase RAG (defensive, optional)
# ---------------------------------------------------------------------------

test_that(".rag_embed_fn returns NULL when ragnar absent, function when present", {
  if (!requireNamespace("ragnar", quietly = TRUE)) {
    expect_null(codeagent:::.rag_embed_fn())
  } else {
    withr::with_envvar(c(CODEAGENT_BASE_URL = "https://x.example.com"), {
      fn <- codeagent:::.rag_embed_fn()
      expect_true(is.function(fn))
    })
  }
})

test_that("register_rag_tool is a no-op (returns chat) when indexing yields nothing", {
  skip_if_not_installed("ellmer")
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  # Point at an empty temp dir so no files match -> tool not registered.
  empty <- tempfile(); dir.create(empty); on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  out <- codeagent:::register_rag_tool(ch, cwd = empty)
  expect_identical(out, ch)
})

test_that("build_codebase_store returns NULL on empty dir", {
  skip_if_not_installed("ragnar")
  empty <- tempfile(); dir.create(empty); on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  expect_null(build_codebase_store(cwd = empty))
})
