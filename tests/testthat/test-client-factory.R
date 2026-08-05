# Multi-user session factory contract for codeagent_app().

.make_factory_client <- function() {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  codeagent_client(chat, register_tools = FALSE,
                   data_shield = data_shield(max_rows = 0L))
}

test_that("client_factory is invoked per session and returns isolated clients", {
  made <- list()
  factory <- function(session) {
    client <- .make_factory_client()
    made[[length(made) + 1L]] <<- client
    client
  }
  session_a <- new.env(); session_b <- new.env()
  client_a <- codeagent:::.invoke_codeagent_client_factory(factory, session_a)
  client_b <- codeagent:::.invoke_codeagent_client_factory(factory, session_b)

  expect_length(made, 2L)
  expect_false(identical(client_a$chat, client_b$chat))
  expect_false(identical(client_a$data_shield, client_b$data_shield))
  expect_false(identical(client_a$data_shield$index, client_b$data_shield$index))
})

test_that("zero-argument client_factory remains supported", {
  client <- codeagent:::.invoke_codeagent_client_factory(
    function() .make_factory_client(), new.env())
  expect_s3_class(client, "CodeagentClient")
})

test_that("client_factory must return CodeagentClient", {
  expect_error(
    codeagent:::.invoke_codeagent_client_factory(function() list(), new.env()),
    "CodeagentClient")
})

test_that("codeagent_app accepts client_factory and rejects ambiguous inputs", {
  factory <- function(session) .make_factory_client()
  app <- codeagent_app(client_factory = factory, launch.browser = FALSE)
  expect_s3_class(app, "shiny.appobj")

  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  expect_error(
    codeagent_app(client = chat, client_factory = factory, launch.browser = FALSE),
    "only one")
})


test_that("codeagent_app creates a distinct client per Shiny session", {
  created <- list()
  factory <- function(session) {
    client <- .make_factory_client()
    client$chat$register_tool(ellmer::tool(
      function() "ok", name = "Ping", description = "d", arguments = list()))
    install_data_shield(client)
    created[[length(created) + 1L]] <<- client
    client
  }
  app <- codeagent_app(client_factory = factory, launch.browser = FALSE)
  server <- app$serverFuncSource()

  shiny::testServer(server, { session$flushReact() })
  shiny::testServer(server, { session$flushReact() })

  expect_length(created, 2L)
  expect_false(identical(created[[1L]]$chat, created[[2L]]$chat))
  expect_false(identical(created[[1L]]$data_shield,
                         created[[2L]]$data_shield))
})


test_that("bare Chat template is cloned into distinct per-session clients", {
  template <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  factory <- codeagent:::.codeagent_chat_template_factory(
    template, permission_mode = "default", cwd = getwd(), btw_groups = NULL)
  client_a <- factory(new.env())
  client_b <- factory(new.env())

  expect_false(identical(client_a$chat, client_b$chat))
  expect_false(identical(client_a$chat, template))
  expect_false(identical(client_b$chat, template))
})
