# tests/testthat/test-input-gate.R
# Data Shield input gate (edge 1): scan_prompt + .input_gate_scan (text,
# attachments, images).

make_shield <- function() {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L), shield_regex()))
  df <- data.frame(subject_id = sprintf("SUBJECT%03d", 1:50),
                   stringsAsFactors = FALSE)
  sh$register_data(df, name = "d")
  sh
}

test_that("scan_prompt redacts a protected value but keeps the rest (edge 1)", {
  sh <- make_shield()
  r <- sh$scan_prompt("tell me about SUBJECT001 please", on_fail = "redact")
  expect_identical(r$action, "redact")
  expect_false(grepl("SUBJECT001", r$text, fixed = TRUE))   # value gone
  expect_true(grepl("tell me about", r$text, fixed = TRUE)) # rest preserved
  expect_true(grepl("please", r$text, fixed = TRUE))
  expect_true(grepl("[REDACTED]", r$text, fixed = TRUE))
})

test_that("scan_prompt redacts PII (regex) but keeps the rest", {
  sh <- make_shield()
  r <- sh$scan_prompt("email me at foo@bar.com thanks", on_fail = "redact")
  expect_identical(r$action, "redact")
  expect_false(grepl("foo@bar.com", r$text, fixed = TRUE))
  expect_true(grepl("email me at", r$text, fixed = TRUE))
  expect_true(grepl("thanks", r$text, fixed = TRUE))
})

test_that("scan_prompt block rejects the whole turn", {
  sh <- make_shield()
  r <- sh$scan_prompt("subject SUBJECT002", on_fail = "block")
  expect_identical(r$action, "block")
  expect_match(r$text, "blocked")
})

test_that("scan_prompt passes clean text unchanged", {
  sh <- make_shield()
  r <- sh$scan_prompt("what is the weather today", on_fail = "redact")
  expect_identical(r$action, "pass")
  expect_identical(r$text, "what is the weather today")
})

test_that("scan_prompt fires on_progress for each detector stage", {
  sh <- make_shield()
  stages <- character(0)
  sh$scan_prompt("SUBJECT003 and foo@x.com", on_fail = "redact",
                 on_progress = function(p) stages <<- c(stages, p$stage))
  expect_true("regex" %in% stages)
  expect_true("value_match" %in% stages)
})

test_that("scan_prompt ignores empty / non-scalar input", {
  sh <- make_shield()
  expect_identical(sh$scan_prompt("", on_fail = "redact")$action, "pass")
})

test_that(".input_gate_scan is a no-op without an active shield", {
  res <- codeagent:::.input_gate_scan("hello SUBJECT001", settings = list(), chat = NULL)
  expect_identical(res$action, "pass")
  expect_identical(res$input, "hello SUBJECT001")   # untouched, no shield
})

test_that(".input_gate_scan redacts a scalar via the settings-resolved shield", {
  sh <- make_shield()
  res <- codeagent:::.input_gate_scan(
    "about SUBJECT004 ok", settings = list(data_shield_engine = sh))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT004", res$input, fixed = TRUE))
  expect_true(grepl("about", res$input, fixed = TRUE))
})

test_that(".input_gate_scan honors block via settings on_fail", {
  sh <- make_shield()
  res <- codeagent:::.input_gate_scan(
    "SUBJECT005", settings = list(data_shield_engine = sh,
                                  data_shield_prompt_on_fail = "block"))
  expect_identical(res$action, "block")
})

test_that(".input_gate_scan degrades ask to redact (fail-safe, never sends raw)", {
  sh <- make_shield()
  res <- codeagent:::.input_gate_scan(
    "SUBJECT006 here", settings = list(data_shield_engine = sh,
                                       data_shield_prompt_on_fail = "ask"))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT006", res$input, fixed = TRUE))
})

test_that(".input_gate_scan redacts the text element of a contents list", {
  sh <- make_shield()
  inp <- list("tell me about SUBJECT007", "second text part")
  res <- codeagent:::.input_gate_scan(inp, settings = list(data_shield_engine = sh))
  expect_identical(res$action, "redact")
  expect_true(is.list(res$input))                       # shape preserved
  expect_length(res$input, 2L)
  expect_false(grepl("SUBJECT007", res$input[[1L]], fixed = TRUE))
  expect_identical(res$input[[2L]], "second text part")
})

test_that(".input_gate_scan passes a clean contents list unchanged", {
  sh <- make_shield()
  inp <- list("just a normal question", "and another")
  res <- codeagent:::.input_gate_scan(inp, settings = list(data_shield_engine = sh))
  expect_identical(res$action, "pass")
  expect_identical(res$input, inp)
})

test_that(".input_gate_scan invokes the image_scanner hook and can block", {
  sh <- make_shield()
  img <- structure(list(), class = "fake_image")   # sentinel; hook keys off nothing
  seen <- 0L
  scanner <- function(content) { seen <<- seen + 1L; list(action = "block") }
  # Force the image branch: a list element the scanner is asked about. We stub
  # the image predicate by passing an actual ContentImage if available; else the
  # hook path is exercised via settings and a real ellmer image.
  ci <- tryCatch(ellmer::content_image_url("https://example.com/x.png"),
                 error = function(e) NULL)
  skip_if(is.null(ci), "ellmer content_image_url unavailable")
  res <- codeagent:::.input_gate_scan(
    list("look at this", ci),
    settings = list(data_shield_engine = sh, data_shield_image_scanner = scanner))
  expect_identical(res$action, "block")
  expect_true(seen >= 1L)
})

test_that(".input_gate_scan skips images when no scanner is set (blind spot)", {
  sh <- make_shield()
  ci <- tryCatch(ellmer::content_image_url("https://example.com/x.png"),
                 error = function(e) NULL)
  skip_if(is.null(ci), "ellmer content_image_url unavailable")
  res <- codeagent:::.input_gate_scan(
    list("clean text", ci), settings = list(data_shield_engine = sh))
  expect_identical(res$action, "pass")
})

test_that(".input_gate_scan input_scanners switch: value_match only skips PII", {
  sh <- make_shield()
  res <- codeagent:::.input_gate_scan(
    "SUBJECT010 and foo@bar.com",
    settings = list(data_shield_engine = sh,
                    data_shield_input_scanners = c("value_match")))
  expect_identical(res$action, "redact")
  expect_false(grepl("SUBJECT010", res$input, fixed = TRUE))   # registered value gone
  expect_true(grepl("foo@bar.com", res$input, fixed = TRUE))   # PII kept (regex off)
})

test_that(".input_gate_scan input_scanners switch: regex only skips value_match", {
  sh <- make_shield()
  res <- codeagent:::.input_gate_scan(
    "SUBJECT011 and foo@bar.com",
    settings = list(data_shield_engine = sh,
                    data_shield_input_scanners = c("regex")))
  expect_identical(res$action, "redact")
  expect_true(grepl("SUBJECT011", res$input, fixed = TRUE))    # value_match off
  expect_false(grepl("foo@bar.com", res$input, fixed = TRUE))  # PII redacted
})

test_that("data_shield_ocr_scanner degrades to pass when tesseract absent", {
  # Guard is requireNamespace: with the pkg missing the scanner must never block.
  skip_if(requireNamespace("tesseract", quietly = TRUE),
          "tesseract installed -- this test asserts the absent-dep path")
  sh <- make_shield()
  scan <- codeagent::data_shield_ocr_scanner(sh)
  ci <- tryCatch(ellmer::content_image_url("https://example.com/x.png"),
                 error = function(e) NULL)
  skip_if(is.null(ci), "ellmer content_image_url unavailable")
  expect_identical(scan(ci)$action, "pass")
})

test_that("data_shield_ocr_scanner blocks on a protected value in the image", {
  skip_if_not_installed("tesseract")
  sh <- make_shield()
  # Render a protected value (SUBJECT001) into a PNG for the OCR to read back.
  f <- tempfile(fileext = ".png")
  grDevices::png(f, width = 320, height = 80)
  op <- graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::text(0.5, 0.5, "SUBJECT001", cex = 3)
  graphics::par(op)
  grDevices::dev.off()
  ci <- ellmer::content_image_file(f)
  scan <- codeagent::data_shield_ocr_scanner(sh, on_fail = "block")
  res  <- scan(ci)
  expect_identical(res$action, "block")
  expect_match(res$text, "image blocked")
})

test_that("data_shield_ocr_scanner passes a clean image (no protected text)", {
  skip_if_not_installed("tesseract")
  sh <- make_shield()
  f <- tempfile(fileext = ".png")
  grDevices::png(f, width = 320, height = 80)
  op <- graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::text(0.5, 0.5, "hello world", cex = 3)
  graphics::par(op)
  grDevices::dev.off()
  ci <- ellmer::content_image_file(f)
  scan <- codeagent::data_shield_ocr_scanner(sh)
  expect_identical(scan(ci)$action, "pass")
})

test_that(".input_gate_scan wires data_shield_ocr_scanner via settings", {
  skip_if_not_installed("tesseract")
  sh <- make_shield()
  f <- tempfile(fileext = ".png")
  grDevices::png(f, width = 320, height = 80)
  op <- graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::text(0.5, 0.5, "SUBJECT002", cex = 3)
  graphics::par(op)
  grDevices::dev.off()
  ci <- ellmer::content_image_file(f)
  res <- codeagent:::.input_gate_scan(
    list("look", ci),
    settings = list(data_shield_engine = sh,
                    data_shield_image_scanner = codeagent::data_shield_ocr_scanner(sh)))
  expect_identical(res$action, "block")
})
