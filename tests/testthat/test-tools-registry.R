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
