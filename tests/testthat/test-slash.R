# Task 09: official shinychat slash-command typeahead (standalone driver).
# We can't easily unit-test the client protocol, so we test the definition
# builder and the input-selection reconstruction contract.

test_that(".slash_command_defs includes local commands + skills, echo=FALSE", {
  defs <- .slash_command_defs(getwd())
  expect_true(length(defs) > 0)
  nms <- vapply(defs, function(d) d$name, character(1))
  expect_true("model" %in% nms)     # local command
  expect_true("compact" %in% nms)
  # every def has name/description/echo and echo is FALSE
  for (d in defs) {
    expect_true(all(c("name", "description", "echo") %in% names(d)))
    expect_false(isTRUE(d$echo))
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
