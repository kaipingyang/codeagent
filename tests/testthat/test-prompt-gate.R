# tests/testthat/test-prompt-gate.R
# Data Shield prompt gate (edge 1): scan_prompt + .prompt_gate_scan.

make_shield <- function() {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L), shield_regex()))
  df <- data.frame(subject_id = sprintf("SUBJECT%03d", 1:50),
                   stringsAsFactors = FALSE)
  sh$register_data(df, name = "d")
  sh
}

test_that("scan_prompt redacts a protected value but keeps the rest (edge 1)", {
  sh <- make_shield()
  r <- sh$scan_prompt("tell me about SUBJECT001 please", on_fail = "redact")
  expect_identical(r$action, "redact")
  expect_false(grepl("SUBJECT001", r$text, fixed = TRUE))   # value gone
  expect_true(grepl("tell me about", r$text, fixed = TRUE)) # rest preserved
  expect_true(grepl("please", r$text, fixed = TRUE))
  expect_true(grepl("[REDACTED]", r$text, fixed = TRUE))
})

test_that("scan_prompt redacts PII (regex) but keeps the rest", {
  sh <- make_shield()
  r <- sh$scan_prompt("email me at foo@bar.com thanks", on_fail = "redact")
  expect_identical(r$action, "redact")
  expect_false(grepl("foo@bar.com", r$text, fixed = TRUE))
  expect_true(grepl("email me at", r$text, fixed = TRUE))
  expect_true(grepl("thanks", r$text, fixed = TRUE))
})

test_that("scan_prompt block rejects the whole turn", {
  sh <- make_shield()
  r <- sh$scan_prompt("subject SUBJECT002", on_fail = "block")
  expect_identical(r$action, "block")
  expect_match(r$text, "blocked")
})

test_that("scan_prompt passes clean text unchanged", {
  sh <- make_shield()
  r <- sh$scan_prompt("what is the weather today", on_fail = "redact")
  expect_identical(r$action, "pass")
  expect_identical(r$text, "what is the weather today")
})

test_that("scan_prompt fires on_progress for each detector stage", {
  sh <- make_shield()
  stages <- character(0)
  sh$scan_prompt("SUBJECT003 and foo@x.com", on_fail = "redact",
                 on_progress = function(p) stages <<- c(stages, p$stage))
  expect_true("regex" %in% stages)
  expect_true("value_match" %in% stages)
})

test_that("scan_prompt ignores empty / non-scalar input", {
  sh <- make_shield()
  expect_identical(sh$scan_prompt("", on_fail = "redact")$action, "pass")
})

test_that(".prompt_gate_scan is a no-op without an active shield", {
  res <- codeagent:::.prompt_gate_scan("hello SUBJECT001", settings = list(), chat = NULL)
  expect_identical(res$action, "pass")
  expect_identical(res$text, "hello SUBJECT001")   # untouched, no shield
})

test_that(".prompt_gate_scan redacts via the settings-resolved shield", {
  sh <- make_shield()
  res <- codeagent:::.prompt_gate_scan(
    "about SUBJECT004 ok", settings = list(data_shield_engine = sh))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT004", res$text, fixed = TRUE))
  expect_true(grepl("about", res$text, fixed = TRUE))
})

test_that(".prompt_gate_scan honors block via settings on_fail", {
  sh <- make_shield()
  res <- codeagent:::.prompt_gate_scan(
    "SUBJECT005", settings = list(data_shield_engine = sh,
                                  data_shield_prompt_on_fail = "block"))
  expect_identical(res$action, "block")
})

test_that(".prompt_gate_scan degrades ask to redact (fail-safe, never sends raw)", {
  sh <- make_shield()
  res <- codeagent:::.prompt_gate_scan(
    "SUBJECT006 here", settings = list(data_shield_engine = sh,
                                       data_shield_prompt_on_fail = "ask"))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT006", res$text, fixed = TRUE))
})
