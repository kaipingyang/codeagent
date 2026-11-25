test_that(".interaction_bar_ui returns NULL when nothing is pending", {
  expect_null(codeagent:::.interaction_bar_ui(NULL))
  expect_null(codeagent:::.interaction_bar_ui(list(type = "other")))
})

test_that(".interaction_bar_ui builds an Allow/Deny bar for approvals", {
  pending <- list(
    type    = "approval",
    payload = list(tool_name = "Bash", tool_input = list(command = "rm -rf /tmp/x"))
  )
  ui   <- codeagent:::.interaction_bar_ui(pending)
  html <- as.character(ui)
  expect_true(grepl("ca_tool_allow", html))
  expect_true(grepl("ca_tool_deny", html))
  expect_true(grepl("Bash", html))
  expect_true(grepl("rm -rf", html))   # command shown in the description
})


test_that("approval card: full command, DSH labels, Reject / Always allow / Allow once", {
  long <- paste(rep("x", 200), collapse = "")
  html <- as.character(codeagent:::.interaction_bar_ui(list(
    type = "approval", payload = list(tool_name = "Bash", tool_input = list(command = long)))))
  expect_true(grepl(long, html, fixed = TRUE))                      # shown in full
  expect_match(html, "Waiting for approval", fixed = TRUE)
  expect_match(html, 'data-ca-keys="approval"', fixed = TRUE)
  pos <- vapply(c("ca_tool_deny", "ca_tool_allow_always", '"ca_tool_allow"'),
                function(s) regexpr(s, html, fixed = TRUE)[[1]], 1)
  expect_true(all(diff(pos) > 0))
  expect_match(html, ">Reject<", fixed = TRUE)
  expect_match(html, ">Allow once<", fixed = TRUE)
  huge <- paste(rep("y", 5000), collapse = "")
  html2 <- as.character(codeagent:::.interaction_bar_ui(list(
    type = "approval", payload = list(tool_name = "Bash", tool_input = list(command = huge)))))
  expect_false(grepl(huge, html2, fixed = TRUE))                    # capped
})

test_that("a single question becomes a one-page question card", {
  html <- as.character(codeagent:::.interaction_bar_ui(list(
    type = "question", payload = list(question = "Pick one", choices = c("a", "b (Recommended)")))))
  expect_match(html, "ca-q-card", fixed = TRUE)
  expect_match(html, "Pick one", fixed = TRUE)
  expect_match(html, 'data-label="b (Recommended)"', fixed = TRUE)
  expect_match(html, 'class="ca-q-badge">Recommended<', fixed = TRUE)
  expect_match(html, "1 / 1", fixed = TRUE)
  expect_match(html, ">Submit<", fixed = TRUE)
  expect_match(html, ">Skip<", fixed = TRUE)
  expect_false(grepl("is-selected", html))   # the recommended one is not the first
})

test_that("a choiceless question gets a block text field", {
  html <- as.character(codeagent:::.interaction_bar_ui(list(
    type = "question", payload = list(question = "Your name?", choices = character(0)))))
  expect_match(html, "ca-q-block", fixed = TRUE)
  expect_false(grepl("ca-q-option", html, fixed = TRUE))
})


test_that(".interaction_cancel_value uses safe defaults", {
  expect_false(codeagent:::.interaction_cancel_value(list(type = "approval")))
  expect_identical(codeagent:::.interaction_cancel_value(list(type = "question")), "")
  expect_identical(codeagent:::.interaction_cancel_value(list(type = "egress")), "redact")
  expect_null(codeagent:::.interaction_cancel_value(NULL))
})

test_that(".resolve_pending resolves the stored promise once and clears the slot", {
  resolved <- new.env(parent = emptyenv())
  resolved$value <- NULL
  resolved$calls <- 0L
  st <- new.env(parent = emptyenv())
  st$pending_interaction <- list(
    type    = "approval",
    resolve = function(v) { resolved$value <- v; resolved$calls <- resolved$calls + 1L }
  )

  ok <- codeagent:::.resolve_pending(st, TRUE)
  expect_true(ok)
  expect_true(resolved$value)
  expect_null(st$pending_interaction)          # slot cleared
  expect_equal(resolved$calls, 1L)

  # Second call is a no-op (nothing pending).
  expect_false(codeagent:::.resolve_pending(st, FALSE))
  expect_equal(resolved$calls, 1L)
})


test_that(".interaction_bar_ui builds safe egress choices without raw content", {
  pending <- list(type="egress",payload=list(
    tool_name="DumpData",strategy="row_cap",reason="bulk tabular output",
    match_count=51L,allow_raw_approval=FALSE))
  html <- as.character(codeagent:::.interaction_bar_ui(pending))
  expect_true(grepl("ca_egress_redact",html))
  expect_true(grepl("ca_egress_block",html))
  expect_false(grepl("ca_egress_raw",html))
  expect_true(grepl("DumpData",html))
})

test_that("egress raw-once button requires explicit opt-in", {
  pending <- list(type="egress",payload=list(
    tool_name="Trusted",strategy="value_match",reason="protected value match",
    match_count=1L,allow_raw_approval=TRUE))
  html <- as.character(codeagent:::.interaction_bar_ui(pending))
  expect_true(grepl("ca_egress_raw",html))
  expect_true(grepl("ALLOW RAW ONCE",html))
})

test_that("answer records are short, escaped, and say what was answered", {
  qs <- list(list(question = "Format?", options = list()), list(question = "Note?", options = list()))
  expect_identical(.answer_record_text(qs, list("Table", character())),
                   "\U0001f4dd Answered: Format? → Table; Note? → Skipped")
  expect_match(.answer_record_text(qs, list("<b>x</b>", "a\nb")), "&lt;b&gt;x&lt;/b&gt;", fixed = TRUE)
  expect_false(grepl("\n", .answer_record_text(qs, list("<b>x</b>", "a\nb")), fixed = TRUE))
  expect_match(.answer_record_text(qs, list()), "dismissed", fixed = TRUE)
  expect_identical(.form_record_text("Grouping", TRUE), "\U0001f4dd Submitted: Grouping.")
  expect_match(.form_record_text(NULL, FALSE), "cancelled", fixed = TRUE)
})

test_that("the waiting count sits above the card", {
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL, interaction_queue = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    st <- session$userData$state
    item <- list(type = "approval", payload = list(tool_name = "Bash", tool_input = list()),
                 resolve = function(v) NULL)
    st$pending_interaction <- item
    st$interaction_queue <- list(item)
    session$flushReact()
    html <- as.character(output$ca_interaction_ui$html)
    expect_lt(regexpr("more request", html)[[1]], regexpr("ca-interaction--approval", html)[[1]])
  })
})

test_that("a floating card is opaque and placed once its content is in the page", {
  css <- paste(readLines(system.file("www", "styles.css", package = "codeagent")), collapse = "\n")
  expect_match(css, ":where(#ca_interaction_ui.ca-ia-overlay) > .ca-interaction {", fixed = TRUE)
  expect_match(css, "#ca_interaction_ui.ca-ia-overlay::after", fixed = TRUE)
  js <- paste(readLines(system.file("www", "interaction.js", package = "codeagent")), collapse = "\n")
  expect_match(js, "MutationObserver(function () { init(document); placeAll(); })", fixed = TRUE)
})

test_that("interaction cards are resizable: handle, 60% default cap, buttons stay in view", {
  js <- paste(readLines(system.file("www", "interaction.js", package = "codeagent")), collapse = "\n")
  css <- paste(readLines(system.file("www", "styles.css", package = "codeagent")), collapse = "\n")
  dsh <- paste(readLines(system.file("themes", "dsh.scss", package = "codeagent")), collapse = "\n")
  expect_match(js, "l.height * 0.6", fixed = TRUE)
  expect_match(js, 'h.className = "ca-ia-handle"', fixed = TRUE)
  expect_match(js, '"codeagent.ia-height"', fixed = TRUE)
  expect_match(js, "function placeInline(", fixed = TRUE)
  expect_match(css, "max-height: var(--ca-ia-max-height, 60%)", fixed = TRUE)
  expect_match(css, "height: var(--ca-ia-height, auto)", fixed = TRUE)
  expect_match(css, ".ca-interaction--scroll > .ca-interaction-actions {\n  position: sticky;", fixed = TRUE)
  expect_match(dsh, "body .ca-interaction--scroll > .ca-interaction-body {\n  flex: 1 1 auto;\n  min-height: 0;\n  overflow-y: auto;", fixed = TRUE)
})
