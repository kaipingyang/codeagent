# G2 — single-layer combination safety matrix.
#
# Data Shield strategies compose freely via the list DSL. This suite locks the
# security consequence of each combination so a future refactor cannot quietly
# make "egress is the non-optional boundary" false. The claim under test:
#   - a combination CONTAINING shield_egress withholds bulk + single-value leaks;
#   - ingress-only / describe-only does NOT (ingress rules are bypassable by
#     aliasing; describe only governs the model's metadata query, not arbitrary
#     tool output) — so those combos must be documented/known-unsafe, and this
#     test asserts the asymmetry rather than pretending they are safe.

# One protected dataset reused across combinations. High-entropy identifier
# values so value_match has something to index.
make_protected <- function(strategies) {
  shield <- DataShield$new(strategies = strategies)
  df <- data.frame(
    SUBJID = paste0("SUBJ", sprintf("%03d", 1:40)),
    stringsAsFactors = FALSE)
  shield$register_data(df, name = "study",
                       sensitivity = c(SUBJID = "identifier"))
  shield
}

# Attack payloads that a tool might return (egress) — each leaks protected data.
BULK_LEAK   <- paste(c("  SUBJID", paste0("  SUBJ", sprintf("%03d", 1:40))),
                     collapse = "\n")                 # bulk tabular dump
SINGLE_LEAK <- "The enrolled patient is SUBJ007, confirmed."   # one targeted value
SAFE_OUTPUT <- "The analysis converged in 12 iterations."      # nothing protected

egress_withholds <- function(shield, text) {
  out <- shield$scan_egress(text, context = list(edge = "egress",
                                                 tool_name = "AnyTool"))
  !identical(out, text)   # TRUE => filtered/withheld (not passed through verbatim)
}

test_that("a combination containing shield_egress withholds bulk and single leaks", {
  shield <- make_protected(list(
    shield_describe(k_anon = 5),
    shield_egress(detectors = c("row_cap", "value_match"), max_rows = 0)))
  expect_true(egress_withholds(shield, BULK_LEAK))     # row_cap catches bulk
  expect_true(egress_withholds(shield, SINGLE_LEAK))   # value_match catches single
  expect_false(egress_withholds(shield, SAFE_OUTPUT))  # harmless output passes
})

test_that("egress + ingress + regex (recommended) still withholds leaks", {
  shield <- make_protected(list(
    shield_ingress(on_fail = "block"),
    shield_egress(max_rows = 0),
    shield_regex(on_fail = "redact")))
  expect_true(egress_withholds(shield, BULK_LEAK))
  expect_true(egress_withholds(shield, SINGLE_LEAK))
  expect_false(egress_withholds(shield, SAFE_OUTPUT))
})

test_that("ingress-only does NOT filter tool output (egress is not optional)", {
  # ingress guards tool ARGUMENTS, not results. With no egress stage, a tool that
  # returns protected rows is not filtered — this is the known-unsafe combo the
  # docs warn about. Assert the gap so nobody assumes ingress-only is safe.
  shield <- make_protected(list(shield_ingress(on_fail = "block")))
  expect_false(egress_withholds(shield, BULK_LEAK))
  expect_false(egress_withholds(shield, SINGLE_LEAK))
})

test_that("ingress rules are bypassable by aliasing (why egress is the boundary)", {
  # ingress matches print(study) but not an aliased copy; the argument scan is a
  # cheap pre-filter, not a guarantee.
  shield <- make_protected(list(shield_ingress(on_fail = "block")))
  scan <- function(code) shield$scan_ingress("RunR", list(code = code))$action
  expect_identical(scan("print(study)"), "block")             # direct: caught
  expect_identical(scan("y <- study; print(y)"), "pass")      # aliased: slips past ingress
})

test_that("describe-only does NOT filter arbitrary tool output", {
  # DescribeData governs the model's sanctioned metadata query. It does not wrap
  # or filter what other tools return, so protected rows in tool output pass.
  shield <- make_protected(list(shield_describe(k_anon = 5)))
  expect_false(egress_withholds(shield, BULK_LEAK))
  expect_false(egress_withholds(shield, SINGLE_LEAK))
})

test_that("regex-only catches PII shapes but misses non-PII protected ids", {
  # shield_regex is a fallback for unregistered PII shapes; it is not a
  # substitute for value_match on arbitrary protected identifiers.
  shield <- DataShield$new(strategies = list(shield_regex(on_fail = "redact")))
  # an email (PII shape) is redacted
  expect_true(egress_withholds(shield, "contact a.person@example.org now"))
  # a bespoke study id with no registered index and no PII shape slips past
  expect_false(egress_withholds(shield, SINGLE_LEAK))
})
