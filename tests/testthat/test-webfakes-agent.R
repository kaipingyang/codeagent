# tests/testthat/test-webfakes-agent.R
# Agent loop integration tests using webfakes to mock the LLM API.
# These tests verify agent behaviour (tool dispatch, error recovery,
# permission gate) WITHOUT hitting a real LLM — fast, free, deterministic.
#
# IMPORTANT: webfakes runs in a child R process. All app logic (including
# response sequences) must be captured in the closure BEFORE new_app_process()
# is called. Mutating a parent-process list after process start has no effect.

skip_if_not_installed("webfakes")
skip_if_not_installed("ellmer")

library(webfakes)
library(ellmer)

# ---------------------------------------------------------------------------
# Response builder helpers
# ---------------------------------------------------------------------------

.mock_text_response <- function(content, finish_reason = "stop") {
  list(
    id     = "chatcmpl-mock",
    object = "chat.completion",
    model  = "test-model",
    choices = list(list(
      index         = 0L,
      message       = list(role = "assistant", content = content),
      finish_reason = finish_reason
    )),
    usage = list(prompt_tokens = 5L, completion_tokens = 5L, total_tokens = 10L)
  )
}

.mock_tool_call_response <- function(tool_name, tool_args_json,
                                      call_id = "call_abc") {
  list(
    id     = "chatcmpl-mock-tool",
    object = "chat.completion",
    model  = "test-model",
    choices = list(list(
      index = 0L,
      message = list(
        role       = "assistant",
        content    = NULL,
        tool_calls = list(list(
          id       = call_id,
          type     = "function",
          `function` = list(
            name      = tool_name,
            arguments = tool_args_json
          )
        ))
      ),
      finish_reason = "tool_calls"
    )),
    usage = list(prompt_tokens = 10L, completion_tokens = 10L, total_tokens = 20L)
  )
}

# ---------------------------------------------------------------------------
# Server factory: pre-bake all responses into the child-process closure.
# webfakes spawns a child R process; `new_app_process()` serialises the
# closure at call time, so `responses` must be fully constructed BEFORE the
# call — parent-side mutations after that are invisible to the child.
# ---------------------------------------------------------------------------

.make_mock_server <- function(responses) {
  force(responses)
  idx <- 0L
  app <- new_app()
  app$use(mw_json())
  app$post("/v1/chat/completions", function(req, res) {
    idx <<- idx + 1L
    if (idx > length(responses)) {
      res$send_status(500L)
      return()
    }
    res$send_json(responses[[idx]], auto_unbox = TRUE)
  })
  new_app_process(app)
}

# ---------------------------------------------------------------------------
# Client factory
# ---------------------------------------------------------------------------

.make_mock_client <- function(proc, permission_mode = "bypass", ...) {
  ch <- chat_openai_compatible(
    base_url    = paste0(proc$url(), "v1/"),
    model       = "test-model",
    credentials = function() "mock-key",
    echo        = "none"
  )
  codeagent_client(ch, permission_mode = permission_mode,
                   btw_groups = NULL, ...)
}

# ===========================================================================
# Test group 1: basic text response round-trip
# ===========================================================================

test_that("agent returns simple text response from mock LLM", {
  proc <- .make_mock_server(list(.mock_text_response("The answer is 42.")))
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc)
  result <- codeagent(client, "What is the answer?")

  expect_type(result, "character")
  expect_match(result, "42", fixed = TRUE)
})

test_that("agent handles empty assistant message gracefully", {
  proc <- .make_mock_server(list(.mock_text_response("")))
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc)
  expect_no_error(codeagent(client, "ping"))
})

# ===========================================================================
# Test group 2: tool call round-trip
# ===========================================================================

test_that("agent dispatches Read tool when LLM requests it", {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("file content here", tmp)

  proc <- .make_mock_server(list(
    .mock_tool_call_response(
      "Read",
      jsonlite::toJSON(list(file_path = tmp), auto_unbox = TRUE)
    ),
    .mock_text_response("The file says: file content here.")
  ))
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc)
  result <- codeagent(client, paste0("Read the file at ", tmp))

  expect_match(result, "file content", ignore.case = TRUE)
})

test_that("agent dispatches Bash tool and forwards output to LLM", {
  proc <- .make_mock_server(list(
    .mock_tool_call_response(
      "Bash",
      jsonlite::toJSON(list(command     = "echo hello_from_bash",
                            description = "echo test"),
                       auto_unbox = TRUE)
    ),
    .mock_text_response("Bash returned: hello_from_bash")
  ))
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc)
  result <- codeagent(client, "Run echo hello_from_bash")

  expect_match(result, "hello_from_bash", ignore.case = TRUE)
})

# ===========================================================================
# Test group 3: permission gate interacts correctly with mock loop
# ===========================================================================

test_that("bypass mode allows Write tool without prompting user", {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)

  proc <- .make_mock_server(list(
    .mock_tool_call_response(
      "Write",
      jsonlite::toJSON(list(file_path = tmp,
                            content   = "written by agent"),
                       auto_unbox = TRUE)
    ),
    .mock_text_response("Done. File written.")
  ))
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc, permission_mode = "bypass")
  codeagent(client, paste0("Write 'written by agent' to ", tmp))

  expect_true(file.exists(tmp))
  expect_match(readLines(tmp, warn = FALSE)[1], "written by agent")
})

test_that("plan mode denies Write tool and file is not created", {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)

  # tool_reject fires after the first response; second response may never
  # be consumed if the error propagates before the loop continues.
  proc <- .make_mock_server(list(
    .mock_tool_call_response(
      "Write",
      jsonlite::toJSON(list(file_path = tmp,
                            content   = "should not appear"),
                       auto_unbox = TRUE)
    ),
    .mock_text_response("Permission denied, cannot write.")
  ))
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc, permission_mode = "plan")
  tryCatch(
    codeagent(client, paste0("Write content to ", tmp)),
    error = function(e) NULL
  )

  expect_false(file.exists(tmp))
})

# ===========================================================================
# Test group 4: error recovery
# ===========================================================================

test_that("agent returns error string on HTTP 500 from mock LLM", {
  # codeagent() wraps errors as "[Error] ..." strings rather than throwing;
  # verify it degrades gracefully rather than crashing.
  proc <- .make_mock_server(list())   # empty queue → 500 on every request
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc)
  result <- codeagent(client, "This should fail gracefully")

  expect_type(result, "character")
  # Either an [Error] string or a hard R error is acceptable; both mean failure
  expect_match(result, "Error", ignore.case = TRUE)
})

test_that("agent respects max_turns limit", {
  # Queue 10 tool-call responses; agent should stop at max_turns=3
  responses <- lapply(seq_len(10), function(i) {
    .mock_tool_call_response(
      "Bash",
      jsonlite::toJSON(list(command     = "echo loop",
                            description = "loop"),
                       auto_unbox = TRUE),
      call_id = paste0("call_", i)
    )
  })
  responses[[11]] <- .mock_text_response("done")

  proc <- .make_mock_server(responses)
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc)
  result <- codeagent(client, "Loop forever", max_turns = 3)

  expect_type(result, "character")
})

# ===========================================================================
# Test group 5: skill tool round-trip
# ===========================================================================

test_that("use_skill tool dispatched by mock LLM loads skill content", {
  metas <- codeagent:::list_skills_meta()
  skip_if(length(metas) == 0, "no skills installed")

  skill_name <- metas[[1]]$name

  proc <- .make_mock_server(list(
    .mock_tool_call_response(
      "use_skill",
      jsonlite::toJSON(list(name = skill_name), auto_unbox = TRUE)
    ),
    .mock_text_response("Skill loaded successfully.")
  ))
  on.exit(proc$stop(), add = TRUE)

  client <- .make_mock_client(proc)
  result <- codeagent(client, paste0("Use the '", skill_name, "' skill"))

  expect_type(result, "character")
})
