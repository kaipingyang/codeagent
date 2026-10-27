# Identifier variants, identifier shapes, and their false-positive guards.

.ids_shield <- function(id_variants = TRUE) {
  s <- DataShield$new(strategies = list(shield_egress(max_rows = 50L)))
  s$register_data(
    data.frame(USUBJID = sprintf("BGB-001-%04d", 1:40),
               ARM = rep(c("Drug X 10MG Q3W", "Placebo"), 20),
               AGE = 40 + (1:40 %% 30),
               PARAMCD = rep(c("BORRCIN", "PFSDRCIN"), 20),
               stringsAsFactors = FALSE),
    name = "adsl", id_variants = id_variants)
  s
}
.ids_index <- function(s) get("private", environment(s$coverage))$index

test_that("USUBJID / SUBJID are classified as identifiers by name", {
  cls <- .data_shield_classify_columns(data.frame(USUBJID = "a", SUBJID = "b", x = 1))
  expect_identical(unname(cls[c("USUBJID", "SUBJID")]), c("identifier", "identifier"))
})

test_that("format variants of an indexed identifier are caught and redacted whole", {
  s <- .ids_shield(); ix <- .ids_index(s)
  for (txt in c("BGB 001 0007", "BGB0010007", "bgb_001_0007", "BGB-1-7", "BGB.001.0007"))
    expect_true(.data_shield_value_scan(paste("subject", txt, "had nausea"), ix)$hit, info = txt)
  out <- s$scan_response("Subject BGB 001 0007 had nausea.", on_fail = "redact")$text
  expect_identical(out, "Subject [REDACTED] had nausea.")
})

test_that("an unregistered identifier of the same shape is caught", {
  s <- .ids_shield(); ix <- .ids_index(s)
  expect_length(attr(ix, "shapes"), 1L)
  expect_match(attr(ix, "shapes"), "BGB\\-[0-9]{3}\\-[0-9]{4}", fixed = TRUE)
  expect_true(.data_shield_value_scan("subject BGB-007-9999 withdrew", ix)$hit)
  expect_identical(s$scan_response("subject bgb-007-9999 withdrew", on_fail = "redact")$text,
                   "subject [REDACTED] withdrew")
})

test_that("labels, codes, counts and dates are not mistaken for identifiers", {
  s <- .ids_shield(); ix <- .ids_index(s)
  for (txt in c("Drug X 10MG Q3W vs Placebo", "BORRCIN and PFSDRCIN", "AGE 45 (12.5%)",
                "N=40 (100.0%)", "Visit 1 Day 15", "2024-01-15", "BGB-A317 is a compound",
                "Table 14.1.1 n = 120"))
    expect_false(.data_shield_value_scan(txt, ix)$hit, info = txt)
})

test_that("shapes need a dominant form and a literal letter prefix", {
  expect_null(.ds_shape_patterns(sprintf("%03d-%04d", 1:40, 1:40)))        # digits only
  expect_null(.ds_shape_patterns(c(sprintf("A%d", 1:20), sprintf("xx-%d-yy", 1:20),
                                   sprintf("%d.%d", 1:20, 1:20))))            # no dominant shape
  expect_null(.ds_shape_patterns(sprintf("BGB-%04d", 1:5)))                 # too few values
  expect_match(.ds_shape_patterns(sprintf("SUBJ%05d", 1:20)), "SUBJ[0-9]{5}", fixed = TRUE)
})

test_that("id_variants = FALSE keeps exact matching only", {
  s <- .ids_shield(id_variants = FALSE); ix <- .ids_index(s)
  expect_false(.data_shield_value_scan("BGB 001 0007", ix)$hit)
  expect_false(.data_shield_value_scan("BGB-007-9999", ix)$hit)
  expect_true(.data_shield_value_scan("BGB-001-0007", ix)$hit)
})

test_that("a large tool result scans in well under a second per 100 KB", {
  s <- .ids_shield(); ix <- .ids_index(s)
  txt <- as.character(jsonlite::toJSON(data.frame(
    Label = rep(c("n", "Mean (SD)", "Median", "Min, Max"), 2500),
    A = sprintf("%d (%.1f%%)", 1:10000, (1:10000) %% 100), B = "xx")))
  expect_gt(nchar(txt), 4e5)
  elapsed <- system.time(r <- .data_shield_value_scan(txt, ix))[["elapsed"]]
  expect_false(r$hit)
  expect_lt(elapsed, 10)
})

test_that("the default phone rule leaves dates and count (percent) cells alone", {
  rx <- .data_shield_default_regex_patterns()[["phone"]]
  for (txt in c("555-123-4567", "(555) 123-4567", "+86 138 0013 8000", "13800138000", "+44 20 7946 0958"))
    expect_true(grepl(rx, txt, perl = TRUE), info = txt)
  for (txt in c("2024-01-15", "40 (100.0%)", "12 (30.0%)", "BGB-001-0007", "Table 14.3.1.2",
                "100 200 3000", "N 250 248 1000", "+10.25 12.50", "Change +10 25 30"))
    expect_false(grepl(rx, txt, perl = TRUE), info = txt)
})

test_that("purely numeric ids get no variants, so decimals and counts stay clear", {
  s <- DataShield$new(strategies = list(shield_egress(max_rows = 50L)))
  s$register_data(data.frame(SUBJID = sprintf("%03d-%04d", rep(c(1, 54, 101), each = 20), 1:60)),
                  name = "adsl")
  ix <- .ids_index(s)
  for (txt in c("Mean (SD) 54.3 (10.2)", "Hemoglobin mean 1.25 g/dL; ratio 1 2",
                "Table 101.1", "107 / 8 subjects", "Mean (SD) 102.3 (15.2)"))
    expect_false(.data_shield_value_scan(txt, ix)$hit, info = txt)
  expect_true(.data_shield_value_scan("subject 054-0021", ix)$hit)   # exact match still works
})

test_that("quasi columns contribute no variants or shapes", {
  s <- DataShield$new(strategies = list(shield_egress(max_rows = 50L)))
  countries <- c("United States", "United Kingdom", "Black or African American", "South Korea",
                 "New Zealand", "Hong Kong", "Saudi Arabia", "Costa Rica", "Sri Lanka", "El Salvador")
  s$register_data(data.frame(COUNTRY = rep(countries, 4), RACE = rep(countries, 4)), name = "dm")
  ix <- .ids_index(s)
  expect_false(.data_shield_value_scan("Country: United States 12 (30.0%)", ix)$hit)
  expect_false(.data_shield_value_scan("Black or African American 3 (7.5%)", ix)$hit)
})

test_that("close() drops the derived variant keys and shapes", {
  s <- .ids_shield(); ix <- .ids_index(s)
  expect_true(.data_shield_value_scan("BGB 001 0007", ix)$hit)
  s$close()
  expect_length(ls(attr(ix, "variants"), all.names = TRUE), 0)
  expect_length(attr(ix, "shapes"), 0)
  expect_false(.data_shield_value_scan("BGB 001 0007", ix)$hit)
})

test_that("a found id counts once and en dash / no-break space variants are caught", {
  s <- .ids_shield(); ix <- .ids_index(s)
  expect_identical(.data_shield_value_scan("BGB-001-0007", ix)$n, 1L)
  expect_true(.data_shield_value_scan("BGB\u2013001\u20130007", ix)$hit)
  expect_true(.data_shield_value_scan("BGB\u00a0001\u00a00007", ix)$hit)
})

test_that("variants reach the egress text path and the reviewer text", {
  s <- .ids_shield(); ix <- .ids_index(s)
  out <- .data_shield_process_text("The listing shows BGB 001 0007.", max_rows = 50L, index = ix,
                                   detectors = c("row_cap", "value_match"))
  expect_false(grepl("0007", out$text, fixed = TRUE))
  rv <- .data_shield_sanitize_reviewer_text("x <- 'a'; id BGB 001 0007; BGB-007-9999", ix)
  expect_false(grepl("0007|9999", rv))
})

test_that("shape regexes escape metacharacters in the literal prefix", {
  p <- .ds_shape_patterns(sprintf("A.B(%03d)+[%04d]", 1:20, 1:20))
  expect_length(p, 1L)
  expect_true(grepl(p, "id A.B(123)+[4567] here", perl = TRUE))
  expect_false(grepl(p, "id AxB(123)+[4567] here", perl = TRUE))
})

test_that("a large index keeps scans fast, and long free-text columns do not widen windows", {
  big <- DataShield$new(strategies = list(shield_egress(max_rows = 50L)))
  big$register_data(data.frame(USUBJID = sprintf("BGB-%03d-%05d", rep(1:100, each = 1000), 1:1e5),
                               COMMENT = paste(rep("word", 60), collapse = " ")),
                    name = "adsl", cols = c("USUBJID", "COMMENT"))
  ix <- .ids_index(big)
  expect_lte(attr(ix, "max_segments"), .DATA_SHIELD_MAX_ID_PARTS)
  expect_lt(system.time(.data_shield_value_scan("Subject 12 had grade 3 nausea on day 15.", ix))[["elapsed"]], 0.5)
  txt <- paste(rep("Mean (SD) 54.3 (10.2), Median 52.0, Min, Max 18, 85; Drug X 10MG", 6000), collapse = "\n")
  expect_lt(system.time(r <- .data_shield_value_scan(txt, ix))[["elapsed"]], 5)
  expect_false(r$hit)
})
