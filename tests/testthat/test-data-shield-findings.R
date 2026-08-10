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
  # Reviewer isolation is now VERIFIED (round-2 #9), so the stub Chat must
  # support the isolation calls and report a clean, model-matching state.
  fake <- structure(list(
    set_turns = function(...) invisible(NULL),
    set_tools = function(...) invisible(NULL),
    set_system_prompt = function(...) invisible(NULL),
    get_turns = function() list(),
    get_model = function() "m"), class = "Chat")
  cfg <- list(backend = "local_only", model = "m",
              client_factory = function(model = NULL) fake)
  expect_error(codeagent:::.data_shield_reviewer_chat(cfg, NULL), NA)
})

test_that("finding 4: remote_sanitized (default) is unaffected", {
  fake <- structure(list(
    set_turns = function(...) invisible(NULL),
    set_tools = function(...) invisible(NULL),
    set_system_prompt = function(...) invisible(NULL),
    get_turns = function() list(),
    get_model = function() "m"), class = "Chat")
  cfg <- list(backend = "remote_sanitized", model = "m",
              client_factory = function(model = NULL) fake)
  expect_error(codeagent:::.data_shield_reviewer_chat(cfg, NULL), NA)
})

# --- Finding 1: reviewer sees code fields only, never other arg values -----

test_that("finding 1: non-code tool args are withheld from the reviewer", {
  r <- codeagent:::.data_shield_reviewer_input(
    "Write", list(file_path = "report.txt",
                  content = "proprietary phrase FAKE-ROW-777"))
  expect_false(grepl("FAKE-ROW-777", r, fixed = TRUE))   # value withheld
  expect_true(grepl("value withheld", r, fixed = TRUE))
})

test_that("finding 1: code-field value IS shown to the reviewer", {
  r <- codeagent:::.data_shield_reviewer_input(
    "RunR", list(code = 'system("ls"); download.file(x)'))
  expect_true(grepl("download.file", r, fixed = TRUE))
  r2 <- codeagent:::.data_shield_reviewer_input("Bash", list(command = "curl http://x"))
  expect_true(grepl("curl", r2, fixed = TRUE))
})

# --- Finding 2: column_access tiers fail-closed ----------------------------

.mk_ca_shield <- function(ca) {
  sh <- DataShield$new(strategies = list(shield_describe(k_anon = 1L),
                                         shield_egress(max_rows = 0L)))
  df <- data.frame(val = round(seq(101, 108, length.out = 8), 1),
                   email = sprintf("u%d@x.com", 1:8), stringsAsFactors = FALSE)
  sh$register_data(df, "d",
                   sensitivity = c(val = "measure", email = "measure"),
                   column_access = ca)
  sh
}

test_that("finding 2: prompt='none' omits the column entirely", {
  d <- .mk_ca_shield(list(val = list(prompt = "none")))$describe("d")
  expect_false(grepl("- val", d, fixed = TRUE))
})

test_that("finding 2: prompt='schema' gives type/missing only, no range/values", {
  d <- .mk_ca_shield(list(val = list(prompt = "schema")))$describe("d")
  expect_false(grepl("range=", d, fixed = TRUE))
  expect_true(grepl("access=schema", d, fixed = TRUE))
})

test_that("finding 2: omitting prompt defaults to none (not raw)", {
  d <- .mk_ca_shield(list(val = list(egress = "raw", reason = "x")))$describe("d")
  expect_false(grepl("access=raw; values", d, fixed = TRUE))
})

test_that("finding 2: raw with scan_secrets redacts PII in enumerated values", {
  d <- .mk_ca_shield(list(email = list(prompt = "raw", reason = "x",
                                       scan_secrets = TRUE)))$describe("d")
  expect_false(grepl("u1@x.com", d, fixed = TRUE))
  expect_true(grepl("REDACTED", d, fixed = TRUE))
})

test_that("finding 2: unknown column_access field is rejected", {
  expect_error(.mk_ca_shield(list(val = list(typoo = "x"))), "unknown field")
})

# --- Finding 5: register_data positional compatibility ---------------------

test_that("finding 5: legacy 6-positional register_data call works", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  df <- data.frame(id = sprintf("SUBJ%03d", 1:20), stringsAsFactors = FALSE)
  # register_data(df, name, sensitivity, cols, min_len, min_card) -- 4L/8L must
  # bind to min_len/min_card, NOT column_access.
  expect_error(sh$register_data(df, "d", c(id = "identifier"), NULL, 4L, 8L), NA)
})

# --- Finding 7: close() releases reviewer/factory/sandbox ------------------

test_that("finding 7: close() clears reviewers and sandbox", {
  sh <- DataShield$new(strategies = list(shield_reviewer(model = "m"),
                                         shield_sandbox(project_root = getwd()),
                                         shield_egress(max_rows = 0L)))
  expect_equal(sh$coverage()$reviewers, 1L)
  sh$close()
  expect_equal(sh$coverage()$reviewers, 0L)
  expect_null(sh$coverage()$sandbox)
})

