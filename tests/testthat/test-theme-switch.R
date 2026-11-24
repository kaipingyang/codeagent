test_that("codeagent_theme_ui is a radio group of theme names", {
  ui <- as.character(codeagent_theme_ui())
  expect_match(ui, 'id="ca_theme"', fixed = TRUE)
  expect_match(ui, 'value="dsh"', fixed = TRUE)
  expect_match(ui, 'class="ca-theme-switch small"', fixed = TRUE)
  ui2 <- as.character(codeagent_theme_ui(c(Light = "a", Dark = "b"), selected = "b"))
  expect_match(ui2, 'value="b" checked', fixed = TRUE)
  expect_error(codeagent_theme_ui(c("a", "b")), "named character vector")
  expect_error(codeagent_theme_ui(c(A = "x", B = "x")), "named character vector")
})

test_that("themes are validated: a bslib theme or a codeagent_theme() style per name", {
  expect_true(.check_host_themes(list(default = bslib::bs_theme(version = 5), dsh = "dsh")))
  expect_error(.check_host_themes(list(bslib::bs_theme())), "named list")
  expect_error(.check_host_themes(list(a = 1)), "bslib theme or a codeagent_theme")
  expect_s3_class(.resolve_host_theme("dsh"), "bs_theme")
})

test_that("switching sets the session's theme once per choice and tells the host", {
  set <- list(); told <- character()
  dflt <- bslib::bs_theme(version = 5)
  shiny::testServer(function(input, output, session) {
    session$setCurrentTheme <- function(theme) set[[length(set) + 1L]] <<- theme
    .serve_host_themes(input, session, list(default = dflt, dsh = "dsh"),
                       on_theme = function(name) told <<- c(told, name))
  }, {
    session$setInputs(ca_theme = "default")      # the start value: nothing applied (ignoreInit)
    session$setInputs(ca_theme = "dsh")
    session$setInputs(ca_theme = "default")
    session$setInputs(ca_theme = "nope")         # not a theme of the host: ignored
  })
  expect_identical(told, c("dsh", "default"))
  expect_length(set, 2L)
  expect_true(inherits(set[[1]], "bs_theme"))
  expect_identical(set[[2]], dflt)
})

test_that("codeagent_server validates themes / on_theme; the stylesheet fix ships in agent.js", {
  expect_error(codeagent_server(NULL, NULL, NULL, client = structure(list(), class = "x")), "CodeagentClient")
  src <- paste(deparse(body(codeagent_server)), collapse = "\n")
  expect_match(src, ".check_host_themes(themes)", fixed = TRUE)
  expect_match(src, ".serve_host_themes(input, session, themes, on_theme)", fixed = TRUE)
  js <- paste(readLines(system.file("www", "agent.js", package = "codeagent")), collapse = "\n")
  expect_match(js, "restyle=", fixed = TRUE)
  expect_match(js, "document.head.appendChild(el)", fixed = TRUE)
})
