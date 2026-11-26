# What the user still sees when the Data Shield keeps something from the
# model, said in every notice; per-column display (register_data(display =),
# column_access display); the tiered prompt gate (subject identifiers block,
# a pasted table of numbers asks, other protected values are redacted and the
# user is told); and the card never reaching the model.

ids <- sprintf("BGB-X-%04d", 1:40)
subj <- sprintf("S%04d", 1:40)
countries <- rep(c("CHN", "NZL", "KOR", "USA", "FRA", "BRA", "JPN", "ITA"), 5)

shield_with <- function(display = NULL, column_access = list(USUBJID = list(prompt = "schema", egress = "none")),
                        explain = TRUE) {
  sh <- DataShield$new(strategies = list(shield_egress(explain = explain), shield_regex()))
  sh$register_data(data.frame(USUBJID = ids, SUBJID = subj, COUNTRY = countries), name = "ADSL",
                   sensitivity = list(USUBJID = "identifier", SUBJID = "identifier"),
                   column_access = column_access, display = display)
  sh
}
card_result <- function(value) ellmer::ContentToolResult(
  value = value, extra = list(display = list(title = "t", html = "<table>full result</table>")))

test_that("withheld values the user may see: the card stays and the notice says so", {
  sh <- shield_with()
  out <- sh$scan_egress(card_result("rows: S0007 S0008"), list(tool_name = "explore_adam"))
  expect_true(S7::S7_inherits(out, ellmer::ContentToolResult))
  expect_identical(out@extra$display$html, "<table>full result</table>")
  expect_match(out@value, "Source: ADSL.SUBJID (identifier). The user sees the full result in the tool card", fixed = TRUE)
  expect_false(grepl("S0007", out@value, fixed = TRUE))
})

test_that("egress=none columns are hidden from the card by default; display = 'show' keeps the card", {
  out <- shield_with()$scan_egress(card_result("BGB-X-0007"), list(tool_name = "t"))
  expect_length(out@extra, 0L)
  expect_match(out@value, "denied.*not shown to the user either")
  shown <- shield_with(display = "show")$scan_egress(card_result("BGB-X-0007"), list(tool_name = "t"))
  expect_identical(shown@extra$display$html, "<table>full result</table>")
  expect_match(shown@value, "denied.*ADSL.USUBJID \\(egress=none\\).*user sees the full result in the tool card")
  expect_false(grepl("BGB-X-0007", shown@value, fixed = TRUE))
})

test_that("a column can hide itself from the card; one hidden value hides the card", {
  sh <- shield_with(column_access = list(USUBJID = list(prompt = "schema", egress = "none"),
                                         SUBJID = list(display = "hide")))
  out <- sh$scan_egress(card_result("S0007 from CHN"), list(tool_name = "t"))
  expect_length(out@extra, 0L)
  expect_match(out@value, "not shown to the user either")
  expect_error(shield_with(display = "maybe"), "display")
  expect_error(shield_with(column_access = list(SUBJID = list(display = "x"))), "display must be")
})

test_that("results without a card, and explain = FALSE", {
  sh <- shield_with()
  expect_match(sh$scan_egress("plain S0007", list(tool_name = "t")), "not shown to the user either")
  bare <- shield_with(explain = FALSE)$scan_egress(card_result("S0007"), list(tool_name = "t"))
  expect_identical(bare@value, "[data_shield] output withheld: contains 1 protected data value(s).")
  expect_identical(bare@extra$display$html, "<table>full result</table>")      # same keep/drop decision
})

test_that("notices for calls that did not run say the user saw nothing", {
  expect_match(.DATA_SHIELD_SEEN[["not_run"]], "did not run")
  src <- paste(deparse(.data_shield_wrap_tool), collapse = "\n")
  expect_match(src, "The error was not shown to the user either", fixed = TRUE)
  gate <- paste(deparse(.tool_gate_fn), collapse = "\n")    # the installed code, not the source tree
  expect_match(gate, "The tool did not run, so the user saw no result either", fixed = TRUE)
})

# ---- prompt gate --------------------------------------------------------------
gate <- function(text, sh = shield_with(), on_fail = "ask", can_ask = TRUE)
  .input_gate_guarded(text, list(data_shield_engine = sh, data_shield_prompt_on_fail = on_fail),
                      can_ask = can_ask)

test_that("subject identifiers in a message block it, with the reason and never the value", {
  r <- gate("why is S0007 missing?")
  expect_identical(r$action, "block")
  expect_match(r$text, "not sent: it contains subject identifiers. Source: ADSL.SUBJID (identifier).", fixed = TRUE)
  expect_false(grepl("S0007", r$text, fixed = TRUE))
  expect_identical(gate("row BGB-X-0003")$action, "block")
})

test_that("a pasted table of numbers asks; prose with numbers does not", {
  tab <- paste(c("Arm A\t12 (40.0)\t3", "Arm B\t10 (33.3)\t4", "Arm C\t8 (26.7)\t5",
                 "Total\t30 (100)\t12", "Missing\t0\t0"), collapse = "\n")
  r <- gate(tab)
  expect_identical(r$action, "ask")
  expect_match(r$question, "table of results (5 lines with numbers)", fixed = TRUE)
  expect_identical(gate("what does 12 (40.0%) in arm A mean?")$action, "pass")
  # the same table pasted into a composer that joins the lines (tabs kept)
  flat <- gsub("\n", "", tab, fixed = TRUE)
  r2 <- gate(flat)
  expect_identical(r2$action, "ask")
  expect_match(r2$question, "table cells with numbers", fixed = TRUE)
  # results written as n (%), no tabs
  expect_identical(gate("Male 12 (40.0) Female 18 (60.0) Total 30 (100)")$action, "ask")
  expect_identical(gate("compare 12 (40%) with 18 (60%)")$action, "pass")
  # no way to ask (CLI): the input goes on as before
  expect_identical(gate(tab, can_ask = FALSE)$action, "pass")
})

test_that("other protected values are redacted and the user is told what", {
  r <- gate("patients from CHN")
  expect_identical(r$action, "redact")
  expect_false(grepl("CHN", r$input, fixed = TRUE))
  note <- .input_gate_user_note(r)
  expect_match(note, "removed protected values from your message.*ADSL.COUNTRY \\(quasi\\)")
  expect_false(grepl("CHN", note, fixed = TRUE))
  expect_null(.input_gate_user_note(list(action = "pass")))
  # the audit says where they came from
  sh <- shield_with(); gate("patients from CHN", sh)
  expect_true(any(grepl("ADSL.COUNTRY (quasi)", sh$audit()$reason, fixed = TRUE)))
})

test_that("the Shiny chat asks before sending a pasted table, and tells the user", {
  src <- paste(deparse(body(server_chat)), collapse = "\n")
  expect_match(src, "can_ask = is.function(ask_q)", fixed = TRUE)
  expect_match(src, "Send it to the model", fixed = TRUE)
  expect_match(src, "continue_after_host(ig$input %||% actual_input)", fixed = TRUE)
  expect_match(src, ".gate_note(session, .input_gate_user_note(ig))", fixed = TRUE)
  expect_match(src, "chat_append(\"chat\", \"Not sent", fixed = TRUE)   # ends the waiting state
})

# ---- the card never reaches the model ----------------------------------------
test_that("a tool card is neither in the request to the model nor in a compaction summary", {
  secret <- "CARDONLY-0007"
  req <- ellmer::ContentToolRequest(id = "call_1", name = "explore_adam", arguments = list(dataset = "ADSL"))
  res <- ellmer::ContentToolResult(value = "[data_shield] output withheld", request = req,
                                   extra = list(display = list(html = paste0("<td>", secret, "</td>"))))
  turns <- list(ellmer::Turn("user", list(ellmer::ContentText("count"))),
                ellmer::Turn("assistant", list(req)),
                ellmer::Turn("user", list(res)))
  expect_false(any(grepl(secret, vapply(seq_along(turns), function(i) .serialize_compact_turn(turns[[i]], i), ""),
                         fixed = TRUE)))
  body <- NULL
  chat <- ellmer::chat_openai_compatible(base_url = "http://127.0.0.1:9/v1", credentials = function() "x",
                                         model = "m", echo = "none")
  chat$set_turns(turns)
  httr2::with_mocked_responses(function(req) {
    d <- req$body$data
    body <<- if (is.raw(d)) rawToChar(d) else as.character(jsonlite::toJSON(d, auto_unbox = TRUE, null = "null"))
    httr2::response_json(body = list(id = "1", object = "chat.completion", created = 1L, model = "m",
      choices = list(list(index = 0L, finish_reason = "stop", message = list(role = "assistant", content = "ok")))))
  }, chat$chat("go on"))
  expect_true(grepl("output withheld", body, fixed = TRUE))
  expect_false(grepl(secret, body, fixed = TRUE))
})

test_that("shield_prompt() sets the gate's policy; a client setting still wins", {
  sh <- DataShield$new(strategies = list(shield_egress(), shield_prompt("ask")))
  sh$register_data(data.frame(SUBJID = subj), name = "ADSL", sensitivity = list(SUBJID = "identifier"))
  expect_identical(sh$prompt_on_fail(), "ask")
  expect_identical(.input_gate_guarded("S0007?", list(data_shield_engine = sh), can_ask = TRUE)$action, "block")
  expect_identical(.input_gate_guarded("S0007?", list(data_shield_engine = sh, data_shield_prompt_on_fail = "redact"))$action, "redact")
  expect_identical(DataShield$new(strategies = list(shield_egress()))$prompt_on_fail(), "redact")
  expect_error(shield_prompt("maybe"))
})

test_that("the gate's final decision is in the audit log (labels only)", {
  sh <- shield_with()
  gate("why is S0007 missing?", sh)
  a <- sh$audit()
  last <- a[nrow(a), ]
  expect_identical(c(last$strategy, last$action), c("prompt_gate", "block"))
  expect_match(last$reason, "subject identifiers in the message: ADSL.SUBJID (identifier)", fixed = TRUE)
  expect_false(any(grepl("S0007", a$reason, fixed = TRUE)))
  tab <- paste(c("A\t1\t2", "B\t3\t4", "C\t5\t6", "D\t7\t8", "E\t9\t1"), collapse = "\n")
  r <- gate(tab, sh)
  expect_identical(r$table, "5 lines with numbers")
  a <- sh$audit()
  expect_identical(a$action[nrow(a)], "ask")
  sh$record_gate("dont_send", "pasted table: 5 lines with numbers")
  expect_identical(sh$audit()$action[nrow(sh$audit())], "dont_send")
  src <- paste(deparse(body(server_chat)), collapse = "\n")
  expect_match(src, "shield$record_gate(", fixed = TRUE)
  expect_match(src, "\"dont_send\"", fixed = TRUE)
})

test_that("display = 'hide': a variant or shape match of an identifier hides the card too", {
  sh <- shield_with(display = "hide", column_access = NULL)
  exact <- sh$scan_egress(card_result("subject S0007"), list(tool_name = "t"))
  expect_length(exact@extra, 0L)
  for (v in c("subject BGBX0007", "subject BGB-X-9999")) {    # variant, unregistered shape
    out <- sh$scan_egress(card_result(v), list(tool_name = "t"))
    if (!identical(out@value, v)) {                           # when the shield acted on it
      expect_length(out@extra, 0L)
      expect_false(grepl("user sees the full result", out@value, fixed = TRUE))
    }
  }
})

test_that("hit labels are never named by the protected value", {
  sh <- shield_with()
  vm <- .data_shield_hit_labels(c("S0007", "S0008"), sh$.__enclos_env__$private$index)
  expect_null(names(vm))
})
