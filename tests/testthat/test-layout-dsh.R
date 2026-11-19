# ui_layout = "dsh": DeepSeek-Harness-like structure on shinychat::page_chat().

dsh_page_html <- function(theme = "dsh") {
  app <- codeagent_app(theme = theme, ui_layout = "dsh", launch.browser = FALSE)
  req <- as.environment(list(PATH_INFO = "/", REQUEST_METHOD = "GET",
    HTTP_HOST = "localhost", QUERY_STRING = "",
    rook.input = list(read = function(...) raw(0))))
  app$httpHandler(req)$content
}

count_id <- function(html, id) lengths(regmatches(html, gregexpr(sprintf('id="%s"', id), html)))

test_that("the dsh layout is a page_chat layout", {
  expect_true(.uses_page_chat("dsh"))
  expect_true(.uses_page_chat("page_chat"))
  expect_false(.uses_page_chat("classic"))
})

test_that("the dsh layout places every control once, with the usual ids", {
  skip_if_not(.shinychat_page_chat_available())
  html <- dsh_page_html()
  for (id in c("perm_mode", "ca_settings_dialog",
               "token-budget-text", "ca_interaction_ui"))
    expect_identical(count_id(html, id), 1L, info = id)
  # history in the left column, controls in the composer row, settings in a dialog
  expect_match(html, 'data-sidebar-key="home"', fixed = TRUE)
  expect_match(html, "ca-dsh-composer-toolbar", fixed = TRUE)
  expect_match(html, 'data-ca-dialog="ca_settings_dialog"', fixed = TRUE)
  expect_match(html, "<dialog", fixed = TRUE)
  expect_identical(lengths(regmatches(html, gregexpr("ca_open_skills&#39;", html, fixed = TRUE))), 1L)
  # the codeagent session list is not used in this layout
  expect_false(grepl('id="session_list_ui"', html, fixed = TRUE))
})

test_that("the dsh layout works with other themes", {
  skip_if_not(.shinychat_page_chat_available())
  expect_match(dsh_page_html("default"), "ca_settings_dialog", fixed = TRUE)
})

test_that("left_sidebar_ui is assembled from the shared pieces", {
  html <- as.character(left_sidebar_ui("default", c("docs", "env"), NULL,
                                       model_choices = c(a = "x/a"), current_model = "a"))
  for (id in c("model_select", "token-budget-text", "perm_mode",
               "btw_groups_input", "session_list_ui"))
    expect_identical(count_id(html, id), 1L, info = id)
})

test_that("the settings dialog has no permission select of its own", {
  html <- as.character(.dsh_settings_dialog_ui(c("docs"), NULL))
  expect_false(grepl('id="perm_mode"', html, fixed = TRUE))
  expect_match(html, 'id="btw_groups_input"', fixed = TRUE)
})

test_that("voice input sits in the composer row in the dsh layout", {
  skip_if_not(.shinychat_page_chat_available())
  html <- dsh_page_html()
  expect_identical(count_id(html, "ca_voice_btn"), 1L)
  expect_match(html, 'ca-dsh-voice-btn" id="ca_voice_btn"', fixed = TRUE)
  # other layouts keep it in the footer
  expect_match(as.character(.skill_picker_footer(list())), 'id="ca_voice_btn"', fixed = TRUE)
  expect_false(grepl("ca_voice_btn", as.character(.skill_picker_footer(list(), voice = FALSE)), fixed = TRUE))
})

test_that("codeagent_history_options() reads the session log, per user, no eviction", {
  home <- withr::local_tempdir()
  withr::local_envvar(CODEAGENT_HOME = home)
  cwd <- withr::local_tempdir()
  opts <- codeagent_history_options(cwd)
  expect_s3_class(opts, "chat_history_config")
  expect_true(inherits(opts$store, ".SessionLogStore"))
  expect_identical(opts$store$cwd, cwd)
  expect_false(dir.exists(file.path(.get_project_session_dir(cwd), "shinychat")))
  # shinychat deletes from the store above max_store_mb: off unless asked for
  expect_null(opts$max_store_mb)
  expect_identical(codeagent_history_options(cwd, max_store_mb = 50)$max_store_mb, 50)
  expect_error(codeagent_history_options(cwd, max_store_mb = -1), "max_store_mb")
  expect_error(codeagent_history_options(cwd, max_store_mb = "a"), "max_store_mb")
  scope <- opts$scope
  expect_identical(scope(list(user = "alice")), "alice")
  expect_identical(scope(list(user = NULL)), unname(Sys.info()[["user"]]))
  expect_identical(codeagent_history_options(cwd, user = "team")$scope(list(user = "x")), "team")
})
