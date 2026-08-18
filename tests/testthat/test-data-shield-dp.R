# 31x: distributions="on"/"dp" -- categorical column counts, with an optional
# DP privacy budget. Numeric/date/logical/free-text columns are UNCHANGED in
# all three modes for v1 (see references/plan/31x-dp-distributions.TODO.md for
# why continuous-statistic DP is deferred).

.mk_dp_data <- function() {
  data.frame(
    arm = rep(c("Placebo", "DrugA"), 25),
    val = round(seq(10.1, 59.1, length.out = 50), 3),
    stringsAsFactors = FALSE)
}

test_that("distributions='on' shows real per-category counts, no noise", {
  sh <- DataShield$new(strategies = list(shield_describe(distributions = "on", k_anon = 5)))
  sh$register_data(.mk_dp_data(), name = "d")
  out <- sh$describe("d")
  expect_match(out, "DrugA \\(n=25\\)")
  expect_match(out, "Placebo \\(n=25\\)")
})

test_that("distributions='on' still suppresses categories below k_anon", {
  df <- data.frame(grp = c(rep("Big", 20), rep("Tiny", 2)), stringsAsFactors = FALSE)
  sh <- DataShield$new(strategies = list(shield_describe(distributions = "on", k_anon = 5)))
  sh$register_data(df, name = "d", cols = character())
  out <- sh$describe("d")
  expect_match(out, "Big \\(n=20\\)")
  expect_match(out, "<rare suppressed>")
  expect_false(grepl("Tiny", out))
})

test_that("distributions='dp' produces noised, non-negative integer counts", {
  set.seed(1)
  sh <- DataShield$new(strategies = list(
    shield_describe(distributions = "dp", k_anon = 5, dp_epsilon = 1, dp_budget = 100)))
  sh$register_data(.mk_dp_data(), name = "d")
  out <- sh$describe("d")
  m <- regmatches(out, gregexpr("n\u2248(-?\\d+)", out))[[1]]
  expect_length(m, 2L)
  counts <- as.integer(sub("n\u2248", "", m))
  expect_true(all(counts >= 0L))
})

test_that("distributions='dp' noised counts are unbiased around the true count on average", {
  # Statistical property test (not a fragile exact-value assertion): draw many
  # independent describe() calls with a large budget and check the noised
  # count's mean is close to the true count (25) within a few noise scales.
  set.seed(2)
  sh <- DataShield$new(strategies = list(
    shield_describe(distributions = "dp", k_anon = 5, dp_epsilon = 1, dp_budget = 10000)))
  sh$register_data(.mk_dp_data(), name = "d")
  draws <- vapply(seq_len(200L), function(i) {
    out <- sh$describe("d")
    m <- regmatches(out, regexec("DrugA \\(n\u2248(-?\\d+)\\)", out))[[1]]
    as.integer(m[[2]])
  }, integer(1))
  expect_equal(mean(draws), 25, tolerance = 2)   # scale = 2/1 = 2 -> sd ~ 2*sqrt(2)
})

test_that("distributions='dp' degrades to labels-only once the dataset budget is exhausted", {
  sh <- DataShield$new(strategies = list(
    shield_describe(distributions = "dp", k_anon = 5, dp_epsilon = 1, dp_budget = 1)))
  sh$register_data(.mk_dp_data(), name = "d")

  first <- sh$describe("d")
  expect_match(first, "n\u2248")
  expect_equal(sh$dp_budget_remaining("d"), 0)

  second <- sh$describe("d")
  expect_false(grepl("n\u2248", second))
  expect_match(second, "labels=\\[DrugA, Placebo\\]")
  expect_equal(sh$dp_budget_remaining("d"), 0)   # never goes negative
})

test_that("dp_budget_remaining() reports NA outside dp mode and decrements under dp", {
  sh_off <- DataShield$new(strategies = list(shield_describe(k_anon = 5)))
  sh_off$register_data(.mk_dp_data(), name = "d")
  expect_true(is.na(sh_off$dp_budget_remaining("d")))
  expect_true(is.na(sh_off$dp_budget_remaining()[["d"]]))

  sh_dp <- DataShield$new(strategies = list(
    shield_describe(distributions = "dp", dp_epsilon = 1, dp_budget = 3)))
  sh_dp$register_data(.mk_dp_data(), name = "d")
  expect_equal(sh_dp$dp_budget_remaining("d"), 3)
  sh_dp$describe("d")
  expect_equal(sh_dp$dp_budget_remaining("d"), 2)
})

test_that("dp_budget consumption/exhaustion is recorded in the audit log", {
  sh <- DataShield$new(strategies = list(
    shield_describe(distributions = "dp", dp_epsilon = 1, dp_budget = 1)))
  sh$register_data(.mk_dp_data(), name = "d")
  sh$describe("d")
  sh$describe("d")
  events <- sh$audit()
  dp_events <- events[events$strategy == "dp_budget", ]
  expect_equal(nrow(dp_events), 2L)
  expect_equal(as.character(dp_events$action), c("consume", "exhausted"))
})

test_that("numeric/date/logical/free_text columns are unchanged across off/on/dp (31x scope limit)", {
  df <- data.frame(
    val = round(seq(10.1, 59.1, length.out = 50), 3),
    flag = rep(c(TRUE, FALSE), 25),
    freetext = paste0("note-", seq_len(50)),
    stringsAsFactors = FALSE)
  outs <- lapply(c("off", "on", "dp"), function(mode) {
    sh <- DataShield$new(strategies = list(shield_describe(distributions = mode, k_anon = 5)))
    sh$register_data(df, name = "d", sensitivity = c(val = "measure", flag = "measure",
                                                      freetext = "measure"))
    sh$describe("d")
  })
  # range=/labels=[FALSE, TRUE]/format=free_text lines must be byte-identical
  # regardless of distributions mode.
  extract <- function(x) grep("^- (val|flag|freetext):", strsplit(x, "\n")[[1]], value = TRUE)
  expect_identical(extract(outs[[1]]), extract(outs[[2]]))
  expect_identical(extract(outs[[1]]), extract(outs[[3]]))
})

test_that("shield_describe() validates dp_epsilon/dp_budget", {
  expect_error(shield_describe(dp_epsilon = 0), "positive number")
  expect_error(shield_describe(dp_epsilon = -1), "positive number")
  expect_error(shield_describe(dp_budget = 0), "positive number")
  expect_error(shield_describe(dp_budget = c(1, 2)), "positive number")
})

test_that("schema_block() also consumes and persists the DP budget", {
  sh <- DataShield$new(strategies = list(
    shield_describe(distributions = "dp", dp_epsilon = 1, dp_budget = 2)))
  sh$register_data(.mk_dp_data(), name = "d")
  b1 <- sh$schema_block()
  expect_match(b1, "n\u2248")
  expect_equal(sh$dp_budget_remaining("d"), 1)
  sh$schema_block()
  expect_equal(sh$dp_budget_remaining("d"), 0)
})
