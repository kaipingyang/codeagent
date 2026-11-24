# A withheld / denied notice says why -- the source columns and their class --
# and never a protected value (UAT LiveTFLAI 2026-11-23: an opaque "contains 8
# protected data value(s)" left the model unable to tell the user what it
# could not see, and the false positive was found only by reproducing it).
mk <- function(explain = TRUE) {
  df <- data.frame(USUBJID = sprintf("BGB-X-%04d", 1:40), SUBJID = sprintf("S%04d", 1:40),
                   COUNTRY = rep(c("CHN", "NZL", "KOR", "USA", "FRA", "BRA", "JPN", "ITA"), 5))
  sh <- DataShield$new(strategies = list(shield_egress(explain = explain)))
  sh$register_data(df, name = "ADSL", sensitivity = list(USUBJID = "identifier", SUBJID = "identifier"),
                   column_access = list(USUBJID = list(prompt = "schema", egress = "none")))
  sh
}

test_that("the notice names the source column and class, never the value", {
  sh <- mk()
  out <- sh$scan_egress("Countries: CHN, USA", list(tool_name = "t"))
  expect_match(out, "Source: ADSL.COUNTRY (quasi).", fixed = TRUE)
  expect_false(grepl("CHN|USA", out))
  out <- sh$scan_egress("subject S0007 had an AE", list(tool_name = "t"))
  expect_match(out, "ADSL.SUBJID (identifier)", fixed = TRUE)
  expect_false(grepl("S0007", out, fixed = TRUE))
  out <- sh$scan_egress("row of BGB-X-0007", list(tool_name = "t"))
  expect_match(out, "denied.*ADSL.USUBJID \\(egress=none\\)")
  expect_false(grepl("0007", out, fixed = TRUE))
  out <- sh$scan_egress("id BGBX0007 written otherwise", list(tool_name = "t"))
  expect_match(out, "an identifier written in another format", fixed = TRUE)
  expect_false(grepl("0007", out, fixed = TRUE))
  # the audit log says the same (local; for collecting false positives)
  reasons <- vapply(sh$audit()$reason, as.character, "")
  expect_true(any(grepl("ADSL.COUNTRY (quasi)", reasons, fixed = TRUE)))
  expect_false(any(grepl("CHN|S0007|BGB-X-0007", reasons)))
})

test_that("explain = FALSE keeps the bare notice", {
  sh <- mk(explain = FALSE)
  expect_identical(sh$scan_egress("Countries: CHN, USA", list(tool_name = "t")),
                   "[data_shield] output withheld: contains 2 protected data value(s).")
  expect_identical(sh$scan_egress("row of BGB-X-0007", list(tool_name = "t")),
                   "[data_shield] tool output denied: contains a value from a column marked egress=none.")
})

test_that("several sources are listed once each, at most five", {
  expect_identical(.data_shield_reason(character()), "")
  expect_identical(.data_shield_reason(c("A.X (quasi)", "A.X (quasi)", "B.Y (identifier)")),
                   " Source: A.X (quasi), B.Y (identifier).")
  expect_match(.data_shield_reason(paste0("D.C", 1:7, " (quasi)")), "and 2 more.", fixed = TRUE)
})

test_that("a value of two datasets keeps one label; matching is unchanged", {
  sh <- mk()
  sh$register_data(data.frame(USUBJID = sprintf("BGB-X-%04d", 1:40),
                              COUNTRY = rep(c("CHN", "NZL", "KOR", "USA", "FRA", "BRA", "JPN", "ITA"), 5)),
                   name = "ADAE", sensitivity = list(USUBJID = "identifier"))
  out <- sh$scan_egress("CHN", list(tool_name = "t"))
  expect_match(out, "withheld")
  expect_match(out, "\\.COUNTRY \\(quasi\\)")
})
