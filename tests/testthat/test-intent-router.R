test_that("route_intent: force / hint / unknown tool / router error", {
  ch <- ellmer::chat_openai_compatible(base_url = "http://localhost:1", model = "m", credentials = function() "k")
  tools <- c("combine_groups", "AskUserForm")
  f <- function(d) function(text, last_reply) d
  expect_identical(.route_intent(f(list(tool = "combine_groups", mode = "force")), ch, "x", tools)$force, "combine_groups")
  h <- .route_intent(f(list(tool = "AskUserForm", mode = "hint")), ch, "x", tools)
  expect_null(h$force); expect_match(h$hint, "AskUserForm")
  expect_null(.route_intent(f(list(tool = "nope", mode = "force")), ch, "x", tools)$force)
  expect_null(.route_intent(function(...) stop("boom"), ch, "x", tools)$force)
  expect_null(.route_intent(f(list(tool = "combine_groups", mode = "force")), ch, "  ", tools)$force)
})

test_that("a forced first tool is set on the chat's model and cleared", {
  ch <- ellmer::chat_openai_compatible(base_url = "http://localhost:1", model = "m", credentials = function() "k")
  st <- new.env()
  expect_true(.force_first_tool(ch, st, "combine_groups"))
  m <- ch$.__enclos_env__$private$model
  expect_identical(m@extra_args$tool_choice$`function`$name, "combine_groups")
  expect_identical(st$forced, "combine_groups")
  .clear_forced_tool(ch, st)
  expect_null(ch$.__enclos_env__$private$model@extra_args$tool_choice)
  expect_null(st$forced)
})

test_that("codeagent_server validates intent_router", {
  expect_true("intent_router" %in% names(formals(codeagent_server)))
  src <- paste(deparse(body(codeagent_server)), collapse = "\n")
  expect_match(src, "on_tool_request", fixed = TRUE)
})
