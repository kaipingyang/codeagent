# Task 09: official shinychat slash-command typeahead (standalone driver).
# We can't easily unit-test the client protocol, so we test the definition
# builder and the input-selection reconstruction contract.

test_that(".slash_command_defs: local commands echo=FALSE, skills echo=TRUE", {
  defs <- .slash_command_defs(getwd())
  expect_true(length(defs) > 0)
  nms <- vapply(defs, function(d) d$name, character(1))
  expect_true("model" %in% nms)     # local command
  expect_true("compact" %in% nms)
  # every def has name/description/echo
  for (d in defs) {
    expect_true(all(c("name", "description", "echo") %in% names(d)))
  }
  # Local commands: echo=FALSE (we render bubble+result ourselves, no AI wait).
  # Skills: echo=TRUE (shinychat renders the user bubble + awaitResponse; skills
  # do call the LLM).
  for (d in defs) {
    if (d$name %in% .LOCAL_COMMANDS) {
      expect_false(isTRUE(d$echo), info = paste("local", d$name, "should be echo=FALSE"))
    } else {
      expect_true(isTRUE(d$echo), info = paste("skill", d$name, "should be echo=TRUE"))
    }
  }
  # names are unique (dedup of command/skill overlap)
  expect_identical(anyDuplicated(nms), 0L)
})

test_that(".slash_command_defs names are valid slash-command tokens", {
  defs <- .slash_command_defs(getwd())
  nms  <- vapply(defs, function(d) d$name, character(1))
  # shinychat requires ^[a-zA-Z0-9_-]+$
  expect_true(all(grepl("^[a-zA-Z0-9_-]+$", nms)))
})

test_that(".send_slash_commands posts the update_slash_commands action", {
  sent <- NULL
  fake_session <- list(
    ns = function(x) x,
    sendCustomMessage = function(type, message) {
      sent <<- list(type = type, message = message)
    }
  )
  ok <- .send_slash_commands(fake_session, cwd = getwd(), id = "chat")
  expect_true(ok)
  expect_identical(sent$type, "shinyChatMessage")
  expect_identical(sent$message$id, "chat")
  expect_identical(sent$message$action$type, "update_slash_commands")
  expect_true(length(sent$message$action$commands) > 0)
})

# ---------------------------------------------------------------------------
# .slash_parse_selection: direct-dispatch routing (regression for the
# "re-submit /command gets re-recognised as slash and dropped" bug).
# ---------------------------------------------------------------------------

test_that(".slash_parse_selection routes local commands to type=command", {
  for (cmd in .LOCAL_COMMANDS) {
    p <- .slash_parse_selection(list(command = cmd, userText = ""))
    expect_identical(p$type, "command")
    expect_identical(p$name, cmd)
    expect_identical(p$args, "")
  }
})

test_that(".slash_parse_selection routes non-local commands to type=skill", {
  p <- .slash_parse_selection(list(command = "plan", userText = "add a tool"))
  expect_identical(p$type, "skill")
  expect_identical(p$name, "plan")
  expect_identical(p$args, "add a tool")
})

test_that(".slash_parse_selection preserves userText as args", {
  p <- .slash_parse_selection(list(command = "explain", userText = "ellmer"))
  expect_identical(p$args, "ellmer")
})

test_that(".slash_parse_selection returns NULL for empty/invalid input", {
  expect_null(.slash_parse_selection(NULL))
  expect_null(.slash_parse_selection(list()))
  expect_null(.slash_parse_selection(list(command = "")))
  expect_null(.slash_parse_selection(list(command = character(0))))
  expect_null(.slash_parse_selection("not-a-list"))
})

test_that(".slash_parse_selection defaults missing/invalid userText to empty", {
  p1 <- .slash_parse_selection(list(command = "model"))          # no userText
  expect_identical(p1$args, "")
  p2 <- .slash_parse_selection(list(command = "model", userText = NULL))
  expect_identical(p2$args, "")
})

# ---------------------------------------------------------------------------
# Regression contract for the bug being fixed: the dispatch must NOT rebuild a
# "/command" string for LOCAL commands (old code re-submitted it via
# update_chat_user_input, which shinychat re-recognised as a slash command and
# dropped). Local commands carry type="command" so the observer runs them via
# .handle_chat_command directly; only skills rebuild "/name args" for the
# stream_task. We assert that partition here from the pure parser.
# ---------------------------------------------------------------------------

test_that("local commands never need a re-submitted '/command' string", {
  # For every local command, the router marks type=command -> handled directly,
  # so the observer's skill-only rebuild branch is never taken.
  for (cmd in .LOCAL_COMMANDS) {
    p <- .slash_parse_selection(list(command = cmd, userText = "x"))
    expect_identical(p$type, "command")
  }
})

test_that("skill rebuild string matches the '/name args' contract", {
  # The observer builds this string only for skills; verify the shape.
  p <- .slash_parse_selection(list(command = "plan", userText = "add a tool"))
  val <- paste0("/", p$name, if (nzchar(p$args)) paste0(" ", p$args) else "")
  expect_identical(val, "/plan add a tool")

  p0 <- .slash_parse_selection(list(command = "verify", userText = ""))
  val0 <- paste0("/", p0$name, if (nzchar(p0$args)) paste0(" ", p0$args) else "")
  expect_identical(val0, "/verify")
})


test_that(".truncate_desc shortens long descriptions with an ellipsis", {
  expect_identical(.truncate_desc("short"), "short")
  long <- strrep("x", 200)
  out <- .truncate_desc(long, n = 72L)
  expect_lte(nchar(out), 72L)
  expect_true(grepl("\u2026$", out))
  # newlines collapsed to single line
  expect_false(grepl("[\r\n]", .truncate_desc("a\nb\nc")))
})
