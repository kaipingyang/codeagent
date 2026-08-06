# End-to-end async (Shiny) permission-approval coverage, split into deterministic
# halves (avoids the flaky promise-flush-inside-testServer combo):
#   (a) the central gate maps the ask_fn promise: resolve(TRUE) -> allow,
#       resolve(FALSE) -> ellmer_tool_reject;
#   (b) server_interaction's Allow/Deny observers resolve the pending interaction
#       with the right value and clear it.
# Together they prove: click Allow -> tool runs; click Deny -> tool rejected.

test_that("async gate maps ask_fn resolve -> allow / reject", {
  make_gate <- function() {
    rf <- NULL
    ask <- function(n, i) promises::promise(function(resolve, reject) rf <<- resolve)
    list(gate = .tool_gate_fn(list(overrides = list(), capabilities = list(write = "ask")),
                              "default", list(), ask_fn = ask, hooks = NULL),
         resolver = function() rf)
  }
  req <- ellmer::ContentToolRequest(id = "1", name = "Write",
           arguments = list(file_path = "x", content = "y"))

  # Allow
  m <- make_gate(); res <- m$gate(req); out <- new.env(); out$v <- "pending"
  promises::then(res, function(v) out$v <- "ALLOW",
    function(e) out$v <- if (inherits(e, "ellmer_tool_reject")) "REJECT" else "ERR")
  m$resolver()(TRUE); for (i in 1:50) later::run_now(0.02)
  expect_identical(out$v, "ALLOW")

  # Deny
  m2 <- make_gate(); res2 <- m2$gate(req); o2 <- new.env(); o2$v <- "pending"
  promises::then(res2, function(v) o2$v <- "ALLOW",
    function(e) o2$v <- if (inherits(e, "ellmer_tool_reject")) "REJECT" else "ERR")
  m2$resolver()(FALSE); for (i in 1:50) later::run_now(0.02)
  expect_identical(o2$v, "REJECT")
})

test_that(".resolve_pending resolves with the value and clears (idempotent)", {
  state <- shiny::reactiveValues(pending_interaction = NULL)
  captured <- new.env(); captured$v <- "none"
  shiny::isolate(state$pending_interaction <- list(
    type = "approval", payload = list(), resolve = function(v) captured$v <- v))
  expect_true(.resolve_pending(state, TRUE))
  expect_identical(captured$v, TRUE)
  expect_null(shiny::isolate(state$pending_interaction))
  expect_false(.resolve_pending(state, TRUE))   # nothing pending -> no-op
})

test_that("server_interaction Allow/Deny observers clear the pending interaction", {
  skip_if_not_installed("shiny")
  testthat::local_mocked_bindings(
    chat_append_message = function(...) invisible(NULL), .package = "shinychat")

  # Allow
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    session$userData$state$pending_interaction <- list(
      type = "approval", payload = list(tool_name = "Write"),
      resolve = function(v) NULL)
    session$flushReact()
    session$setInputs(ca_tool_allow = 1)
    expect_null(shiny::isolate(session$userData$state$pending_interaction))
  })

  # Deny
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    session$userData$state$pending_interaction <- list(
      type = "approval", payload = list(tool_name = "Bash"),
      resolve = function(v) NULL)
    session$flushReact()
    session$setInputs(ca_tool_deny = 1)
    expect_null(shiny::isolate(session$userData$state$pending_interaction))
  })
})


test_that("server_interaction egress observers resolve redact/block/raw safely", {
  run_choice <- function(input_name, allow_raw=FALSE) {
    resolved <- new.env(); resolved$value <- NULL
    shiny::testServer(function(input,output,session) {
      state <- shiny::reactiveValues(pending_interaction=NULL)
      server_interaction(input,output,session,state)
      session$userData$state <- state
    }, {
      session$userData$state$pending_interaction <- list(
        type="egress",payload=list(allow_raw_approval=allow_raw),
        resolve=function(v) resolved$value <- v)
      session$flushReact()
      do.call(session$setInputs,stats::setNames(list(1),input_name))
      expect_null(shiny::isolate(session$userData$state$pending_interaction))
    })
    resolved$value
  }
  expect_identical(run_choice("ca_egress_redact"),"redact")
  expect_identical(run_choice("ca_egress_block"),"block")
  expect_identical(run_choice("ca_egress_raw",TRUE),"raw_once")
  expect_identical(run_choice("ca_egress_raw",FALSE),"redact")
})


test_that("Shiny egress ask promise resolves choice and timeout safely", {
  run <- function(event, click=NULL) {
    value <- NULL; done <- FALSE
    shiny::testServer(function(input,output,session) {
      state <- shiny::reactiveValues(pending_interaction=NULL)
      interaction <- server_interaction(input,output,session,state)
      session$userData$state <- state; session$userData$interaction <- interaction
    }, {
      p <- session$userData$interaction$egress_ask_fn(event)
      promises::then(p,function(x){value <<- x;done <<- TRUE})
      session$flushReact()
      if (!is.null(click)) do.call(session$setInputs,stats::setNames(list(1),click))
      for(i in 1:200){later::run_now(0.01);if(done)break}
      expect_true(done)
      expect_null(shiny::isolate(session$userData$state$pending_interaction))
    })
    value
  }
  event <- list(tool_name="Dump",strategy="row_cap",reason="bulk",
                match_count=10L,allow_raw_approval=TRUE,timeout=1)
  expect_identical(run(event,"ca_egress_raw"),"raw_once")
  event$timeout <- 0.01
  expect_identical(run(event),"redact")
})
