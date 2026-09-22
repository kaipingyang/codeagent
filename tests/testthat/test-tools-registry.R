# Guard rails for the codeagent <-> btw tool surface.
#
# codeagent reuses btw rather than reinventing it (CLAUDE.md "btw as tool
# layer"), so every btw tool must have a deliberate codeagent classification.
# When btw ships a new tool or group, these tests fail on purpose: someone has
# to decide the group name, capability and set, rather than letting the tool
# silently fall through to the "unknown -> exec" default.

# Full btw registry (not btw_tools(), which drops tools whose can_register()
# fails in this environment, e.g. git without gert or github without gh).
.btw_registry_or_skip <- function() {
  skip_if_not_installed("btw")
  reg <- tryCatch(utils::getFromNamespace(".btw_tools", "btw"),
                  error = function(e) NULL)
  if (is.null(reg)) skip("btw internal tool registry is not available")
  reg
}

test_that(".BTW_GROUPS covers every group the installed btw ships", {
  reg <- .btw_registry_or_skip()
  btw_groups <- sort(unique(vapply(reg, function(t) t$group, character(1L))))
  expect_setequal(names(.BTW_GROUPS), btw_groups)
})

test_that("every codeagent-native tool declares a group", {
  native <- names(.TOOL_META)[vapply(.TOOL_META, function(m)
    identical(m$set, "A"), logical(1L))]
  expect_gt(length(native), 0L)
  groups <- vapply(native, .tool_group, character(1L))
  expect_true(all(nzchar(groups)),
              info = paste("ungrouped:",
                           paste(native[!nzchar(groups)], collapse = ", ")))
})

test_that(".CODEAGENT_GROUPS names only real native tools", {
  listed <- unlist(.CODEAGENT_GROUPS, use.names = FALSE)
  expect_false(anyDuplicated(listed) > 0L,
               info = paste("listed twice:",
                            paste(listed[duplicated(listed)], collapse = ", ")))
  unknown <- setdiff(listed, names(.TOOL_META))
  expect_identical(unknown, character(0),
                   info = paste("not in .TOOL_META:",
                                paste(unknown, collapse = ", ")))
  wrong_set <- listed[vapply(listed, function(n)
    !identical(.TOOL_META[[n]]$set, "A"), logical(1L))]
  expect_identical(wrong_set, character(0),
                   info = paste("not set A:", paste(wrong_set, collapse = ", ")))
})

test_that(".resolve_tool_spec(NULL) selects every tool", {
  spec <- .resolve_tool_spec(NULL)
  expect_true(spec$all)
})

test_that(".resolve_tool_spec(FALSE) selects no codeagent tool", {
  spec <- .resolve_tool_spec(FALSE)
  expect_false(spec$all)
  expect_identical(spec$native, character(0))
  expect_identical(spec$btw_groups, character(0))
})

test_that(".resolve_tool_spec expands a native capability group", {
  spec <- .resolve_tool_spec(c("lint", "shell"))
  expect_false(spec$all)
  expect_setequal(spec$native, c("Lint", "Format", "Bash"))
  expect_identical(spec$btw_groups, character(0))
})

test_that(".resolve_tool_spec accepts individual tool names", {
  spec <- .resolve_tool_spec(c("Read", "Glob"))
  expect_setequal(spec$native, c("Read", "Glob"))
})

test_that(".resolve_tool_spec routes btw-only groups to btw_groups", {
  spec <- .resolve_tool_spec(c("docs", "cran"))
  expect_identical(spec$native, character(0))
  expect_setequal(spec$btw_groups, c("docs", "cran"))
})

test_that(".resolve_tool_spec rejects unknown names instead of dropping them", {
  expect_error(.resolve_tool_spec("nosuchthing"), "nosuchthing")
  expect_error(.resolve_tool_spec(c("docs", "nosuchthing")), "nosuchthing")
})

test_that("codeagent-owned capabilities resolve to the owning native tool", {
  expect_identical(.resolve_tool_spec("run")$native, "RunR")
  expect_identical(.resolve_tool_spec("skills")$native, "use_skill")
  expect_setequal(.resolve_tool_spec("agent")$native,
                  c("Agent", "BackgroundAgent", "TeamRun", "TeamCoordinate"))
  expect_identical(.resolve_tool_spec("run")$btw_groups, character(0))
})

test_that("files@ and web@ pick the implementation backend", {
  expect_identical(.resolve_tool_spec("files")$backends$files, "core")
  expect_identical(.resolve_tool_spec("files@core")$backends$files, "core")
  expect_identical(.resolve_tool_spec("files@btw")$backends$files, "btw")
  expect_identical(.resolve_tool_spec("files@both")$backends$files, "both")
  expect_identical(.resolve_tool_spec("web@btw")$backends$web, "btw")
})

test_that("files@btw drops the native file tools and keeps the btw group", {
  spec <- .resolve_tool_spec("files@btw")
  expect_false(any(c("Read", "Write", "Edit") %in% spec$native))
  expect_true("files" %in% spec$btw_groups)
})

test_that("an @ suffix is rejected on single-implementation groups", {
  expect_error(.resolve_tool_spec("shell@btw"), "shell")
  expect_error(.resolve_tool_spec("files@nosuch"), "nosuch")
})

.registry_test_chat <- function() {
  ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                 credentials = function() "k")
}
.registered_names <- function(chat) {
  unname(unlist(lapply(chat$get_tools(), function(t)
    tryCatch(t@name, error = function(e) NA_character_))))
}

test_that("default registration keeps the three btw ownership boundaries", {
  skip_if_not_installed("btw")
  chat <- .registry_test_chat()
  .register_all_tools(chat, list(permission_mode = "default", cwd = getwd()))
  nm <- .registered_names(chat)

  # 1. skills: .make_skill_tool() owns the capability
  expect_false("btw_tool_skill" %in% nm)
  expect_true("use_skill" %in% nm)
  # 2. files: default backend is codeagent's (any absolute path)
  expect_false(any(startsWith(nm, "btw_tool_files_")))
  expect_true(all(c("Read", "Write", "Edit", "MultiEdit") %in% nm))
  # 3. agent: the dedicated owner keeps worktree/async/Data Shield semantics
  expect_false(any(startsWith(nm, "btw_tool_agent_")))
  expect_true("Agent" %in% nm)
  # btw groups codeagent does not own are still registered
  expect_true(any(startsWith(nm, "btw_tool_docs_")))
  # web has always registered both implementations side by side
  expect_true(all(c("WebSearch", "WebFetch") %in% nm))
  expect_true("btw_tool_web_read_url" %in% nm)
})

test_that("codeagent_client(tools=) restricts what gets registered", {
  skip_if_not_installed("btw")
  client <- codeagent_client(.registry_test_chat(), tools = c("files", "shell"))
  nm <- .registered_names(client$chat)
  expect_true(all(c("Read", "Write", "Edit", "MultiEdit", "Bash") %in% nm))
  expect_false("WebSearch" %in% nm)
  expect_false("Agent" %in% nm)
  expect_false(any(startsWith(nm, "btw_tool_")))
})

test_that("codeagent_client(tools=FALSE) keeps host-registered tools", {
  chat <- .registry_test_chat()
  chat$register_tool(ellmer::tool(function(path) "ok", name = "host_tool",
    description = "host", arguments = list(path = ellmer::type_string("p"))))
  client <- codeagent_client(chat, tools = FALSE)
  nm <- .registered_names(client$chat)
  expect_identical(nm, "host_tool")
})

test_that("files@btw swaps the native file tools for btw's Path A set", {
  skip_if_not_installed("btw")
  client <- suppressMessages(
    codeagent_client(.registry_test_chat(), tools = c("files@btw", "shell")))
  nm <- .registered_names(client$chat)
  expect_false(any(c("Read", "Write", "Edit", "MultiEdit") %in% nm))
  expect_true(any(startsWith(nm, "btw_tool_files_")))
  expect_true("Bash" %in% nm)
})

test_that("files@both registers the two parallel edit paths together", {
  skip_if_not_installed("btw")
  client <- suppressMessages(
    codeagent_client(.registry_test_chat(), tools = "files@both"))
  nm <- .registered_names(client$chat)
  expect_true(all(c("Read", "Write", "Edit") %in% nm))
  expect_true(any(startsWith(nm, "btw_tool_files_")))
})

test_that("tools= and the superseded btw_groups= cannot both be supplied", {
  expect_error(
    codeagent_client(.registry_test_chat(), tools = "shell", btw_groups = "docs"),
    "btw_groups")
})

test_that("btw_groups= alone still works (superseded, not removed)", {
  skip_if_not_installed("btw")
  client <- codeagent_client(.registry_test_chat(), btw_groups = "docs")
  nm <- .registered_names(client$chat)
  expect_true(any(startsWith(nm, "btw_tool_docs_")))
  expect_false(any(startsWith(nm, "btw_tool_cran_")))
  expect_true("Read" %in% nm)
})

test_that("a bare disallowed_tools name removes the tool from the model's view", {
  skip_if_not_installed("btw")
  client <- codeagent_client(.registry_test_chat(),
                             tools = c("files", "shell"),
                             disallowed_tools = "Bash")
  nm <- .registered_names(client$chat)
  expect_false("Bash" %in% nm)
  expect_true("Read" %in% nm)
})

test_that("a scoped disallowed_tools entry keeps the tool and denies the call", {
  client <- codeagent_client(.registry_test_chat(),
                             tools = "shell",
                             disallowed_tools = "Bash(rm *)")
  nm <- .registered_names(client$chat)
  expect_true("Bash" %in% nm)
  denies <- Filter(function(r) identical(r$behavior, "deny"), client$settings$rules)
  expect_true(any(vapply(denies, function(r)
    identical(r$tool_name, "Bash") && identical(r$rule_content, "rm *"),
    logical(1L))))
})

test_that("disallowed_tools accepts a capability group name", {
  skip_if_not_installed("btw")
  client <- codeagent_client(.registry_test_chat(),
                             tools = c("files", "lint"),
                             disallowed_tools = "lint")
  nm <- .registered_names(client$chat)
  expect_false(any(c("Lint", "Format") %in% nm))
  expect_true("Read" %in% nm)
})

.btw_tool_named <- function(group, name) {
  skip_if_not_installed("btw")
  tools <- tryCatch(btw::btw_tools(group), error = function(e) list())
  hit <- Filter(function(t) identical(as.character(t@name), name), tools)
  if (!length(hit)) skip(paste0("btw tool not registrable here: ", name))
  hit[[1L]]
}

test_that("a btw tool declaring read_only_hint is classified read, not exec", {
  tool <- .btw_tool_named("pkg", "btw_tool_pkg_coverage")
  expect_true(isTRUE(tool@annotations$read_only_hint))
  expect_identical(.tool_capability("btw_tool_pkg_coverage", tool), "read")
})

test_that("a read-only btw tool that reaches the network stays net", {
  tool <- .btw_tool_named("web", "btw_tool_web_read_url")
  expect_true(isTRUE(tool@annotations$read_only_hint))
  expect_identical(.tool_capability("btw_tool_web_read_url", tool), "net")
})

test_that("built-in .TOOL_META stays authoritative over a tool's own hint", {
  # A btw file tool is explicitly classified write; its annotations must not
  # be able to downgrade that.
  tool <- .btw_tool_named("files", "btw_tool_files_write")
  expect_identical(.tool_capability("btw_tool_files_write", tool), "write")
})

test_that("the gate honours a read-only btw tool the prefix scan misjudged", {
  tool   <- .btw_tool_named("pkg", "btw_tool_pkg_coverage")
  cap    <- .tool_capability("btw_tool_pkg_coverage", tool)
  policy <- .resolve_tool_policy(list())
  expect_identical(cap, "read")
  # default: read-capability tools run without prompting
  expect_identical(
    .gate_decide("btw_tool_pkg_coverage", list(), policy, "default", list(), cap),
    "allow")
  # plan is a read-only boundary, so a read tool belongs inside it
  expect_identical(
    .gate_decide("btw_tool_pkg_coverage", list(), policy, "plan", list(), cap),
    "allow")
})

test_that("a host tool registered read via register_tool_meta passes the gate", {
  register_tool_meta("erp_reader", capability = "read", set = "A")
  policy <- .resolve_tool_policy(list())
  expect_identical(
    .gate_decide("erp_reader", list(), policy, "default", list(), "read"), "allow")
  expect_identical(
    .gate_decide("erp_reader", list(), policy, "plan", list(), "read"), "allow")
})

test_that("a host tool cannot downgrade a built-in exec tool", {
  register_tool_meta("Bash", capability = "read", set = "A")
  expect_identical(.tool_capability("Bash"), "exec")
  policy <- .resolve_tool_policy(list())
  expect_identical(
    .gate_decide("Bash", list(command = "ls"), policy, "plan", list(), "read"),
    "deny")
})

test_that("register_tool_meta defaults are usable without extra tools$sets config", {
  # The ERP report's exact call: no `set=`, so it lands in the default "C".
  register_tool_meta("erp_tool_read_excel", capability = "read")
  policy <- .resolve_tool_policy(list())
  expect_identical(
    .gate_decide("erp_tool_read_excel", list(), policy, "default", list(), "read"),
    "allow")
  expect_identical(
    .gate_decide("erp_tool_read_excel", list(), policy, "plan", list(), "read"),
    "allow")
})

test_that("an unregistered tool is still denied in every mode", {
  policy <- .resolve_tool_policy(list())
  for (mode in c("default", "plan", "bypass", "dont_ask")) {
    expect_identical(
      .gate_decide("never_declared_tool", list(), policy, mode, list()), "deny",
      info = mode)
  }
})

test_that("the worker security snapshot carries the parent's tools= selection", {
  settings <- list(permission_mode = "default", cwd = getwd(),
                   tools_spec = .resolve_tool_spec(c("files", "shell")))
  ctx <- .worker_security_context_from_settings(settings, chat = NULL)
  spec <- ctx$tool_config$tools_spec
  expect_false(is.null(spec))
  expect_false(isTRUE(spec$all))
  expect_setequal(unlist(spec$native, use.names = FALSE),
                  c("Read", "Write", "Edit", "MultiEdit", "Glob", "Grep", "LS",
                    "Bash"))
})

test_that("the tools= selection survives the snapshot's JSON round trip", {
  settings <- list(permission_mode = "default", cwd = getwd(),
                   tools_spec = .resolve_tool_spec(c("lint", "docs")))
  ctx  <- .worker_security_context_from_settings(settings, chat = NULL)
  back <- jsonlite::fromJSON(jsonlite::toJSON(ctx, auto_unbox = TRUE, null = "null"),
                             simplifyVector = FALSE)
  spec <- .rehydrate_tool_spec(back$tool_config$tools_spec)
  expect_setequal(spec$native, c("Lint", "Format"))
  expect_setequal(spec$btw_groups, "docs")
  expect_false(spec$all)
})

test_that("a snapshot without tools_spec keeps the historical register-all behaviour", {
  expect_null(.rehydrate_tool_spec(NULL))
})

test_that("disallowed_tools survives the snapshot's JSON round trip", {
  settings <- list(
    permission_mode = "default", cwd = getwd(),
    disallowed_tools = .resolve_disallowed_tools(c("lint", "Bash(rm *)")))
  ctx  <- .worker_security_context_from_settings(settings, chat = NULL)
  back <- jsonlite::fromJSON(jsonlite::toJSON(ctx, auto_unbox = TRUE, null = "null"),
                             simplifyVector = FALSE)
  d <- .rehydrate_disallowed_tools(back$tool_config$disallowed_tools)
  expect_true(is.character(d$remove))
  expect_setequal(d$remove, c("Lint", "Format"))
  # The scoped deny rule travels in the snapshot's own rules list, not here,
  # so it must not be duplicated into the worker's disallowed set.
  expect_identical(d$rules, list())
})

test_that("a rehydrated disallowed set can be applied to a Chat", {
  chat <- .registry_test_chat()
  register_builtin_tools(chat, mode = "bypass")
  register_lint_tools(chat)
  before <- .registered_names(chat)
  expect_true("Lint" %in% before)
  d <- .rehydrate_disallowed_tools(list(remove = list("Lint", "Format")))
  .apply_disallowed_tools(chat, d$remove)
  expect_false(any(c("Lint", "Format") %in% .registered_names(chat)))
  expect_true("Read" %in% .registered_names(chat))
})

test_that("a sub-agent inherits the parent's tools= selection", {
  skip_if_not_installed("btw")
  parent <- codeagent_client(.registry_test_chat(), tools = c("files", "shell"),
                             permission_mode = "bypass")
  ctx <- .worker_security_context_from_settings(parent$settings, parent$chat)
  # The snapshot carries both layers: the cheap selection and the authority.
  spec <- .rehydrate_tool_spec(ctx$tool_config$tools_spec)
  expect_setequal(spec$native,
                  c("Read", "Write", "Edit", "MultiEdit", "Glob", "Grep", "LS",
                    "Bash"))
  expect_false("WebSearch" %in% ctx$allowed_tools)
  expect_true("Bash" %in% ctx$allowed_tools)
})
