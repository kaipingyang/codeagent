test_that("codeagent_progress sends start / update / done for one id", {
  sent <- list()
  session <- list(sendCustomMessage = function(type, msg) sent[[length(sent) + 1L]] <<- list(type = type, msg = msg))
  p <- codeagent_progress("t_ae_socpt_grd", step = "loading the study", typical = 61.4, session = session)
  p$update("running the template")
  p$update("rendering", typical = -1)                       # not a duration: dropped
  p$done()
  expect_true(all(vapply(sent, `[[`, "", "type") == "ca_tool_progress"))
  msgs <- lapply(sent, `[[`, "msg")
  expect_identical(vapply(msgs, `[[`, "", "action"), c("start", "update", "update", "done"))
  expect_identical(unique(vapply(msgs, `[[`, "", "id")), p$id)
  expect_identical(msgs[[1]]$typical, 61)
  expect_identical(msgs[[1]]$delay, 3)
  expect_null(msgs[[3]]$typical)
  q <- codeagent_progress("other", session = session)
  expect_false(identical(q$id, p$id))
})

test_that("codeagent_progress without a session, or with a closed one, does nothing", {
  p <- codeagent_progress("x", session = NULL)
  expect_false(p$update("y")); expect_false(p$done())
  broken <- list(sendCustomMessage = function(...) stop("closed"))
  expect_false(codeagent_progress("x", session = broken)$done())
  expect_false(.progress_clear(NULL))
})

test_that("the chat footer has the progress line and the turn end clears it", {
  ui <- as.character(codeagent_chat_ui())
  expect_match(ui, 'id="ca_tool_progress"', fixed = TRUE)
  src <- paste(deparse(body(server_chat)), collapse = "\n")
  expect_match(src, ".progress_clear(session)", fixed = TRUE)
  js <- paste(readLines(system.file("www", "agent.js", package = "codeagent")), collapse = "\n")
  expect_match(js, "ca_tool_progress", fixed = TRUE)
})

test_that("every codeagent_app layout has the progress box next to the card", {
  for (layout in c("classic", "page_chat", "dsh")) {
    app <- codeagent_app(ui_layout = layout, launch.browser = FALSE)
    req <- as.environment(list(PATH_INFO = "/", REQUEST_METHOD = "GET", HTTP_HOST = "localhost",
      QUERY_STRING = "", rook.input = list(read = function(...) raw(0))))
    html <- app$httpHandler(req)$content
    expect_identical(lengths(regmatches(html, gregexpr('id="ca_tool_progress"', html, fixed = TRUE))), 1L,
                     info = layout)
    expect_lt(regexpr('id="ca_tool_progress"', html)[[1]], regexpr('id="ca_interaction_ui"', html)[[1]])
  }
  js <- paste(readLines(system.file("www", "interaction.js", package = "codeagent")), collapse = "\n")
  expect_match(js, "placeProgress", fixed = TRUE)
})
