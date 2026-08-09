test_that(".tool_capability classifies tools (unknown -> read/allow)", {
  expect_identical(.tool_capability("Write"), "write")
  expect_identical(.tool_capability("Read"), "read")
  expect_identical(.tool_capability("Bash"), "exec")
  expect_identical(.tool_capability("Format"), "write")
  expect_identical(.tool_capability("btw_tool_git_commit"), "write")
  expect_identical(.tool_capability("btw_tool_github"), "net")
  expect_identical(.tool_capability("btw_tool_files_read"), "read")
  expect_identical(.tool_capability("some_unknown_tool"), "read")
})

test_that(".resolve_tool_policy parses settings$tools with defaults", {
  p <- .resolve_tool_policy(list(tools = list(
    sets = c("A"), capabilities = list(write = "ask"),
    overrides = list(Bash = "deny"))))
  expect_identical(p$sets, "A")
  expect_identical(p$capabilities$write, "ask")
  expect_identical(p$overrides$Bash, "deny")

  p2 <- .resolve_tool_policy(list())
  expect_setequal(p2$sets, c("A", "B"))
  expect_identical(p2$overrides, list())
})

test_that(".gate_decide precedence: override > capability > check_permission", {
  pol <- list(overrides = list(Write = "deny"), capabilities = list(write = "ask"))
  expect_identical(.gate_decide("Write", list(), pol, "bypass", list(), "write"), "deny")

  pol2 <- list(overrides = list(), capabilities = list(write = "ask"))
  expect_identical(.gate_decide("Write", list(), pol2, "bypass", list(), "write"), "ask")

  pol3 <- list(overrides = list(), capabilities = list())
  # falls back to check_permission; bypass mode -> allow
  expect_identical(.gate_decide("Write", list(), pol3, "bypass", list(), "write"), "allow")
})

test_that(".install_permission_gate registers on the chat without error", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  me <- new.env(); me$mode <- "default"
  expect_invisible(
    .install_permission_gate(chat, list(), me, list(), ask_fn = NULL))
})

test_that(".tool_gate_fn enforces deny and fires PermissionDenied", {
  # NOTE: PreToolUse (run_pre) is no longer fired at the gate -- it moved to the
  # tool-input-hook wrapper layer (.wrap_tool_pre_hook) so a hook can rewrite
  # args, which the rejectable gate callback cannot do. The gate still enforces
  # permission policy and fires PermissionDenied.
  reg <- HookRegistry$new()
  ev  <- new.env(); ev$log <- character()
  reg$register(HookEvent$PERMISSION_DENIED, function(tool_name, tool_input, mode)
    ev$log <- c(ev$log, paste0("DENIED:", tool_name)))

  policy <- list(overrides = list(Write = "deny"), capabilities = list())
  gate <- .tool_gate_fn(policy, "default", list(), ask_fn = NULL, hooks = reg)
  req  <- ellmer::ContentToolRequest(id = "1", name = "Write",
            arguments = list(file_path = "x", content = "y"))

  expect_error(gate(req), class = "ellmer_tool_reject")   # deny enforced
  expect_true(any(grepl("^DENIED:Write", ev$log)))        # PermissionDenied fired
})

test_that(".tool_gate_fn allows read-only tools (no PreToolUse at gate)", {
  reg <- HookRegistry$new(); ev <- new.env(); ev$log <- character()
  reg$register_pre(function(tool_name, tool_input) ev$log <- c(ev$log, tool_name))
  gate <- .tool_gate_fn(list(overrides = list(), capabilities = list()),
                        "default", list(), NULL, reg)
  req <- ellmer::ContentToolRequest(id = "2", name = "Read",
           arguments = list(file_path = "x"))
  expect_invisible(gate(req))
  expect_false("Read" %in% ev$log)   # PreToolUse fires in the wrapper, not the gate
})

test_that(".tool_gate_fn allows write tools in bypass mode", {
  gate <- .tool_gate_fn(list(overrides = list(), capabilities = list()),
                        "bypass", list(), NULL, NULL)
  req <- ellmer::ContentToolRequest(id = "3", name = "Write",
           arguments = list(file_path = "x", content = "y"))
  expect_invisible(gate(req))
})

test_that("capability policy 'write=ask' with no ask_fn denies write tools", {
  policy <- list(overrides = list(), capabilities = list(write = "ask"))
  gate <- .tool_gate_fn(policy, "bypass", list(), ask_fn = NULL, hooks = NULL)
  req <- ellmer::ContentToolRequest(id = "4", name = "Write",
           arguments = list(file_path = "x", content = "y"))
  expect_error(gate(req), class = "ellmer_tool_reject")   # ask + no ask_fn -> deny
})

test_that(".tool_gate_fn takes the async promise branch when ask_fn is async (Shiny)", {
  policy <- list(overrides = list(), capabilities = list(write = "ask"))
  gate <- .tool_gate_fn(policy, "bypass", list(),
                        ask_fn = function(n, i) promises::promise_resolve(TRUE),
                        hooks = NULL)
  req <- ellmer::ContentToolRequest(id = "5", name = "Write",
           arguments = list(file_path = "x", content = "y"))
  res <- gate(req)
  expect_true(promises::is.promise(res))   # async decision deferred to a promise
})

test_that(".install_permission_gate is idempotent per chat (no stale duplicate gate)", {
  # Reproduces the Shiny bug: client build installs a gate with ask_fn=NULL/console;
  # the Shiny server re-registers with shiny_ask_fn. The gate must be installed ONCE
  # and use the LATEST ask_fn (else the stale first gate denies "ask" tools).
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  me <- new.env(); me$mode <- "default"
  ask_console <- function(n, i) FALSE                          # 1st: deny-ish
  ask_shiny   <- function(n, i) promises::promise_resolve(TRUE) # 2nd: async approve

  scfg <- list(tools = list(capabilities = list(write = "ask")))
  .install_permission_gate(chat, scfg, me, list(), ask_fn = ask_console)
  .install_permission_gate(chat, scfg, me, list(), ask_fn = ask_shiny)

  key <- rlang::obj_address(chat)
  ctx <- .gate_contexts[[key]]
  expect_true(isTRUE(ctx$installed))          # gate registered on the chat
  expect_identical(ctx$ask_fn, ask_shiny)     # latest ask_fn wins -> single live gate
})


# --- register_tool_meta: host tool capability declaration ---

test_that("register_tool_meta lets host tools be classified for the gate", {
  reg <- codeagent:::.tool_meta_user
  on.exit(rm(list = ls(reg), envir = reg), add = TRUE)

  # An unregistered host tool defaults to benign "read" (allowed without gating).
  expect_identical(codeagent:::.tool_capability("MyHostTool"), "read")

  # Declaring it exec makes it sensitive.
  expect_identical(codeagent::register_tool_meta("MyHostTool", "exec"), "MyHostTool")
  expect_identical(codeagent:::.tool_capability("MyHostTool"), "exec")

  # Built-in metadata stays authoritative: a host cannot downgrade Bash.
  codeagent::register_tool_meta("Bash", "read")
  expect_identical(codeagent:::.tool_capability("Bash"), "exec")

  # Validation.
  expect_error(codeagent::register_tool_meta("X", "bogus"))
  expect_error(codeagent::register_tool_meta("", "read"))
})

test_that("a declared-exec host tool is governed by policy (not auto-allowed)", {
  reg <- codeagent:::.tool_meta_user
  on.exit(rm(list = ls(reg), envir = reg), add = TRUE)

  codeagent::register_tool_meta("MyHostTool", "exec")
  cap <- codeagent:::.tool_capability("MyHostTool")           # "exec" -> not the read fast-path
  pol <- codeagent:::.resolve_tool_policy(
    list(tools = list(capabilities = list(exec = "deny"))))
  expect_identical(
    codeagent:::.gate_decide("MyHostTool", list(), pol, "default", list(), cap),
    "deny")
})


# --- Gap #1: gate passes tool-call id to ask_fns that accept it ---

test_that("gate passes tool-call id only to ask_fns that accept it", {
  reg <- codeagent:::.tool_meta_user
  on.exit(rm(list = ls(reg), envir = reg), add = TRUE)
  register_tool_meta("WTool", "exec")

  policy   <- codeagent:::.resolve_tool_policy(
    list(tools = list(capabilities = list(exec = "ask"))))
  mode_env <- new.env(); mode_env$mode <- "default"
  mk_req   <- function() ellmer::ContentToolRequest(
    id = "call_42", name = "WTool", arguments = list())

  # (a) ask_fn declaring id= receives the tool-call id
  seen <- new.env(); seen$id <- NA_character_
  g1 <- codeagent:::.tool_gate_fn(codeagent:::.make_gate_ctx(
    policy, mode_env, list(), function(name, input, id = NULL) { seen$id <- id; TRUE }))
  g1(mk_req())
  expect_identical(seen$id, "call_42")

  # (b) legacy (name, input) ask_fn is called unchanged, no error
  hit <- new.env(); hit$called <- FALSE
  g2 <- codeagent:::.tool_gate_fn(codeagent:::.make_gate_ctx(
    policy, mode_env, list(), function(tool_name, tool_input) { hit$called <- TRUE; TRUE }))
  expect_silent(g2(mk_req()))
  expect_true(hit$called)
})

# --- Gap #2: install_permission_gate() governs host tools ---

test_that("install_permission_gate installs the gate + applies tool_meta", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  reg <- codeagent:::.tool_meta_user
  on.exit(rm(list = ls(reg), envir = reg), add = TRUE)

  install_permission_gate(
    chat, permission_mode = "default",
    tools     = list(capabilities = list(write = "deny")),
    tool_meta = list(HostWrite = "write"))

  # tool_meta convenience recorded the capability
  expect_identical(codeagent:::.tool_capability("HostWrite"), "write")
  # gate is installed on the chat
  ctx <- codeagent:::.gate_contexts[[rlang::obj_address(chat)]]
  expect_true(isTRUE(ctx$installed))
  # policy carried through: a write host tool is denied
  expect_identical(
    codeagent:::.gate_decide("HostWrite", list(), ctx$policy, "default", list(), "write"),
    "deny")
  # unnamed tool_meta is rejected
  expect_error(install_permission_gate(chat, tool_meta = list("write")))
})


# --- Data Shield ingress: universal pre-tool interception ---

test_that("Data Shield ingress block rejects even a read/unknown tool", {
  shield <- DataShield$new(strategies=list(
    shield_ingress(patterns=c(exfil="SEND_SECRET\\("),
                   include_defaults=FALSE, on_fail="block")))
  policy <- codeagent:::.resolve_tool_policy(list())
  mode_env <- new.env(); mode_env$mode <- "default"
  ctx <- codeagent:::.make_gate_ctx(policy, mode_env)
  ctx$data_shield <- shield
  gate <- codeagent:::.tool_gate_fn(ctx)
  req <- ellmer::ContentToolRequest(
    id="call-shield-block", name="UnknownReadTool",
    arguments=list(payload="SEND_SECRET(x)"))
  expect_error(gate(req), "Data Shield ingress matched")
  audit <- shield$audit()
  expect_identical(audit$tool_call_id[[1L]], "call-shield-block")
  expect_identical(audit$tool_name[[1L]], "UnknownReadTool")
  expect_false(grepl("SEND_SECRET", paste(audit, collapse="")))
})

test_that("Data Shield ingress ask bypasses read fast-path and uses existing approval", {
  shield <- DataShield$new(strategies=list(
    shield_ingress(patterns=c(review="CHECK_DATA\\("),
                   include_defaults=FALSE, on_fail="ask")))
  policy <- codeagent:::.resolve_tool_policy(list())
  mode_env <- new.env(); mode_env$mode <- "default"
  seen <- new.env(); seen$called <- FALSE; seen$id <- NULL
  ask_fn <- function(name, input, id=NULL) {
    seen$called <- TRUE; seen$id <- id; TRUE
  }
  ctx <- codeagent:::.make_gate_ctx(policy, mode_env, ask_fn=ask_fn)
  ctx$data_shield <- shield
  gate <- codeagent:::.tool_gate_fn(ctx)
  req <- ellmer::ContentToolRequest(
    id="call-shield-ask", name="Read",
    arguments=list(command="CHECK_DATA(x)"))
  expect_silent(gate(req))
  expect_true(seen$called)
  expect_identical(seen$id, "call-shield-ask")
  expect_identical(shield$audit()$action[[1L]], "ask")
})

test_that("no Data Shield preserves ordinary read fast-path", {
  policy <- codeagent:::.resolve_tool_policy(list())
  mode_env <- new.env(); mode_env$mode <- "default"
  called <- FALSE
  ctx <- codeagent:::.make_gate_ctx(
    policy, mode_env, ask_fn=function(...) { called <<- TRUE; FALSE })
  gate <- codeagent:::.tool_gate_fn(ctx)
  req <- ellmer::ContentToolRequest(
    id="call-no-shield", name="Read", arguments=list(file_path="data.csv"))
  expect_silent(gate(req))
  expect_false(called)
})


test_that("Shield tool bypass never bypasses the independent permission gate", {
  shield <- DataShield$new(strategies=list(
    shield_tool_policy(rules=list(Write=list(ingress="bypass",egress="bypass")))))
  policy <- codeagent:::.resolve_tool_policy(
    list(tools=list(capabilities=list(write="deny"))))
  mode_env <- new.env(); mode_env$mode <- "default"
  ctx <- codeagent:::.make_gate_ctx(policy,mode_env)
  ctx$data_shield <- shield
  gate <- codeagent:::.tool_gate_fn(ctx)
  req <- ellmer::ContentToolRequest(
    id="call-trusted-write",name="Write",
    arguments=list(file_path="safe.txt",content="hello"))
  expect_error(gate(req),"Permission denied")
  expect_true(any(shield$audit()$strategy=="tool_policy" &
                  shield$audit()$action=="bypass"))
})


test_that("portable sandbox blocks project-external Read before read fast-path", {
  root <- withr::local_tempdir(); outside <- tempfile(); writeLines("x",outside)
  on.exit(unlink(outside),add=TRUE)
  shield <- DataShield$new(strategies=list(shield_sandbox(project_root=root,backend="policy")))
  policy <- codeagent:::.resolve_tool_policy(list())
  mode_env <- new.env(); mode_env$mode <- "default"
  ctx <- codeagent:::.make_gate_ctx(policy,mode_env); ctx$data_shield <- shield
  gate <- codeagent:::.tool_gate_fn(ctx)
  req <- ellmer::ContentToolRequest(
    id="sandbox-read",name="Read",arguments=list(file_path=outside))
  expect_error(gate(req),"outside sandbox roots")
})


test_that("central gate awaits promise-valued Data Shield reviewer decision", {
  shield <- DataShield$new(strategies=list(
    shield_reviewer(model="fast",scope="exec",on_risk="ask")))
  testthat::local_mocked_bindings(
    .data_shield_invoke_reviewer=function(...)
      promises::promise_resolve(list(error=FALSE,risk="serialization",confidence=.9,reason="risk")),
    .package="codeagent")
  policy <- codeagent:::.resolve_tool_policy(list())
  mode_env <- new.env(); mode_env$mode <- "default"
  asked <- FALSE
  ctx <- codeagent:::.make_gate_ctx(policy,mode_env,
    ask_fn=function(name,input,id=NULL){asked <<- TRUE; TRUE})
  ctx$data_shield <- shield
  gate <- codeagent:::.tool_gate_fn(ctx)
  req <- ellmer::ContentToolRequest(id="review-promise",name="RunR",arguments=list(code="x"))
  result <- gate(req)
  expect_true(inherits(result,"promise"))
  done <- FALSE; promises::then(result,function(x)done<<-TRUE)
  # run_now pumps the shared global later loop; tolerate stray bad callbacks
  # left enqueued by earlier async tests so this poll only drives our promise.
  for(i in 1:100){tryCatch(later::run_now(.01),error=function(e)NULL);if(done)break}
  expect_true(done); expect_true(asked)
})
