# Registering many datasets merges each new one into the live index instead of
# rebuilding it every time, and labels are added in bulk (LiveTFLAI 2026-11-26:
# 32 ADaM datasets took 15.5 s). The index must be exactly what one full
# rebuild gives, and what the one-value-at-a-time code gave.

snap_env <- function(e) { k <- sort(ls(e, all.names = TRUE)); stats::setNames(lapply(k, function(x) get(x, envir = e)), k) }
snap <- function(sh) {
  p <- sh$.__enclos_env__$private
  list(index = snap_env(p$index), deny = snap_env(p$deny_index),
       raw = sort(paste(attr(p$deny_index, "raw_values") %||% character(), names(attr(p$deny_index, "raw_values") %||% character()))),
       variants = sort(ls(attr(p$index, "variants"), all.names = TRUE)),
       max_segments = attr(p$index, "max_segments"), shapes = sort(attr(p$index, "shapes")))
}
mkdata <- function(seed) {
  set.seed(seed); n <- 60
  ids <- sprintf("BGB-%03d-%04d", sample(1:3, n, TRUE), seq_len(n))
  list(
    ADSL = data.frame(USUBJID = ids, SUBJID = sprintf("%04d", seq_len(n)), SITEID = sprintf("S%02d", sample(1:12, n, TRUE)),
                      COUNTRY = sample(c("CHN", "USA", "KOR", "NZL", "FRA", "BRA", "JPN", "ITA", "ESP"), n, TRUE), AGE = sample(20:80, n, TRUE)),
    ADAE = data.frame(USUBJID = sample(ids, 90, TRUE), AETERM = sample(c("NAUSEA", "RASH", "FATIGUE", "HEADACHE", "COUGH", "FEVER", "PAIN", "ANEMIA", "DIZZY"), 90, TRUE)),
    ADCM = data.frame(USUBJID = sample(ids, 40, TRUE), SUBJID = sample(sprintf("%04d", seq_len(n)), 40, TRUE), CMTRT = sprintf("DRUG%02d", sample(1:20, 40, TRUE))))
}
reg <- function(sh, d) for (nm in names(d)) {
  df <- d[[nm]]; ids <- intersect(c("USUBJID", "SUBJID", "SITEID"), names(df))
  sh$register_data(df, name = nm, sensitivity = stats::setNames(as.list(rep("identifier", length(ids))), ids),
    column_access = list(USUBJID = list(prompt = "schema", egress = "none")))
}

test_that("incremental registration gives the index of one full rebuild", {
  sh <- DataShield$new(); reg(sh, mkdata(1))
  inc <- snap(sh)
  sh$.__enclos_env__$private$rebuild_index()
  expect_identical(inc, snap(sh))
  expect_gt(length(inc$index), 50L); expect_gt(length(inc$deny), 50L); expect_gt(length(inc$raw), 50L)
})

test_that("re-registering a dataset and clearing one rebuild the index", {
  sh <- DataShield$new(); d <- mkdata(2); reg(sh, d)
  d2 <- d; d2$ADAE$USUBJID <- sprintf("NEW-999-%04d", seq_len(nrow(d2$ADAE)))
  reg(sh, d2["ADAE"])                                   # replaced: old ADAE values must be gone
  ref <- DataShield$new(); reg(ref, list(ADSL = d$ADSL, ADAE = d2$ADAE, ADCM = d$ADCM))
  expect_identical(snap(sh), snap(ref))
  sh$clear("ADCM"); ref2 <- DataShield$new(); reg(ref2, list(ADSL = d$ADSL, ADAE = d2$ADAE))
  expect_identical(snap(sh), snap(ref2))
})

test_that("bulk labels equal the one-value-at-a-time labels", {
  one <- function(env, key, labels) {                    # the code before 2026-11-26
    labels <- as.character(labels[!vapply(as.list(labels), isTRUE, logical(1))])
    old <- if (exists(key, envir = env, inherits = FALSE)) get(key, envir = env, inherits = FALSE) else character(0)
    old <- as.character(old[!vapply(as.list(old), isTRUE, logical(1))])
    assign(key, unique(c(old, labels)), envir = env)
  }
  a <- new.env(); b <- new.env()
  assign("k1", TRUE, envir = a); assign("k1", TRUE, envir = b)          # legacy presence marker
  keys <- c("k1", "k2", "k3"); for (k in keys) one(a, k, "L1"); .data_shield_add_labels(b, keys, "L1")
  for (k in c("k2", "k4")) one(a, k, "L2"); .data_shield_add_labels(b, c("k2", "k4"), "L2")
  src <- new.env(); assign("k3", c("L3", "L1"), envir = src); assign("k5", "L5", envir = src)
  for (k in ls(src)) one(a, k, get(k, envir = src)); .data_shield_merge_labels(b, src)
  expect_identical(snap_env(a), snap_env(b))
})

test_that("blocking is unchanged: an id written any way is still withheld", {
  sh <- DataShield$new(strategies = list(shield_egress())); reg(sh, mkdata(3))
  id <- mkdata(3)$ADSL$USUBJID[5]
  out <- sh$scan_egress(paste("subject", id, "had an AE"), list(tool_name = "x"))
  expect_false(grepl(id, paste(unlist(out), collapse = " "), fixed = TRUE))
})

test_that("32 datasets register fast", {
  skip_on_cran()                                         # a timing check
  d <- mkdata(4); many <- stats::setNames(rep(list(d$ADSL), 32), sprintf("DS%02d", 1:32))
  sh <- DataShield$new()
  t <- system.time(reg(sh, many))[["elapsed"]]
  expect_lt(t, 5)
})

test_that("a deny column cut short by max_values still denies every value", {
  df <- data.frame(a = c("alpha one", "beta two", "gamma three"),
                   b = c("delta", "epsilon", "zeta"))
  set <- .data_shield_build_value_index(df, max_values = 2L, deny_all = TRUE)
  expect_true(attr(set, "truncated"))
  expect_identical(attr(set, "n"), 2L)
  # the value index stops at the cap, the fixed-string deny values do not
  expect_setequal(unname(attr(set, "raw_values")), c("alpha one", "beta two", "gamma three"))
  expect_false("delta" %in% attr(set, "raw_values"))   # columns after the cut are skipped, as before
})
