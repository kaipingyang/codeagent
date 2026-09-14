# Tests for the WEAR loop data-exploration report export (R/wear.R).

# Build a CodeagentClient-like stub wrapping a real ellmer chat with set turns.
.wear_fake_client <- function(turns = list()) {
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  if (length(turns)) tryCatch(chat$set_turns(turns), error = function(e) NULL)
  structure(list(chat = chat), class = "CodeagentClient")
}

test_that("generate_wear_report errors on empty history", {
  client <- .wear_fake_client(list())
  expect_error(generate_wear_report(client, path = tempfile(fileext = ".qmd")),
               "No conversation history")
})

test_that("generate_wear_report writes a valid .qmd with headings and code chunks", {
  turns <- list(
    ellmer::Turn("user", list(ellmer::ContentText("What is the mean mpg?"))),
    ellmer::Turn("assistant", list(
      ellmer::ContentText("The mean mpg is about 20."),
      ellmer::ContentToolResult(value = "20.09",
                                extra = list(code = "mean(mtcars$mpg)"))
    ))
  )
  client <- .wear_fake_client(turns)
  path   <- tempfile(fileext = ".qmd")
  ret    <- suppressMessages(generate_wear_report(client, path = path,
                                                  title = "MT Analysis"))
  expect_identical(ret, path)
  expect_true(file.exists(path))
  txt <- paste(readLines(path), collapse = "\n")
  # YAML front-matter with title
  expect_true(grepl('title: "MT Analysis"', txt, fixed = TRUE))

  # user message -> ## heading
  expect_true(grepl("## What is the mean mpg?", txt, fixed = TRUE))
  # tool code -> {r} chunk
  expect_true(grepl("```{r}", txt, fixed = TRUE))
  expect_true(grepl("mean(mtcars$mpg)", txt, fixed = TRUE))
  unlink(path)
})

test_that("register_wear_report_tool uses the stable GenerateReport name", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  codeagent:::register_wear_report_tool(chat)
  expect_true("GenerateReport" %in% names(chat$get_tools()))
})

test_that("wear_explore validates the mode argument before doing anything", {
  # match.arg() rejects an invalid mode up front (no client built, no launch).
  expect_error(wear_explore(data = list(mtcars = mtcars), mode = "not-a-mode"),
               "should be one of")
})

test_that("codeagent already prefers ellmer::df_schema over the self-written fallback", {
  # Guard: ellmer provides df_schema(); tools_data.R uses it as the primary
  # path with .df_schema() only as a fallback. If ellmer drops it, flag here.
  expect_true(exists("df_schema", where = asNamespace("ellmer")))
})


test_that("wear_explore preserves Data Shield on runtime ExploreData replacement", {
  ids <- paste0("WEARSECRET", sprintf("%03d", 1:12))
  data <- data.frame(id = ids, stringsAsFactors = FALSE)
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 0)))
  shield$register_data(data, name = "study", sensitivity = c(id = "identifier"))
  chat <- ellmer::chat_anthropic(model = "fixture")
  client <- codeagent_client(chat, permission_mode = "bypass",
                             data_shield = shield, cwd = tempdir())

  testthat::local_mocked_bindings(
    codeagent_console = function(client, ...) invisible(client),
    .package = "codeagent")
  suppressMessages(suppressWarnings(
    wear_explore(data = list(study = data), client = client, mode = "repl")))

  names <- vapply(client$chat$get_tools(), function(tool) tool@name, character(1L))
  explore <- client$chat$get_tools()[[match("ExploreData", names)]]
  outer <- S7::S7_data(explore)
  expect_identical(get0(".codeagent_data_shield_state", environment(outer),
                        inherits = FALSE), shield)
  result <- do.call(outer, list(
    data_name = "study", code = "study$id[[1]]"))
  value <- as.character(result@value)
  expect_false(grepl(ids[[1L]], value, fixed = TRUE))
  expect_match(value, "withheld|blocked")
})


test_that("wear_explore preserves PreToolUse on runtime ExploreData replacement", {
  data <- data.frame(id = paste0("HOOKSECRET", sprintf("%03d", 1:12)))
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 0)))
  shield$register_data(data, name = "study", sensitivity = c(id = "identifier"))
  hooks <- HookRegistry$new()
  hooks$register_pre(function(tool_name, tool_input) {
    if (identical(tool_name, "ExploreData"))
      list(action = "deny", message = "blocked by fixture hook") else NULL
  })
  chat <- ellmer::chat_anthropic(model = "fixture")
  client <- codeagent_client(chat, permission_mode = "bypass",
                             data_shield = shield, cwd = tempdir())
  client$settings$hooks_registry <- hooks
  marker <- tempfile("wear-hook-side-effect-")
  on.exit(unlink(marker), add = TRUE)

  testthat::local_mocked_bindings(
    codeagent_console = function(client, ...) invisible(client),
    .package = "codeagent")
  suppressMessages(suppressWarnings(
    wear_explore(data = list(study = data), client = client, mode = "repl")))

  names <- vapply(client$chat$get_tools(), function(tool) tool@name, character(1L))
  explore <- client$chat$get_tools()[[match("ExploreData", names)]]
  outer <- S7::S7_data(explore)
  inner <- get0(".codeagent_data_shield_original", environment(outer),
                inherits = FALSE)
  expect_identical(get0(".codeagent_pre_hook_state", environment(inner),
                        inherits = FALSE), hooks)
  expect_warning(
    expect_error(
      do.call(outer, list(
        data_name = "study",
        code = sprintf("writeLines('executed', %s)",
                       encodeString(marker, quote = "\"")))),
      class = "ellmer_tool_reject"),
    "tool 'ExploreData' errored"
  )
  expect_false(file.exists(marker))
})


test_that("wear_explore rolls back when a runtime Shield wrapper cannot install", {
  data <- data.frame(id = paste0("ROLLBACK", sprintf("%03d", 1:12)))
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 0)))
  shield$register_data(data, name = "study", sensitivity = c(id = "identifier"))
  chat <- ellmer::chat_anthropic(model = "fixture")
  client <- codeagent_client(chat, permission_mode = "bypass",
                             data_shield = shield, cwd = tempdir())
  old_tools <- client$chat$get_tools()

  testthat::local_mocked_bindings(
    .data_shield_wrap_tool = function(...) stop("fixture Shield wrap failure"),
    .package = "codeagent")
  expect_error(
    wear_explore(data = list(study = data), client = client, mode = "repl"),
    "fixture Shield wrap failure")
  expect_identical(client$chat$get_tools(), old_tools)
})
