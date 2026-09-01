# tests/testthat/test-page-chat-ui.R
# Contracts for the opt-in shinychat page_chat workspace (Plan 38).

test_that("codeagent_app exposes a classic-first ui_layout argument", {
  fmls <- formals(codeagent_app)
  expect_true("ui_layout" %in% names(fmls))
  expect_identical(eval(fmls$ui_layout), c("classic", "page_chat"))
  expect_identical(tail(names(fmls), 1L), "ui_layout")
})

test_that("page_chat UI composes the codeagent sidebar and workspace drawer", {
  skip_if_not(
    codeagent:::.shinychat_page_chat_available(),
    "installed shinychat does not provide the page_chat drawer APIs"
  )
  sidebar <- bslib::sidebar(
    htmltools::tags$div(id = "fixture-page-chat-sidebar", "controls")
  )
  workspace <- htmltools::tags$div(id = "ca_page_chat_workspace", "workspace")
  ui <- codeagent:::.codeagent_page_chat_ui(
    theme = bslib::bs_theme(),
    sidebar = sidebar,
    workspace = workspace,
    chat_args = list(
      enable_cancel = TRUE,
      submit_key = "enter",
      tool_grouping = "tool",
      allow_attachments = TRUE,
      placeholder = "Ask codeagent..."
    )
  )
  html <- as.character(htmltools::renderTags(ui)$html)
  expect_match(html, "fixture-page-chat-sidebar", fixed = TRUE)
  expect_match(html, "ca_page_chat_workspace", fixed = TRUE)
  expect_match(html, "Ask codeagent...", fixed = TRUE)
  expect_match(html, "--_chat-width:100%", fixed = TRUE)
})


test_that("page_chat UI fails fast with an actionable capability error", {
  testthat::local_mocked_bindings(
    .shinychat_page_chat_available = function() FALSE
  )
  expect_error(
    codeagent:::.codeagent_page_chat_ui(NULL, NULL, NULL),
    "page_chat.*drawer control API.*DESCRIPTION"
  )
})


test_that("page_chat keeps global dark mode and exposes a workspace drawer toggle", {
  skip_if_not(codeagent:::.shinychat_page_chat_available())
  ui <- codeagent:::.codeagent_page_chat_ui(
    theme = bslib::bs_theme(),
    sidebar = bslib::sidebar("controls"),
    workspace = htmltools::tags$div("workspace")
  )
  html <- as.character(htmltools::renderTags(ui)$html)
  expect_match(html, "ca_workspace_toggle", fixed = TRUE)
  expect_match(html, "bslib-toolbar-input-button", fixed = TRUE)
  expect_match(html, "ca_dark_mode", fixed = TRUE)
})

test_that("drawer action helper covers all four official server APIs", {
  called <- character()
  fake_export <- function(name) {
    force(name)
    function(...) called <<- c(called, name)
  }
  testthat::local_mocked_bindings(.shinychat_export = fake_export)
  for (action in c("show", "update", "hide", "toggle"))
    codeagent:::.shinychat_drawer_action("chat", action, session = list())
  expect_identical(called, paste0("chat_drawer_", c("show", "update", "hide", "toggle")))
})


test_that("page_chat can omit the duplicate sidebar dark-mode input", {
  args <- list(
    permission_mode = "default",
    btw_available_groups = character(),
    btw_groups_selected = character(),
    model_choices = character(),
    current_model = NULL
  )
  classic <- do.call(codeagent:::left_sidebar_ui, c(args, list(show_dark_mode = TRUE)))
  page <- do.call(codeagent:::left_sidebar_ui, c(args, list(show_dark_mode = FALSE)))
  expect_match(as.character(htmltools::renderTags(classic)$html),
               "ca_dark_mode", fixed = TRUE)
  expect_no_match(as.character(htmltools::renderTags(page)$html),
                  "ca_dark_mode", fixed = TRUE)
})


test_that("classic chat disables shinychat-owned drawer and history UI", {
  ui <- codeagent:::chat_codeagent_ui(list(), submit_key = "enter")
  html <- as.character(htmltools::renderTags(ui)$html)
  expect_match(html, "show-history=\"false\"", fixed = TRUE)
  expect_no_match(html, "<shiny-chat-drawer", fixed = TRUE)
})
