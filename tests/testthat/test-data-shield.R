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


test_that("value_match indexes high-entropy values, ignores low-card/small-int (no FP)", {
  set.seed(1)
  df <- data.frame(
    name = paste0("Patient", 1:50),                 # high-card, single-token
    arm  = factor(rep(c("Placebo", "DrugA"), 25)),  # low-card (2) -> skipped
    age  = 20:69,                                    # 2-digit ints -> skipped
    wt   = round(runif(50, 40, 90), 3),              # high-card precise floats
    stringsAsFactors = FALSE)
  idx  <- codeagent:::.data_shield_build_value_index(df,
            cols = c("name", "arm", "age", "wt"))
  scan <- codeagent:::.data_shield_value_scan

  expect_true (scan("The event happened to Patient7 last week.", idx)$hit)  # name leak
  expect_false(scan("The analysis found a significant effect.", idx)$hit)   # no leak
  expect_false(scan("Randomised to the Placebo arm.", idx)$hit)             # low-card cat -> no FP
  expect_false(scan("The patient was 45 years old.", idx)$hit)              # small int -> no FP
  expect_true (scan(paste("weight was", as.character(df$wt[1])), idx)$hit)  # precise float leak
})


test_that("register_protected_data + shield withholds targeted value leaks (row-cap misses)", {
  idx <- codeagent:::.data_shield_index
  reg <- codeagent:::.data_shield_installed
  on.exit({ rm(list = ls(idx), envir = idx); rm(list = ls(reg), envir = reg) }, add = TRUE)

  df <- data.frame(name = paste0("Subject", 1:50), stringsAsFactors = FALSE)
  expect_gt(register_protected_data(df), 0)

  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  # leaks ONE protected value as a short string -> not bulk, row-cap wouldn't catch it
  leak <- ellmer::tool(function() "The result is Subject7.", name = "Leak",
                       description = "d", arguments = list())
  safe <- ellmer::tool(function() "The analysis converged.", name = "Safe",
                       description = "d", arguments = list())
  chat$register_tool(leak); chat$register_tool(safe)
  install_data_shield(chat, max_rows = 0L)

  by_name <- function(nm) {
    for (t in chat$get_tools())
      if (identical(tryCatch(S7::prop(t, "name"), error = function(e) ""), nm)) return(t)
    NULL
  }
  expect_match(by_name("Leak")(), "withheld")                       # protected value blocked
  expect_identical(by_name("Safe")(), "The analysis converged.")    # harmless passes
})
