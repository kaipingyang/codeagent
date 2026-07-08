test_that(".interaction_bar_ui returns NULL when nothing is pending", {
  expect_null(codeagent:::.interaction_bar_ui(NULL))
  expect_null(codeagent:::.interaction_bar_ui(list(type = "other")))
})

test_that(".interaction_bar_ui builds an Allow/Deny bar for approvals", {
  pending <- list(
    type    = "approval",
    payload = list(tool_name = "Bash", tool_input = list(command = "rm -rf /tmp/x"))
  )
  ui   <- codeagent:::.interaction_bar_ui(pending)
  html <- as.character(ui)
  expect_true(grepl("ca_tool_allow", html))
  expect_true(grepl("ca_tool_deny", html))
  expect_true(grepl("Bash", html))
  expect_true(grepl("rm -rf", html))   # command shown in the description
})

test_that(".interaction_bar_ui truncates long approval descriptions", {
  long <- paste(rep("x", 200), collapse = "")
  ui   <- codeagent:::.interaction_bar_ui(list(
    type = "approval",
    payload = list(tool_name = "Bash", tool_input = list(command = long))
  ))
  html <- as.character(ui)
  # substr(desc, 1, 80) -> at most 80 x's shown, not 200.
  expect_false(grepl(paste(rep("x", 100), collapse = ""), html))
})

test_that(".interaction_bar_ui builds radio choices for a question with options", {
  ui <- codeagent:::.interaction_bar_ui(list(
    type = "question",
    payload = list(question = "Pick one", choices = c("a", "b", "c"))
  ))
  html <- as.character(ui)
  expect_true(grepl("ca_q_choice", html))
  expect_true(grepl("ca_q_submit", html))
  expect_true(grepl("Pick one", html))
})

test_that(".interaction_bar_ui builds a free-text input for a choiceless question", {
  ui <- codeagent:::.interaction_bar_ui(list(
    type = "question",
    payload = list(question = "Your name?", choices = character(0))
  ))
  html <- as.character(ui)
  expect_true(grepl("ca_q_text", html))
  expect_false(grepl("ca_q_choice", html))
})

test_that(".interaction_cancel_value denies approvals, blanks questions", {
  expect_false(codeagent:::.interaction_cancel_value(list(type = "approval")))
  expect_identical(codeagent:::.interaction_cancel_value(list(type = "question")), "")
  expect_null(codeagent:::.interaction_cancel_value(NULL))
})

test_that(".resolve_pending resolves the stored promise once and clears the slot", {
  resolved <- new.env(parent = emptyenv())
  resolved$value <- NULL
  resolved$calls <- 0L
  st <- new.env(parent = emptyenv())
  st$pending_interaction <- list(
    type    = "approval",
    resolve = function(v) { resolved$value <- v; resolved$calls <- resolved$calls + 1L }
  )

  ok <- codeagent:::.resolve_pending(st, TRUE)
  expect_true(ok)
  expect_true(resolved$value)
  expect_null(st$pending_interaction)          # slot cleared
  expect_equal(resolved$calls, 1L)

  # Second call is a no-op (nothing pending).
  expect_false(codeagent:::.resolve_pending(st, FALSE))
  expect_equal(resolved$calls, 1L)
})
