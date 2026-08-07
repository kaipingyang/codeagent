# tests/testthat/test-output-gate.R
# Data Shield output gate (edge 3): scan_response + .output_gate_scan.
# The model's finalized reply is scanned before it reaches the user, so a
# protected value the model reproduced (e.g. inferred from tool output) is
# caught even when the user's own input was clean.

make_shield <- function() {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L), shield_regex()))
  df <- data.frame(subject_id = sprintf("SUBJECT%03d", 1:50),
                   stringsAsFactors = FALSE)
  sh$register_data(df, name = "d")
  sh
}

test_that("scan_response redacts a protected value but keeps the rest (edge 3)", {
  sh <- make_shield()
  r <- sh$scan_response("the model said SUBJECT001 here", on_fail = "redact")
  expect_identical(r$action, "redact")
  expect_false(grepl("SUBJECT001", r$text, fixed = TRUE))
  expect_true(grepl("the model said", r$text, fixed = TRUE))
  expect_true(grepl("here", r$text, fixed = TRUE))
})

test_that("scan_response audits under edge = 'response' (not 'prompt')", {
  sh <- make_shield()
  sh$scan_response("reply SUBJECT002")
  a <- sh$audit(limit = 10)
  expect_true("response" %in% a$edge)
  expect_false("prompt" %in% a$edge)   # only a response scan ran
})

test_that("scan_response block rejects the whole reply", {
  sh <- make_shield()
  r <- sh$scan_response("SUBJECT003", on_fail = "block")
  expect_identical(r$action, "block")
})

test_that(".output_gate_scan is a no-op without an active shield", {
  res <- codeagent:::.output_gate_scan("reply SUBJECT001", settings = list(), chat = NULL)
  expect_identical(res$action, "pass")
  expect_identical(res$text, "reply SUBJECT001")
})

test_that(".output_gate_scan redacts via the settings-resolved shield", {
  sh <- make_shield()
  res <- codeagent:::.output_gate_scan(
    "model leaked SUBJECT004 oops", settings = list(data_shield_engine = sh))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT004", res$text, fixed = TRUE))
  expect_true(grepl("model leaked", res$text, fixed = TRUE))
  expect_gte(res$matches, 1L)
})

test_that(".output_gate_scan honors response_on_fail = block", {
  sh <- make_shield()
  res <- codeagent:::.output_gate_scan(
    "SUBJECT005", settings = list(data_shield_engine = sh,
                                  data_shield_response_on_fail = "block"))
  expect_identical(res$action, "block")
})

test_that(".output_gate_scan degrades ask to redact (fail-safe)", {
  sh <- make_shield()
  res <- codeagent:::.output_gate_scan(
    "SUBJECT006 here", settings = list(data_shield_engine = sh,
                                       data_shield_response_on_fail = "ask"))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT006", res$text, fixed = TRUE))
})

test_that(".output_gate_scan passes a clean reply unchanged", {
  sh <- make_shield()
  res <- codeagent:::.output_gate_scan(
    "the analysis converged fine", settings = list(data_shield_engine = sh))
  expect_identical(res$action, "pass")
  expect_identical(res$text, "the analysis converged fine")
})

test_that(".output_gate_scan output_scanners switch: value_match only skips PII", {
  sh <- make_shield()
  res <- codeagent:::.output_gate_scan(
    "SUBJECT007 and foo@bar.com",
    settings = list(data_shield_engine = sh,
                    data_shield_output_scanners = c("value_match")))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT007", res$text, fixed = TRUE))   # registered value gone
  expect_true(grepl("foo@bar.com", res$text, fixed = TRUE))   # PII kept (regex off)
})

test_that(".output_gate_scan output_scanners switch: regex only skips value_match", {
  sh <- make_shield()
  res <- codeagent:::.output_gate_scan(
    "SUBJECT008 and foo@bar.com",
    settings = list(data_shield_engine = sh,
                    data_shield_output_scanners = c("regex")))
  expect_identical(res$action, "redact")
  expect_true(grepl("SUBJECT008", res$text, fixed = TRUE))    # value_match off
  expect_false(grepl("foo@bar.com", res$text, fixed = TRUE))  # PII redacted
})
