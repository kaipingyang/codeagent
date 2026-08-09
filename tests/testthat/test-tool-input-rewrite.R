# tests/testthat/test-tool-input-rewrite.R
# PreToolUse updatedInput (gap #2, aligns with Claude Agent SDK): a hook can
# rewrite or deny a tool's arguments before execution, done in the tool-input
# wrapper layer (.wrap_tool_pre_hook) -- zero ellmer patch. Data Shield's
# ingress rewrite (scan_tool_args + .data_shield_wrap_tool) redacts protected
# values inside tool arguments.

test_that(".wrap_tool_pre_hook rewrites tool args via updated_input", {
  hooks <- HookRegistry$new()
  hooks$register_pre(function(tool_name, tool_input) {
    if (identical(tool_name, "echo")) {
      ni <- tool_input; ni$x <- paste0("HOOKED:", tool_input$x)
      return(list(action = "updated_input", input = ni))
    }
    NULL
  })
  seen <- new.env()
  t <- ellmer::tool(function(x) { seen$got <- x; x }, name = "echo",
                    description = "e", arguments = list(x = ellmer::type_string("i")))
  tw <- codeagent:::.wrap_tool_pre_hook(t, hooks)
  do.call(S7::S7_data(tw), list(x = "original"))
  expect_identical(seen$got, "HOOKED:original")
})

test_that(".wrap_tool_pre_hook preserves the tool schema", {
  hooks <- HookRegistry$new()
  t <- ellmer::tool(function(city, unit = "C") paste0(city, unit), name = "w",
                    description = "w",
                    arguments = list(city = ellmer::type_string("c"),
                                     unit = ellmer::type_string("u", required = FALSE)))
  tw <- codeagent:::.wrap_tool_pre_hook(t, hooks)
  expect_setequal(names(tw@arguments@properties), c("city", "unit"))
})

test_that(".wrap_tool_pre_hook denies via tool_reject", {
  hooks <- HookRegistry$new()
  hooks$register_pre(function(tn, ti) list(action = "deny", message = "nope"))
  t <- ellmer::tool(function(x) x, name = "echo", description = "e",
                    arguments = list(x = ellmer::type_string("i")))
  tw <- codeagent:::.wrap_tool_pre_hook(t, hooks)
  expect_error(do.call(S7::S7_data(tw), list(x = "y")),
               class = "ellmer_tool_reject")
})

test_that(".wrap_tool_pre_hook is a no-op without hooks", {
  t <- ellmer::tool(function(x) x, name = "echo", description = "e",
                    arguments = list(x = ellmer::type_string("i")))
  expect_identical(codeagent:::.wrap_tool_pre_hook(t, NULL), t)
})

test_that(".wrap_tool_pre_hook passes args through unchanged when hook returns NULL", {
  hooks <- HookRegistry$new()
  hooks$register_pre(function(tn, ti) NULL)
  seen <- new.env()
  t <- ellmer::tool(function(x) { seen$got <- x; x }, name = "echo",
                    description = "e", arguments = list(x = ellmer::type_string("i")))
  tw <- codeagent:::.wrap_tool_pre_hook(t, hooks)
  do.call(S7::S7_data(tw), list(x = "clean"))
  expect_identical(seen$got, "clean")
})

# --- Data Shield ingress rewrite ------------------------------------------

make_shield <- function() {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L), shield_regex()))
  sh$register_data(data.frame(subject_id = sprintf("SUBJECT%03d", 1:50)), name = "d")
  sh
}

test_that("scan_tool_args redacts a protected value in a string argument", {
  sh <- make_shield()
  r <- sh$scan_tool_args(list(query = "find SUBJECT001 in db", limit = "10"))
  expect_identical(r$action, "redact")
  expect_false(grepl("SUBJECT001", r$args$query, fixed = TRUE))
  expect_true(grepl("find", r$args$query, fixed = TRUE))
  expect_identical(r$args$limit, "10")   # non-matching arg untouched
})

test_that("scan_tool_args passes clean args unchanged", {
  sh <- make_shield()
  r <- sh$scan_tool_args(list(query = "normal search"))
  expect_identical(r$action, "pass")
  expect_identical(r$args$query, "normal search")
})

test_that("scan_tool_args leaves non-string args untouched", {
  sh <- make_shield()
  r <- sh$scan_tool_args(list(n = 5L, flag = TRUE))
  expect_identical(r$action, "pass")
  expect_identical(r$args$n, 5L)
})

test_that(".data_shield_wrap_tool redacts protected values in tool args (ingress)", {
  sh <- make_shield()
  seen <- new.env()
  t <- ellmer::tool(function(query) { seen$got <- query; query }, name = "search",
                    description = "s", arguments = list(query = ellmer::type_string("q")))
  tw <- codeagent:::.data_shield_wrap_tool(t, sh)
  do.call(S7::S7_data(tw), list(query = "lookup SUBJECT042 now"))
  expect_false(grepl("SUBJECT042", seen$got, fixed = TRUE))
  expect_true(grepl("[REDACTED]", seen$got, fixed = TRUE))
  expect_true(grepl("lookup", seen$got, fixed = TRUE))
})
