# tests/testthat/test-data-shield-findings.R
# Regression tests for the kiro security-audit findings (2026-08-10).
# Each `test_that` pins a fail-closed fix so the fail-open behaviour cannot
# silently return. Findings 1-4 High, 5-9 Med/Low (added as fixes land).

# --- Finding 3: value index cap fail-closed --------------------------------

.mk_shield_egress <- function()
  DataShield$new(strategies = list(shield_egress(max_rows = 0L)))

test_that("finding 3: hitting max_index_values refuses registration (fail-closed)", {
  sh <- .mk_shield_egress()
  df <- data.frame(id = sprintf("FAKEID%03d", 1:20), stringsAsFactors = FALSE)
  expect_error(sh$register_data(df, "d", cols = "id", max_index_values = 5L),
               "max_index_values")
})

test_that("finding 3: max_index_values = NA is rejected (no silent Inf)", {
  sh <- .mk_shield_egress()
  df <- data.frame(id = sprintf("FAKEID%03d", 1:20), stringsAsFactors = FALSE)
  expect_error(sh$register_data(df, "d", cols = "id", max_index_values = NA),
               "non-negative integer")
})

test_that("finding 3: negative / non-scalar max_index_values rejected", {
  sh <- .mk_shield_egress()
  df <- data.frame(id = sprintf("FAKEID%03d", 1:20), stringsAsFactors = FALSE)
  expect_error(sh$register_data(df, "d", cols = "id", max_index_values = -1L),
               "non-negative integer")
  expect_error(sh$register_data(df, "d", cols = "id", max_index_values = c(1L, 2L)),
               "non-negative integer")
})

test_that("finding 3: Inf / large cap indexes all values", {
  sh <- .mk_shield_egress()
  df <- data.frame(id = sprintf("FAKEID%03d", 1:20), stringsAsFactors = FALSE)
  n <- sh$register_data(df, "d", cols = "id", max_index_values = Inf)
  expect_gte(n, 20L)
})

# --- Finding 4: backend="local_only" fail-closed ---------------------------

test_that("finding 4: local_only with no client_factory refuses (no remote fallback)", {
  remote_called <- FALSE
  default_factory <- function(model = NULL) { remote_called <<- TRUE; structure(list(), class = "Chat") }
  cfg <- list(backend = "local_only", model = "m", client_factory = NULL)
  expect_error(codeagent:::.data_shield_reviewer_chat(cfg, default_factory),
               "local_only")
  expect_false(remote_called)   # the remote/parent factory was never invoked
})

test_that("finding 4: local_only WITH explicit client_factory is honoured", {
  fake <- structure(list(), class = "Chat")
  cfg <- list(backend = "local_only", model = "m",
              client_factory = function(model = NULL) fake)
  # set_turns/set_tools/set_system_prompt are best-effort tryCatch, so a bare
  # stub Chat is fine -- we only assert it does not error out on the guard.
  expect_error(codeagent:::.data_shield_reviewer_chat(cfg, NULL), NA)
})

test_that("finding 4: remote_sanitized (default) is unaffected", {
  fake <- structure(list(), class = "Chat")
  cfg <- list(backend = "remote_sanitized", model = "m",
              client_factory = function(model = NULL) fake)
  expect_error(codeagent:::.data_shield_reviewer_chat(cfg, NULL), NA)
})
