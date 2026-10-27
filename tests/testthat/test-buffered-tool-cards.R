# Buffered output (Data Shield / citations) holds the model's text until the
# reply is gated, but tool cards are shown as the turn runs: a host tool's
# display is output for the user. Their arguments are model-authored and pass
# the output gate first.

req <- function(args) ellmer::ContentToolRequest(id = "1", name = "bgtemplate_tfl", arguments = args)

test_that("text and thinking stay buffered; tool requests and results are shown", {
  testthat::local_mocked_bindings(.output_gate_guarded = function(text, ...) list(action = "pass", text = text))
  expect_null(.buffered_display_chunk(ellmer::ContentText("partial reply"), list(), NULL))
  expect_null(.buffered_display_chunk("raw string", list(), NULL))
  r <- .buffered_display_chunk(req(list(key = "t_dm")), list(), NULL)
  expect_equal(r@arguments, list(key = "t_dm"))
  res <- ellmer::ContentToolResult(value = "ok", request = req(list(key = "t_dm")),
                                   extra = list(display = list(html = "<b>TFL</b>")))
  shown <- .buffered_display_chunk(res, list(), NULL)
  expect_equal(shown@extra$display$html, "<b>TFL</b>")
  expect_equal(shown@request@arguments, list(key = "t_dm"))
})

test_that("arguments the output gate would change are dropped from the card", {
  testthat::local_mocked_bindings(.output_gate_guarded = function(text, ...)
    if (grepl("SUBJ-0001", text, fixed = TRUE)) list(action = "redact", text = "[redacted]")
    else list(action = "pass", text = text))
  r <- .buffered_display_chunk(req(list(filter = "USUBJID == 'SUBJ-0001'")), list(), NULL)
  expect_length(r@arguments, 0L)
  res <- ellmer::ContentToolResult(value = "ok", request = req(list(filter = "SUBJ-0001")))
  expect_length(.buffered_display_chunk(res, list(), NULL)@request@arguments, 0L)
  # unaffected arguments are kept
  expect_equal(.buffered_display_chunk(req(list(key = "t_ae")), list(), NULL)@arguments, list(key = "t_ae"))
})

test_that("a real shield drops a registered identifier from the card arguments", {
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 50L)))
  sh$register_data(data.frame(USUBJID = sprintf("BGB-001-%04d", 1:40), AGE = 40 + (1:40 %% 30)),
                   name = "adsl")
  s <- list(data_shield_engine = sh)
  hit <- .buffered_display_chunk(req(list(filter = "USUBJID == 'BGB-001-0007'")), s, NULL)
  expect_length(hit@arguments, 0L)
  ok <- .buffered_display_chunk(req(list(key = "t_dm")), s, NULL)
  expect_equal(ok@arguments, list(key = "t_dm"))
})
