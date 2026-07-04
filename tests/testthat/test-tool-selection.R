# Tests for selectable file-tool sets (core/btw/both) and btw task reuse.
# See references/plan/14-tool-reuse-and-selection.md.

test_that(".resolve_file_tools maps settings + legacy option", {
  expect_identical(.resolve_file_tools(list()), "core")
  expect_identical(.resolve_file_tools(list(file_tools = "btw")), "btw")
  expect_identical(.resolve_file_tools(list(file_tools = "both")), "both")
  withr::local_options(codeagent.use_btw_files = TRUE)
  expect_identical(.resolve_file_tools(list()), "both")            # legacy alias
  expect_identical(.resolve_file_tools(list(file_tools = "core")), "core")  # explicit wins
})

.tool_names <- function(chat) {
  tls <- tryCatch(chat$get_tools(), error = function(e) list())
  unlist(lapply(tls, function(t) tryCatch(t@name, error = function(e) NA_character_)))
}

test_that("register_builtin_tools skip_file_tools drops the core file tools", {
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  register_builtin_tools(chat, mode = "bypass", skip_file_tools = TRUE)
  nm <- .tool_names(chat)
  expect_false(any(c("Read", "Write", "Edit", "MultiEdit") %in% nm))

  chat2 <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                          credentials = function() "k")
  register_builtin_tools(chat2, mode = "bypass", skip_file_tools = FALSE)
  nm2 <- .tool_names(chat2)
  expect_true(all(c("Read", "Write", "Edit") %in% nm2))
})

test_that("register_btw_task_tools is opt-in and reuses btw (no reinvention)", {
  skip_if_not_installed("btw")
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  before <- length(.tool_names(chat))
  # disabled by default -> no change
  register_btw_task_tools(chat, list())
  expect_identical(length(.tool_names(chat)), before)
  # enabled -> adds btw task tools
  register_btw_task_tools(chat, list(btw_tasks = TRUE))
  expect_gt(length(.tool_names(chat)), before)
})

test_that("codeagent_task wrappers are exported and delegate to btw", {
  expect_true(is.function(codeagent_task))
  expect_true(is.function(codeagent_create_skill))
  expect_true(is.function(codeagent_create_readme))
  expect_true(is.function(codeagent_init_context))
  # .as_ellmer_chat passes a Chat through and extracts $chat from a client-like
  ch <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                       credentials = function() "k")
  expect_identical(.as_ellmer_chat(ch), ch)
  expect_identical(.as_ellmer_chat(list(chat = ch)), ch)
  expect_null(.as_ellmer_chat(NULL))
})
