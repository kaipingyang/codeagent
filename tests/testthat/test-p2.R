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
  p <- codeagent:::.sandbox_profile(list(sandbox = list(
    enabled = TRUE, allow_network = FALSE, run_r_backend = "process")))
  expect_true(p$enabled)
  expect_false(p$allow_network)
  expect_identical(p$run_r_backend, "process")
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
  # tool_reject() throws ellmer_tool_reject -- the semantically correct signal
  expect_error(t(command = "curl http://example.com"), class = "ellmer_tool_reject")
})

# ---------------------------------------------------------------------------
# Team
# ---------------------------------------------------------------------------

test_that("team_run returns empty list for no tasks", {
  expect_equal(team_run(character(0)), list())
})

test_that("team_run runs real mirai workers: list, length, input order preserved", {
  skip_on_cran()
  skip_if_not_installed("mirai")
  # No reachable endpoint -> each worker's codeagent() call fails fast and
  # run_one returns an "[Error] ..." string. This exercises the REAL mirai
  # worker path (daemons spawn, run_one serialises + runs, all results are
  # collected) and pins the documented contract: a list, same length, in input
  # order. Guards against the removed crew branch (which returned NA / dropped
  # results / lost order).
  withr::local_envvar(
    CODEAGENT_BASE_URL = "http://127.0.0.1:1",   # connection refused -> fast
    CODEAGENT_API_KEY  = "x",
    CODEAGENT_MODEL    = "x")
  tasks <- c("alpha", "bravo", "charlie")
  res <- team_run(tasks, n_workers = 2L)
  expect_type(res, "list")
  expect_length(res, length(tasks))
  # run_one must actually RUN in each worker, i.e. its args were BOUND. If the
  # constants were passed via `...` (which mirai does NOT bind in the worker),
  # run_one would crash with "argument missing" and mirai would return
  # `miraiError` objects instead of run_one's own "[Error] ..." string. Note
  # `is.character()` is TRUE for a miraiError, so we must check the class.
  expect_false(any(vapply(res, function(x) inherits(x, "miraiError"), logical(1))))
  expect_true(all(grepl("^\\[Error\\]", vapply(res, as.character, character(1)))))
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

test_that("register_rag_tool classifies newly registered retrieval tools", {
  skip_if_not_installed("ragnar")
  ch <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  testthat::local_mocked_bindings(
    ragnar_register_tool_retrieve = function(chat, store, ...) {
      chat$register_tool(ellmer::tool(
        function(query) query,
        name = "RAGFixture",
        description = "fixture",
        arguments = list(query = ellmer::type_string("query"))))
    },
    .package = "ragnar"
  )
  register_rag_tool(ch, store = structure(list(), class = "fixture_store"))
  meta <- codeagent:::.tool_metadata("RAGFixture")
  expect_true(meta$known)
  expect_identical(meta$capability, "net")
  expect_identical(meta$set, "A")
})

test_that("build_codebase_store returns NULL on empty dir", {
  skip_if_not_installed("ragnar")
  empty <- tempfile(); dir.create(empty); on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  expect_null(build_codebase_store(cwd = empty))
})

# ---------------------------------------------------------------------------
# RunR sandbox (in-process code-pattern blocking)
# ---------------------------------------------------------------------------

test_that(".sandbox_block_r_code blocks shell/env calls when enabled", {
  p <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = TRUE, allow_network = TRUE)))
  expect_match(codeagent:::.sandbox_block_r_code("system('ls')", p), "shell")
  expect_match(codeagent:::.sandbox_block_r_code("system2('ls')", p), "shell")
  expect_match(codeagent:::.sandbox_block_r_code("Sys.setenv(X=1)", p), "shell")
  # Plain compute is allowed
  expect_null(codeagent:::.sandbox_block_r_code("1 + 1", p))
})

test_that(".sandbox_block_r_code blocks network fns only when network disabled", {
  p_net <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = TRUE, allow_network = TRUE)))
  expect_null(codeagent:::.sandbox_block_r_code("httr2::request('http://x')", p_net))

  p_block <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = TRUE, allow_network = FALSE)))
  expect_match(codeagent:::.sandbox_block_r_code("httr2::request('http://x')", p_block), "network")
  expect_match(codeagent:::.sandbox_block_r_code("download.file('x','y')", p_block), "network")
  expect_match(codeagent:::.sandbox_block_r_code("install.packages('z')", p_block), "network")
})

test_that(".sandbox_block_r_code is a no-op when sandbox disabled", {
  p_off <- codeagent:::.sandbox_profile(list(sandbox = list(enabled = FALSE)))
  expect_null(codeagent:::.sandbox_block_r_code("system('rm -rf /')", p_off))
})

test_that("run_r_tool accepts a sandbox argument", {
  expect_true("sandbox" %in% names(formals(run_r_tool)))
  expect_true("sandbox" %in% names(formals(register_run_r_tool)))
})

# ---------------------------------------------------------------------------
# Declarative hooks from settings.json
# ---------------------------------------------------------------------------

test_that(".hooks_from_settings returns NULL for empty/invalid spec", {
  expect_null(codeagent:::.hooks_from_settings(list()))
  expect_null(codeagent:::.hooks_from_settings(list(hooks = list())))
  expect_null(codeagent:::.hooks_from_settings(list(hooks = "bad")))
})

test_that(".hooks_from_settings builds a HookRegistry from a valid spec", {
  s <- list(hooks = list(
    PreToolUse  = list(list(command = "true")),
    PostToolUse = list(list(command = "true", pattern = "Bash"))
  ))
  reg <- codeagent:::.hooks_from_settings(s)
  expect_s3_class(reg, "HookRegistry")
})

test_that(".hooks_from_settings skips unknown events", {
  s <- list(hooks = list(BogusEvent = list(list(command = "true"))))
  expect_null(codeagent:::.hooks_from_settings(s))
})

# ---------------------------------------------------------------------------
# MCP auto-connect
# ---------------------------------------------------------------------------

test_that(".mcp_autoconnect returns 0 when no servers declared", {
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  empty <- tempfile(); dir.create(empty); on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  n <- codeagent:::.mcp_autoconnect(ch, list(cwd = empty))
  expect_equal(n, 0L)
})

test_that(".mcp_autoconnect respects disabled_mcp_json_servers filter", {
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  s <- list(
    mcp_servers = list(foo = list(command = "true"), bar = list(command = "true")),
    disabled_mcp_json_servers = c("foo", "bar")  # all disabled -> nothing to connect
  )
  n <- codeagent:::.mcp_autoconnect(ch, s)
  expect_equal(n, 0L)
})

# ---------------------------------------------------------------------------
# RunR true isolation (callr subprocess with scrubbed env)
# ---------------------------------------------------------------------------

test_that(".runr_sandboxed_exec scrubs secrets from the child process", {
  skip_if_not_installed("callr")
  withr::with_envvar(c(CODEAGENT_API_KEY = "SECRET_LEAK_TOKEN_abc"), {
    prof <- codeagent:::.sandbox_profile(list(sandbox = list(
      enabled = TRUE, allow_network = TRUE, run_r_backend = "process")))
    r <- codeagent:::.runr_sandboxed_exec('Sys.getenv("CODEAGENT_API_KEY")', prof)
    val <- tryCatch(as.character(r@value), error = function(e) as.character(r))
    expect_false(grepl("SECRET_LEAK_TOKEN", val))
  })
})

test_that(".runr_sandboxed_exec still runs plain computation", {
  skip_if_not_installed("callr")
  prof <- codeagent:::.sandbox_profile(list(sandbox = list(
    enabled = TRUE, allow_network = TRUE, run_r_backend = "process")))
  r <- codeagent:::.runr_sandboxed_exec("sum(1:10)", prof)
  val <- tryCatch(as.character(r@value), error = function(e) as.character(r))
  expect_match(val, "55")
})

test_that(".runr_sandboxed_exec enforces a timeout", {
  skip_if_not_installed("callr")
  prof <- codeagent:::.sandbox_profile(list(sandbox = list(
    enabled = TRUE, allow_network = TRUE, run_r_backend = "process")))
  r <- codeagent:::.runr_sandboxed_exec("Sys.sleep(30)", prof, timeout = 2)
  val <- tryCatch(as.character(r@value), error = function(e) as.character(r))
  expect_match(val, "timed out", ignore.case = TRUE)
})

test_that(".runr_sandboxed_exec resists regex-bypass secret reads", {
  skip_if_not_installed("callr")
  withr::with_envvar(c(CODEAGENT_API_KEY = "SECRET_BYPASS_xyz"), {
    prof <- codeagent:::.sandbox_profile(list(sandbox = list(
      enabled = TRUE, allow_network = TRUE, run_r_backend = "process")))
    # Construct the call dynamically to dodge any pattern matcher.
    code <- 'do.call(get(paste0("Sys",".getenv")), list("CODEAGENT_API_KEY"))'
    r <- codeagent:::.runr_sandboxed_exec(code, prof)
    val <- tryCatch(as.character(r@value), error = function(e) as.character(r))
    expect_false(grepl("SECRET_BYPASS", val))
  })
})

test_that("RunR sandbox fails closed without an explicit process fallback", {
    skip_if_not_installed("btw")
    tool <- run_r_tool(
      mode = "bypass",
      sandbox = list(enabled = TRUE, allow_network = TRUE)
    )
    expect_error(tool(code = "1 + 1"), "no supported OS sandbox backend",
                 class = "ellmer_tool_reject")
})

test_that("worker security context preserves parent policy without expansion", {
    root <- withr::local_tempdir()
    ctx <- codeagent:::.worker_security_context(
      permission_mode = "plan",
      rules = list(PermissionRule("Read", "deny", rule_content = "secret/*")),
      tools = list(
        sets = "A",
        capabilities = list(net = "deny"),
        overrides = list(WebFetch = "deny")
      ),
      sandbox = list(enabled = TRUE, allow_network = FALSE),
      cwd = root
    )
    restored <- jsonlite::fromJSON(
      codeagent:::.worker_security_context_json(ctx),
      simplifyVector = FALSE
    )
    expect_identical(restored$permission_mode, "plan")
    expect_identical(unlist(restored$tools$sets), "A")
    expect_identical(restored$tools$capabilities$net, "deny")
    expect_identical(restored$tools$overrides$WebFetch, "deny")
})

test_that("worker security context preserves the parent tool configuration", {
    root <- withr::local_tempdir()
    ctx <- codeagent:::.worker_security_context(
      cwd = root,
      tool_config = list(
        file_tools = "btw", btw_groups = c("docs", "git"),
        explore_data = FALSE, rag = FALSE),
      allowed_tools = c("btw_tool_files_read", "btw_tool_docs_help")
    )
    restored <- jsonlite::fromJSON(
      codeagent:::.worker_security_context_json(ctx),
      simplifyVector = FALSE)
    expect_identical(restored$tool_config$file_tools, "btw")
    expect_setequal(unlist(restored$tool_config$btw_groups),
                    c("docs", "git"))
    expect_false(restored$tool_config$explore_data)
    expect_setequal(unlist(restored$allowed_tools),
                    c("btw_tool_files_read", "btw_tool_docs_help"))
})

test_that("worker security context preserves backend reconstruction settings", {
    root <- withr::local_tempdir()
    ctx <- codeagent:::.worker_security_context(
      cwd = root,
      backend = list(
        model = "gpt-4.1",
        provider = "openai_compatible",
        base_url = "https://example.invalid/v1",
        api_key_env = "CUSTOM_API_KEY",
        effort_level = "high"
      ))
    restored <- jsonlite::fromJSON(
      codeagent:::.worker_security_context_json(ctx),
      simplifyVector = FALSE)
    expect_identical(as.integer(restored$version), 2L)
    expect_identical(restored$backend$model, "gpt-4.1")
    expect_identical(restored$backend$provider, "openai_compatible")
    expect_identical(restored$backend$base_url,
                     "https://example.invalid/v1")
    expect_identical(restored$backend$api_key_env, "CUSTOM_API_KEY")
    expect_identical(restored$backend$effort_level, "high")
})

test_that("worker client reconstructs the captured parent backend", {
    root <- withr::local_tempdir()
    captured <- NULL
    testthat::local_mocked_bindings(
      .make_chat = function(settings, cwd, ...) {
        captured <<- settings
        structure(list(), class = "Chat")
      },
      .register_all_tools = function(...) invisible(NULL),
      .new_client = function(chat, settings, data_shield = NULL)
        list(chat = chat, settings = settings),
      .package = "codeagent"
    )
    ctx <- codeagent:::.worker_security_context(
      cwd = root,
      backend = list(
        model = "gpt-4.1",
        provider = "openai_compatible",
        base_url = "https://example.invalid/v1",
        api_key_env = "CUSTOM_API_KEY",
        effort_level = "high"
      ))
    codeagent:::.worker_client_from_json(
      "ignored-model", codeagent:::.worker_security_context_json(ctx))
    expect_identical(captured$model, "gpt-4.1")
    expect_identical(captured$provider, "openai_compatible")
    expect_identical(captured$base_url, "https://example.invalid/v1")
    expect_identical(captured$api_key_env, "CUSTOM_API_KEY")
    expect_identical(captured$effort_level, "high")
})

test_that("worker client removes tools absent from the parent snapshot", {
    root <- withr::local_tempdir()
    read_def <- ellmer::tool(function(file_path) file_path, name = "Read",
      description = "read", arguments = list(
        file_path = ellmer::type_string("path")))
    write_def <- ellmer::tool(function(file_path) file_path, name = "Write",
      description = "write", arguments = list(
        file_path = ellmer::type_string("path")))
    fake_chat <- new.env(parent = emptyenv())
    class(fake_chat) <- "Chat"
    fake_chat$tools <- list()
    fake_chat$get_tools <- function() fake_chat$tools
    fake_chat$set_tools <- function(value) {
      fake_chat$tools <- value
      invisible(fake_chat)
    }
    testthat::local_mocked_bindings(
      .make_chat = function(settings, cwd, ...) fake_chat,
      .register_all_tools = function(chat, settings, ask_fn = NULL, ...) {
        chat$set_tools(list(read_def, write_def))
        invisible(chat)
      },
      .new_client = function(chat, settings, data_shield = NULL)
        list(chat = chat, settings = settings),
      .package = "codeagent"
    )
    ctx <- codeagent:::.worker_security_context(
      cwd = root, allowed_tools = "Read")
    client <- codeagent:::.worker_client_from_json(
      "gpt-4.1", codeagent:::.worker_security_context_json(ctx), root)
    expect_identical(codeagent:::.tool_names(client$chat$get_tools()), "Read")
    expect_false(client$settings$delegation_tools)
})

test_that("worker rejects a same-name tool with a different implementation", {
    trusted <- ellmer::tool(function(file_path) "restricted", name = "Read",
      description = "restricted", arguments = list(
        file_path = ellmer::type_string("path")))
    expanded <- ellmer::tool(function(file_path) readLines(file_path),
      name = "Read", description = "expanded", arguments = list(
        file_path = ellmer::type_string("path")))
    context <- codeagent:::.worker_security_context(
      allowed_tools = "Read",
      allowed_tool_signatures = codeagent:::.tool_signatures(list(trusted)))
    kept <- codeagent:::.filter_verified_worker_tools(
      list(expanded), context)
    expect_length(kept, 0L)
})

test_that("foreground Agent uses the security-context cwd", {
    root <- withr::local_tempdir()
    other <- withr::local_tempdir()
    observed <- NULL
    sub_chat <- ellmer::chat_openai_compatible(
      base_url = "http://x", model = "m", credentials = function() "k")
    ctx <- codeagent:::.worker_security_context(
      cwd = root, allowed_tools = character())
    testthat::local_mocked_bindings(
      .register_all_tools = function(chat, settings, ask_fn = NULL, ...) {
        observed <<- settings$cwd
        invisible(chat)
      },
      .run_subagent_loop = function(...) "done",
      .package = "codeagent"
    )
    withr::with_dir(other, {
      out <- codeagent:::agent_tool(
        parent_chat = sub_chat, security_context = ctx)(
          description = "cwd", prompt = "check")
      expect_identical(out, "done")
})
    expect_identical(observed, codeagent:::.canonical_security_path(root))
  })

test_that("worker client construction does not reload project settings", {
    root <- withr::local_tempdir()
    dir.create(file.path(root, ".codeagent"))
    writeLines(
      '{"env":{"CODEAGENT_WORKER_RELOAD_TEST":"unsafe"}}',
      file.path(root, ".codeagent", "settings.json")
    )
    old <- Sys.getenv("CODEAGENT_WORKER_RELOAD_TEST", unset = NA_character_)
    on.exit({
      if (is.na(old)) Sys.unsetenv("CODEAGENT_WORKER_RELOAD_TEST")
      else Sys.setenv(CODEAGENT_WORKER_RELOAD_TEST = old)
    }, add = TRUE)
    Sys.unsetenv("CODEAGENT_WORKER_RELOAD_TEST")

    captured <- NULL
    testthat::local_mocked_bindings(
      .make_chat = function(settings, cwd, ...) structure(list(), class = "Chat"),
      .register_all_tools = function(chat, settings, ask_fn = NULL, ...) {
        captured <<- settings
        invisible(chat)
      },
      .new_client = function(chat, settings, data_shield = NULL)
        list(chat = chat, settings = settings),
      .package = "codeagent"
    )
    ctx <- codeagent:::.worker_security_context(
      permission_mode = "plan",
      tools = list(sets = "A", capabilities = list(net = "deny"),
                   overrides = list(WebFetch = "deny")),
      cwd = root
    )
    codeagent:::.worker_client_from_json(
      "gpt-4.1", codeagent:::.worker_security_context_json(ctx), root)
    expect_identical(Sys.getenv("CODEAGENT_WORKER_RELOAD_TEST"), "")
    expect_identical(captured$permission_mode, "plan")
    expect_identical(captured$tools$capabilities$net, "deny")
    expect_null(captured$hooks_registry)
})

test_that("worker security cwd cannot be overridden by an ordinary argument", {
    root <- withr::local_tempdir()
    other <- withr::local_tempdir()
    captured <- NULL
    testthat::local_mocked_bindings(
      .make_chat = function(settings, cwd, ...) structure(list(), class = "Chat"),
      .register_all_tools = function(chat, settings, ask_fn = NULL, ...) {
        captured <<- settings$cwd
        invisible(chat)
      },
      .new_client = function(chat, settings, data_shield = NULL)
        list(chat = chat, settings = settings),
      .package = "codeagent"
    )
    ctx <- codeagent:::.worker_security_context(cwd = root)
    codeagent:::.worker_client_from_json(
      "gpt-4.1", codeagent:::.worker_security_context_json(ctx), other)
    expect_identical(captured, codeagent:::.canonical_security_path(root))
})

test_that("verified worktree override can derive a worker cwd", {
    root <- withr::local_tempdir()
    worktree <- withr::local_tempdir()
    captured <- NULL
    testthat::local_mocked_bindings(
      .make_chat = function(settings, cwd, ...) structure(list(), class = "Chat"),
      .register_all_tools = function(chat, settings, ask_fn = NULL, ...) {
        captured <<- settings$cwd
        invisible(chat)
      },
      .new_client = function(chat, settings, data_shield = NULL)
        list(chat = chat, settings = settings),
      .package = "codeagent"
    )
    ctx <- codeagent:::.worker_security_context(cwd = root)
    codeagent:::.worker_client_from_json(
      "gpt-4.1", codeagent:::.worker_security_context_json(ctx), worktree,
      trusted_cwd_override = TRUE)
    expect_identical(captured, codeagent:::.canonical_security_path(worktree))
})


test_that("codeagent_mcp_server has an explicit safe session-tools default", {
  fm <- formals(codeagent_mcp_server)
  expect_true("session_tools" %in% names(fm))
  expect_identical(fm$session_tools, FALSE)
})

test_that("codeagent_mcp_server refuses old mcptools", {
  testthat::local_mocked_bindings(
    .mcptools_supported = function(...) FALSE,
    .package = "codeagent")
  expect_error(codeagent_mcp_server(tools = list()), "mcptools >= 1.0.2.9000")
})

test_that("network MCP server cannot expose session tools", {
  testthat::local_mocked_bindings(
    .mcptools_supported = function(...) TRUE,
    .package = "codeagent")
  expect_error(
    codeagent_mcp_server(tools = list(), transport = "http",
                         host = "0.0.0.0", session_tools = TRUE),
    "loopback")
})
