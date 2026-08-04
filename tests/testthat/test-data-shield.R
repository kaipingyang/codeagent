# Data Shield P0 --- egress row-cap (edge 2) + tool-wrap installer.

test_that("row-cap detects bulk tabular vs harmless output", {
  cap <- function(x) codeagent:::.data_shield_row_cap(x, max_rows = 0L)$capped
  expect_true(cap(paste(utils::capture.output(print(mtcars)), collapse = "\n")))
  expect_false(cap("[1] 320"))                                   # scalar
  expect_false(cap("Done. Converged in 5 iterations."))          # message
  expect_false(cap(paste(utils::capture.output(                  # model summary
    print(summary(lm(mpg ~ wt, mtcars)))), collapse = "\n")))
})

test_that(".data_shield_filter_result caps bulk results, passes harmless", {
  df_txt <- paste(utils::capture.output(print(mtcars)), collapse = "\n")

  # ellmer ContentToolResult with a bulk value -> value truncated
  ctr <- codeagent::tool_result(df_txt, kind = "text")
  out <- codeagent:::.data_shield_filter_result(ctr, max_rows = 0L)
  expect_match(as.character(out@value), "data_shield")

  # ContentToolResult with a harmless scalar value -> unchanged
  ctr2 <- codeagent::tool_result("320", kind = "text")
  expect_identical(as.character(
    codeagent:::.data_shield_filter_result(ctr2)@value), "320")

  # raw data.frame return -> capped to a shape string
  cap_df <- codeagent:::.data_shield_filter_result(mtcars, max_rows = 0L)
  expect_true(is.character(cap_df) && grepl("data_shield", cap_df))

  # harmless scalar string -> unchanged
  expect_identical(codeagent:::.data_shield_filter_result("hello"), "hello")
})

test_that("install_data_shield wraps tools so bulk results are capped, harmless pass", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  reg <- codeagent:::.data_shield_installed
  on.exit(rm(list = ls(reg), envir = reg), add = TRUE)

  dump <- ellmer::tool(function() mtcars, name = "Dump",
                       description = "returns a bulk data.frame", arguments = list())
  scal <- ellmer::tool(function() "ok", name = "Scal",
                       description = "returns a scalar", arguments = list())
  chat$register_tool(dump)
  chat$register_tool(scal)

  install_data_shield(chat, max_rows = 0L)
  tools <- chat$get_tools()
  by_name <- function(nm) {
    for (t in tools) if (identical(tryCatch(S7::prop(t, "name"),
                                            error = function(e) ""), nm)) return(t)
    NULL
  }
  dumped <- by_name("Dump")()
  scaled <- by_name("Scal")()
  expect_true(is.character(dumped) && grepl("data_shield", dumped))  # bulk capped
  expect_identical(scaled, "ok")                                     # scalar passed
})

test_that("codeagent_client exposes data_shield (off by default) + install_data_shield exported", {
  expect_true("data_shield" %in% names(formals(codeagent_client)))
  expect_true("install_data_shield" %in% getNamespaceExports("codeagent"))
})
