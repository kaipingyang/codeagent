#!/usr/bin/env Rscript
# G1 — value_match performance / false-positive / false-negative benchmark.
#
# Not part of the test suite (slow, needs {pharmaverseadam}). Run manually:
#   Rscript inst/bench/value_match_benchmark.R
#
# It answers the three open G1 questions with open-source pharmaverse
# CDISC-ADaM-format example data plus a scaled-up copy:
#   1. Index memory + build time as row/value count grows (is an unbounded
#      hash env a problem? do we need max_index_values?).
#   2. False positives: does scanning ordinary English text spuriously hit
#      indexed values?
#   3. False negatives: are pharmaverse short ids (4-digit SUBJID) indexed/caught,
#      or dropped by the min_len/min_card thresholds?

if (!requireNamespace("pharmaverseadam", quietly = TRUE)) {
  stop("Install {pharmaverseadam} to run this benchmark: ",
       "pak::pak('pharmaverseadam')", call. = FALSE)
}
pkgload::load_all(quiet = TRUE)

build  <- codeagent:::.data_shield_build_value_index
scan   <- codeagent:::.data_shield_value_scan
norm   <- codeagent:::.data_shield_normalize

env_bytes <- function(e) sum(vapply(ls(e, all.names = TRUE),
  function(k) as.numeric(object.size(k)), numeric(1)))

section <- function(x) cat("\n== ", x, " ==\n", sep = "")

# ---- load pharmaverse example data -----------------------------------------
data("adsl", package = "pharmaverseadam")
data("adlb", package = "pharmaverseadam")   # ~83k rows
id_cols <- c("USUBJID", "SUBJID")

section("pharmaverse ADSL identifiers")
cat(sprintf("adsl: %d rows; USUBJID card=%d (e.g. %s); SUBJID card=%d (e.g. %s)\n",
    nrow(adsl), length(unique(adsl$USUBJID)), adsl$USUBJID[[1]],
    length(unique(adsl$SUBJID)), adsl$SUBJID[[1]]))

# ---- 1. performance / memory across scale ---------------------------------
section("Index build: time + memory vs value count")
# Scale by replicating USUBJID with a suffix so cardinality actually grows.
scale_df <- function(n_ids) {
  base <- unique(adlb$USUBJID)
  reps <- ceiling(n_ids / length(base))
  ids  <- paste0(rep(base, reps)[seq_len(n_ids)], "-", seq_len(n_ids))
  data.frame(USUBJID = ids, stringsAsFactors = FALSE)
}
for (n in c(1e3, 1e4, 1e5, 5e5, 1e6)) {
  df <- scale_df(n)
  t0 <- proc.time()[["elapsed"]]
  idx <- build(df, cols = "USUBJID", max_values = Inf)  # unbounded: reproduce the 1M-value scale claim, not the 500k default cap
  dt <- proc.time()[["elapsed"]] - t0
  cat(sprintf("  n=%8d indexed=%8d build=%6.2fs keys~%6.1fMB\n",
      n, attr(idx, "n"), dt, env_bytes(idx) / 1024^2))
}

# ---- 2. false positives on ordinary prose ---------------------------------
section("False positives: scan English prose against real index")
idx <- build(adsl, cols = id_cols)
prose <- c(
  "The study analysis converged after twelve iterations without warnings.",
  "Patient demographics were summarized by treatment arm and visit window.",
  "No adverse events were reported during the double-blind treatment period.",
  "Mean change from baseline was estimated using a mixed model for repeated measures.")
fp <- sum(vapply(prose, function(s) scan(s, idx)$hit, logical(1)))
cat(sprintf("  prose lines=%d  false-positive hits=%d\n", length(prose), fp))

# ---- 3. false negatives on pharmaverse ids ---------------------------------
section("False negatives: are pharmaverse ids caught?")
u_hit <- scan(sprintf("enrolled subject %s today", adsl$USUBJID[[1]]), idx)$hit
s_id  <- adsl$SUBJID[[1]]
s_hit <- scan(sprintf("subject id %s", s_id), idx)$hit
cat(sprintf("  USUBJID %-14s caught=%s\n", adsl$USUBJID[[1]], u_hit))
cat(sprintf("  SUBJID  %-14s caught=%s  (len=%d; min_len=3 threshold)\n",
    s_id, s_hit, nchar(s_id)))
cat("  NOTE: 4-digit SUBJID passes min_len=3 but pure small ints <100 are\n",
    "  dropped; SUBJID like '1015' is kept (len 4). Verify per-study id shape.\n")

section("Done")
cat("Use these numbers to decide: (a) add max_index_values cap if memory grows\n",
    "unbounded; (b) retune min_len/min_card if FN/FP rates are unacceptable.\n")
