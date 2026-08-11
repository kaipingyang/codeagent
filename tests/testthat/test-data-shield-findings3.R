# tests/testthat/test-data-shield-findings3.R
# Regression tests for kiro's THIRD-round security audit (2026-08-11).
# Each test pins a fail-closed fix that round-2 left open (the gate helpers were
# fail-closed but entry points / detectors / egress re-opened the failure).

# --- Entry-point fail-closed (guarded wrappers) ------------------------------

test_that("input gate guarded wrapper blocks on scan exception (not raw pass)", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  df <- data.frame(id = sprintf("FAKEID%03d", 1:20), stringsAsFactors = FALSE)
  sh$register_data(df, "d", cols = "id")
  s <- list(data_shield_engine = sh, data_shield_input_scanners = c("value_macth"))
  r <- codeagent:::.input_gate_guarded("FAKEID001", settings = s)
  expect_identical(r$action, "block")
})

test_that("output gate guarded wrapper redacts on scan exception", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  s <- list(data_shield_engine = sh, data_shield_output_scanners = c("value_macth"))
  r <- codeagent:::.output_gate_guarded("some reply", settings = s)
  expect_false(identical(r$action, "pass"))
})

test_that("guarded wrappers are no-ops when no shield is active", {
  expect_identical(codeagent:::.input_gate_guarded("hi", settings = list())$action, "pass")
  expect_identical(codeagent:::.output_gate_guarded("hi", settings = list())$action, "pass")
})

# --- Core detector fail-closed (scan_prompt raises, not fakes no-hit) --------

test_that("scan_prompt raises when the value detector throws (no fake no-hit)", {
  # A broken index whose value scan errors -> egress detector must fail CLOSED
  # (withhold), never fake a no-hit. Force the error by mocking the value scan.
  testthat::local_mocked_bindings(
    .data_shield_value_scan = function(...) stop("scan boom"),
    .package = "codeagent")
  out <- codeagent:::.data_shield_process_text(
    "row FAKEID001", index = new.env(), detectors = c("value_match"))
  expect_true(isTRUE(out$changed))
  expect_match(out$text, "withheld|blocked|fail-closed")
})

# --- egress list / sync stop / promise rejection -----------------------------

test_that("egress withholds a protected value buried in a list result", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  df <- data.frame(id = sprintf("FAKEID%03d", 1:20), stringsAsFactors = FALSE)
  sh$register_data(df, "d", cols = "id")
  idx <- sh$.__enclos_env__$private$index
  out <- codeagent:::.data_shield_filter_result(list(payload = "FAKEID001"), index = idx)
  expect_true(is.character(out) && grepl("withheld|blocked", out))
})

test_that("wrapped sync tool that stop()s rejects with a fixed message, not the raw error", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  df <- data.frame(id = sprintf("FAKEID%03d", 1:20), stringsAsFactors = FALSE)
  sh$register_data(df, "d", cols = "id")
  tool <- ellmer::tool(function() stop("failed on FAKEID001 leaked"),
                       name = "Boom", description = "errors with a protected value",
                       arguments = list())
  wrapped <- codeagent:::.data_shield_wrap_tool(tool, sh)
  fn <- S7::S7_data(wrapped)
  # ellmer::tool_reject() RAISES an ellmer_tool_reject condition (invoke_tools
  # turns it into a tool result). Capture it and assert the raw error text
  # (with FAKEID001) is NOT in the surfaced message.
  msg <- tryCatch(suppressWarnings(fn()),
                  ellmer_tool_reject = function(c) conditionMessage(c),
                  error = function(e) conditionMessage(e))
  expect_false(grepl("FAKEID001", msg, fixed = TRUE))
  expect_true(grepl("fail-closed|withheld", msg))
})

# --- column egress none: low-cardinality deny --------------------------------

test_that("egress='none' denies even a low-cardinality column (ALPHA/BETA)", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  df <- data.frame(grp = rep(c("ALPHA", "BETA"), 10), stringsAsFactors = FALSE)
  sh$register_data(df, "d", sensitivity = c(grp = "identifier"),
                   column_access = list(grp = list(egress = "none")))
  expect_match(sh$scan_egress("result has ALPHA in it"), "denied")
  expect_identical(sh$scan_egress("nothing here"), "nothing here")
})

# --- AuditCode: directory / read failure -> block ----------------------------

test_that("AuditCode blocks a directory masquerading as a source file", {
  d <- file.path(tempdir(), paste0("auditroot", as.integer(Sys.time()) %% 100000))
  dir.create(d, showWarnings = FALSE)
  dir.create(file.path(d, "not-a-file.R"), showWarnings = FALSE)
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  res <- codeagent:::.audit_code_impl('source("not-a-file.R")', shield = sh,
                                      project_root = d)
  expect_length(res$allowed, 0L)
  expect_true(length(res$blocked) >= 1L)
  expect_identical(res$risk, "block")
})

# --- image scanner exception -> block ----------------------------------------

test_that("a configured image scanner that throws fails closed to block", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  boom_scanner <- function(content_image) stop("boom")
  img <- ellmer::content_image_url("data:image/png;base64,AA==")
  s <- list(data_shield_engine = sh, data_shield_image_scanner = boom_scanner)
  res <- codeagent:::.input_gate_scan(list("look at this", img), settings = s)
  expect_identical(res$action, "block")
})

test_that("a configured image scanner returning an invalid contract fails closed", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  bad_scanner <- function(content_image) list(nonsense = TRUE)  # no $action
  img <- ellmer::content_image_url("data:image/png;base64,AA==")
  s <- list(data_shield_engine = sh, data_shield_image_scanner = bad_scanner)
  res <- codeagent:::.input_gate_scan(list("look", img), settings = s)
  expect_identical(res$action, "block")
})

# --- R6 finalizer is private (no public-finalize warning) --------------------

test_that("DataShield finalize is private (R6 compliance)", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  # public interface must NOT expose finalize
  expect_false("finalize" %in% ls(sh))
})
