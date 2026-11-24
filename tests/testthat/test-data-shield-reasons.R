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

# A value present in several datasets: the notice pairs each dataset with a
# column it really has -- the dataset the tool was asked about when it is one
# of them, else every dataset that has the value (UAT LiveTFLAI 2026-11-24:
# an ADSL query was reported as ADAE.SUBJID, the first dataset registered).
mk2 <- function() {
  ids <- sprintf("S%04d", 1:40)
  sh <- DataShield$new(strategies = list(shield_egress()))
  sh$register_data(data.frame(SUBJID = ids, AETERM = "x"), name = "ADAE", sensitivity = list(SUBJID = "identifier"))
  sh$register_data(data.frame(SUBJID = ids), name = "ADSL", sensitivity = list(SUBJID = "identifier"))
  sh$register_data(data.frame(PATID = ids), name = "ADCM", sensitivity = list(PATID = "identifier"))
  sh
}

test_that("the dataset the tool was asked about is the one named", {
  sh <- mk2()
  out <- sh$scan_egress("S0007", list(tool_name = "explore_adam", args = list(dataset = "ADSL", operation = "unique")))
  expect_match(out, "Source: ADSL.SUBJID (identifier).", fixed = TRUE)
  expect_false(grepl("ADAE|ADCM", out))
  out <- sh$scan_egress("S0007", list(tool_name = "t", args = list(code = "count(adcm, PATID)")))
  expect_match(out, "Source: ADCM.PATID (identifier).", fixed = TRUE)
})

test_that("without a dataset in the arguments every dataset with the value is listed, per column", {
  sh <- mk2()
  out <- sh$scan_egress("S0007", list(tool_name = "t"))
  expect_match(out, "SUBJID (identifier) in ADAE, ADSL", fixed = TRUE)
  expect_match(out, "ADCM.PATID (identifier)", fixed = TRUE)
  expect_false(grepl("ADSL.PATID|ADCM.SUBJID|ADAE.PATID", out))       # never a wrong pair
  # a named dataset that does not have the value does not take it over
  out <- sh$scan_egress("S0007", list(tool_name = "t", args = list(dataset = "ADTTE")))
  expect_match(out, "SUBJID (identifier) in ADAE, ADSL", fixed = TRUE)
  expect_false(grepl("ADTTE", out))
})

test_that("many datasets are summarised; word boundaries decide a named dataset", {
  labs <- list(paste("D", LETTERS[1:6], sep = "")) |> lapply(function(d) .data_shield_label(d, "SUBJID", "identifier"))
  expect_identical(.data_shield_sources(labs), "SUBJID (identifier) in DA, DB, DC and 3 more datasets")
  expect_identical(.data_shield_named_datasets(list(x = "ADSLX and adsl"), c("ADSL", "ADSLX", "ADAE")), c("ADSL", "ADSLX"))
  expect_identical(.data_shield_named_datasets(list(x = "ADSLX"), c("ADSL", "ADAE")), character(0))
  expect_identical(.data_shield_named_datasets(list(), c("ADSL")), character(0))
})

test_that("egress=none values pair dataset and column too", {
  ids <- sprintf("BGB-X-%04d", 1:40)
  sh <- DataShield$new(strategies = list(shield_egress()))
  for (d in c("ADAE", "ADSL"))
    sh$register_data(data.frame(USUBJID = ids), name = d, sensitivity = list(USUBJID = "identifier"),
                     column_access = list(USUBJID = list(prompt = "schema", egress = "none")))
  expect_match(sh$scan_egress("BGB-X-0003", list(tool_name = "t", args = list(dataset = "ADSL"))),
               "Source: ADSL.USUBJID (egress=none).", fixed = TRUE)
  expect_match(sh$scan_egress("BGB-X-0003", list(tool_name = "t")),
               "USUBJID (egress=none) in ADAE, ADSL", fixed = TRUE)
})
