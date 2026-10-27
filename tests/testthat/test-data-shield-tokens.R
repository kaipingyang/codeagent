# Value matching must see compound identifiers whole (CDISC USUBJID etc.).

test_that("compound identifiers are candidates whole and in parts", {
  toks <- .data_shield_tokens("Subject BGB-001-0007, site SITE_12/0003. pi=3.14")
  expect_true(all(c("BGB-001-0007", "BGB", "001", "0007", "SITE_12/0003", "SITE", "0003", "3.14") %in% toks))
  expect_false(any(grepl("^[._/-]|[._/-]$", toks)))
})

test_that("a hyphenated USUBJID is withheld on egress and redacted in replies", {
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 50L)))
  shield$register_data(data.frame(USUBJID = sprintf("BGB-001-%04d", 1:40)),
                       name = "adsl", sensitivity = c(USUBJID = "identifier"))
  vm <- .data_shield_value_scan("subject BGB-001-0007 had nausea", get("private", environment(shield$coverage))$index)
  expect_true(vm$hit)
  out <- shield$scan_response("Subject BGB-001-0007 had nausea.", on_fail = "redact")
  expect_false(grepl("BGB-001-0007", out$text, fixed = TRUE))
  expect_match(out$text, "had nausea", fixed = TRUE)
  expect_false(.data_shield_value_scan("ARM A, 40 subjects", get("private", environment(shield$coverage))$index)$hit)
})

test_that("an identifier joined to other words is still found and redacted whole", {
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 50L)))
  shield$register_data(data.frame(USUBJID = sprintf("BGB-001-%04d", 1:40),
                                  SITE = sprintf("SITE_%02d", 1:40)),
                       name = "adsl", sensitivity = c(USUBJID = "identifier", SITE = "identifier"))
  ix <- get("private", environment(shield$coverage))$index
  for (txt in c("subject/BGB-001-0007", "BGB-001-0007_AE.csv", "BGB-001-0007-visit2",
                "(BGB-001-0007)", "SITE_12/0003"))
    expect_true(.data_shield_value_scan(txt, ix)$hit, info = txt)
  out <- shield$scan_response("Saved BGB-001-0007_AE.csv for review.", on_fail = "redact")
  expect_false(grepl("0007", out$text, fixed = TRUE))
  expect_match(out$text, "_AE.csv", fixed = TRUE)
})

test_that("token runs are bounded on long compound tokens", {
  long <- paste(sprintf("p%03d", 1:200), collapse = "-")
  toks <- .data_shield_tokens(long)
  expect_lt(length(toks), 200 * .DATA_SHIELD_MAX_SEGMENTS + 2)
  expect_true(long %in% toks)
})
