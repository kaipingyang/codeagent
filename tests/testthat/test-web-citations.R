
test_that("citation mode API uses the frozen enum and fails closed for private web", {
  expect_identical(eval(formals(codeagent_app)$web_citations),
                   c("off", "shiny_aside"))
  expect_identical(formals(codeagent_app)$web_allow_private, FALSE)
  expect_false(.web_citations_enabled("off"))
  expect_true(.web_citations_enabled("shiny_aside"))
  expect_true(.web_citations_enabled(TRUE))
  expect_false(.web_citations_enabled(FALSE))
  expect_error(codeagent_app(web_allow_private = TRUE),
               "Private-network web fetching")
})
# tests/testthat/test-web-citations.R

library(ellmer)

.citation_fake_gen <- function(chunks) {
  force(chunks)
  coro::async_generator(function() {
    for (chunk in chunks) coro::yield(chunk)
  })
}

.citation_fake_chat <- function(chunks) {
  list(
    stream_async = function(...) .citation_fake_gen(chunks)(),
    get_tokens = function(...) data.frame(
      input = 1L, output = 1L, cached_input = 0L, cost = 0),
    get_cost = function(...) 0,
    get_turns = function(...) list(),
    on_tool_request = function(...) NULL,
    on_tool_result = function(...) NULL)
}

.citation_pump <- function(p, timeout_s = 5) {
  done <- FALSE; value <- NULL
  promises::then(p, function(x) { value <<- x; done <<- TRUE })
  deadline <- Sys.time() + timeout_s
  while (!done && Sys.time() < deadline) later::run_now(timeoutSecs = 0.05)
  value
}

test_that("web source contract sanitizes fields and rejects unsafe URLs", {
  src <- .new_web_source(
    url = "https://example.com/path", title = paste0("<b>Title</b>", intToUtf8(1L)),
    cited_quote = "Quote<script>alert(1)</script>", tool = "WebSearch")
  expect_match(src$id, "^src_[a-z0-9]{8}$")
  expect_identical(src$title, "Title")
  expect_false(grepl("script|<|>", src$cited_quote, ignore.case = TRUE))
  expect_error(.new_web_source("file:///etc/passwd", "x", "y", "WebFetch"),
               "http|https")
  expect_error(.new_web_source("https://user:pass@example.com", "x", "y", "WebFetch"),
               "credentials|userinfo")
})

test_that("citation registry is current-turn, deduplicated, and rejects conflicts", {
  reg <- .new_citation_registry()
  a <- .new_web_source("https://example.com/a", "A", "qa", "WebSearch",
                       id = "src_aaaaaaaa")
  duplicate <- a; duplicate$title <- "A revised"
  conflict <- .new_web_source("https://example.com/b", "B", "qb", "WebFetch",
                              id = "src_aaaaaaaa")
  .citation_registry_add(reg, list(a, duplicate, conflict))
  expect_null(.citation_registry_get(reg, "src_aaaaaaaa"))

  .citation_registry_clear(reg)
  .citation_registry_add(reg, list(a))
  expect_identical(.citation_registry_get(reg, "src_aaaaaaaa")$url,
                   "https://example.com/a")
  .citation_registry_clear(reg)
  expect_null(.citation_registry_get(reg, "src_aaaaaaaa"))
})

test_that("marker bridge rebuilds fixed shiny-aside and escapes model markup", {
  reg <- .new_citation_registry()
  src <- .new_web_source(
    "https://example.com/a?x=1&y=2", 'Title"><img src=x onerror=1>',
    'Quoted <script>bad()</script>', "WebSearch", id = "src_aaaaaaaa")
  .citation_registry_add(reg, list(src))

  text <- paste0(
    "Claim [[cite:src_aaaaaaaa|visible <b>claim</b>]] ",
    "[[cite:src_missing|unknown]] ",
    "<shiny-aside data-citation url=\"https://evil.invalid\">raw</shiny-aside>")
  out <- .render_citation_markers(text, reg, settings = list(), chat = NULL)

  expect_match(out, "<shiny-aside data-citation ", fixed = TRUE)
  expect_match(out, 'url="https://example.com/a?x=1&amp;y=2"', fixed = TRUE)
  expect_match(out, 'grounded-span="visible claim"', fixed = TRUE)
  expect_match(out, 'display="compact"', fixed = TRUE)
  expect_false(grepl("onerror|<img", out, ignore.case = TRUE))
  expect_false(grepl("<shiny-aside[^>]+evil\\.invalid", out, ignore.case = TRUE))
  expect_match(out, "[[cite:src_missing|unknown]]", fixed = TRUE)
  expect_match(out, "&lt;shiny-aside", fixed = TRUE)
  expect_equal(lengths(regmatches(out, gregexpr("<shiny-aside", out, fixed = TRUE))), 1L)
})

test_that("marker fields pass through Data Shield before markup", {
  shield <- DataShield$new(strategies = list(shield_regex(on_fail = "redact")))
  reg <- .new_citation_registry()
  src <- .new_web_source("https://example.com", "Public title",
                         "Contact person@example.com", "WebFetch",
                         id = "src_aaaaaaaa")
  .citation_registry_add(reg, list(src))
  out <- .render_citation_markers(
    "[[cite:src_aaaaaaaa|email person@example.com]]", reg,
    settings = list(data_shield_engine = shield), chat = NULL)
  expect_false(grepl("person@example.com", out, fixed = TRUE))
  expect_match(out, "shiny-aside", fixed = TRUE)
})

test_that("native provider citations rebuild through the fixed aside allowlist", {
  registry <- .new_citation_registry()
  citations <- list(
    ContentCitation(
      source = WebSource("https://example.com/a", "Provider A"),
      grounded_span = "supported claim", cited_quote = "evidence A"),
    ContentCitation(
      source = WebSource("https://example.com/b", "Provider B"),
      grounded_span = "supported claim", cited_quote = "evidence B")
  )

  marked <- .inject_native_citation_markers(
    "A supported claim appears here.", citations, registry)
  rendered <- .render_citation_markers(marked, registry, list(), NULL)

  expect_equal(lengths(regmatches(rendered, gregexpr("supported claim", rendered,
                                                     fixed = TRUE))), 3L)
  expect_equal(lengths(regmatches(rendered, gregexpr("<shiny-aside", rendered,
                                                     fixed = TRUE))), 2L)
  expect_match(rendered, 'grounded-span="supported claim"', fixed = TRUE)
  expect_match(rendered, 'url="https://example.com/a"', fixed = TRUE)
  expect_match(rendered, 'url="https://example.com/b"', fixed = TRUE)
  expect_false(grepl("cite-ref", rendered, fixed = TRUE))
})

test_that("native provider citations reject unsafe sources and escape fallback markup", {
  registry <- .new_citation_registry()
  citations <- list(ContentCitation(
    source = WebSource("http://127.0.0.1/private", "Private"),
    grounded_span = "claim", cited_quote = "private"))
  marked <- .inject_native_citation_markers(
    "claim <shiny-aside url=\"https://evil.invalid\">raw</shiny-aside>",
    citations, registry)
  rendered <- .render_citation_markers(marked, registry, list(), NULL)
  expect_false(grepl("<shiny-aside", rendered, fixed = TRUE))
  expect_match(rendered, "&lt;shiny-aside", fixed = TRUE)
})

test_that("native citation fields pass through Data Shield output gates", {
  shield <- DataShield$new(strategies = list(shield_regex(on_fail = "redact")))
  registry <- .new_citation_registry()
  citation <- ContentCitation(
    source = WebSource(
      "https://example.com/native?contact=url.person@example.com",
      "title.person@example.com"),
    grounded_span = "supported claim",
    cited_quote = "quote.person@example.com")
  marked <- .inject_native_citation_markers(
    "A supported claim appears here.", list(citation), registry)
  rendered <- .render_citation_markers(
    marked, registry, list(data_shield_engine = shield), NULL)

  expect_false(grepl("person@example.com", rendered, fixed = TRUE))
  expect_match(rendered, "<shiny-aside data-citation", fixed = TRUE)
})

test_that("native citations without a matched span use a message-wide aside", {
  registry <- .new_citation_registry()
  citation <- ContentCitation(
    source = WebSource("https://example.com/message", "Message source"),
    grounded_span = "not present", cited_quote = "message evidence")
  rendered <- .render_citation_markers(
    .inject_native_citation_markers("Whole message.", list(citation), registry),
    registry, list(), NULL)

  expect_match(rendered, "Whole message.", fixed = TRUE)
  expect_match(rendered, "<shiny-aside data-citation", fixed = TRUE)
  expect_false(grepl("grounded-span=", rendered, fixed = TRUE))
})

test_that("native citation refs are scoped to the current-turn registry", {
  registry <- .new_citation_registry()
  citation <- ContentCitation(
    source = WebSource("https://example.com/old", "Old source"),
    grounded_span = "old claim", cited_quote = "old evidence")
  marked <- .inject_native_citation_markers(
    "An old claim.", list(citation), registry)
  .citation_registry_clear(registry)
  rendered <- .render_citation_markers(marked, registry, list(), NULL)

  expect_false(grepl("<shiny-aside", rendered, fixed = TRUE))
  expect_match(rendered, "[[cite-ref:", fixed = TRUE)
})

test_that("native citation replay ignores provider-generated raw aside markup", {
  citation <- ContentCitation(
    source = WebSource("https://example.com/replay-native", "Replay native"),
    grounded_span = "restored fact", cited_quote = "restored evidence")
  turn <- AssistantTurn(
    contents = list(ContentText("A restored fact."), citation),
    finish_reason = "stop")
  registry <- .new_citation_registry()
  rendered <- .finalize_replay_assistant_text(
    "<shiny-aside url=\"https://evil.invalid\">evil</shiny-aside>",
    registry, settings = list(web_citations = "shiny_aside"), turn = turn)

  expect_match(rendered, "A restored fact", fixed = TRUE)
  expect_match(rendered, "https://example.com/replay-native", fixed = TRUE)
  expect_equal(lengths(regmatches(
    rendered, gregexpr("<shiny-aside", rendered, fixed = TRUE))), 1L)
  expect_false(grepl("evil.invalid", rendered, fixed = TRUE))
  expect_true(inherits(turn@contents[[2L]], "ellmer::ContentCitation"))
})

test_that("citation stream rebuilds ellmer ContentCitation after buffering", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")
  citation <- ContentCitation(
    source = WebSource("https://example.com/native", "Native source"),
    grounded_span = "provider fact", cited_quote = "provider evidence")
  chunks <- list(ContentText("A provider fact."), citation)
  chat <- .citation_fake_chat(chunks)
  chat$last_turn <- function(...) AssistantTurn(
    contents = list(ContentText("A provider fact."), citation),
    finish_reason = "stop")
  client <- structure(list(
    chat = chat,
    settings = list(web_citations = TRUE, cwd = getwd(), model_limit = 1000L,
                    model = "fake")), class = "CodeagentClient")
  deltas <- character()
  result <- .citation_pump(codeagent_stream_async(
    client, "test", on_delta = function(x) deltas <<- c(deltas, x)))

  expect_length(deltas, 1L)
  expect_match(result$text, "<shiny-aside data-citation", fixed = TRUE)
  expect_match(result$text, "https://example.com/native", fixed = TRUE)
})

test_that("tool adapter preserves private source metadata", {
  src <- .new_web_source("https://example.com", "Example", "Quote", "WebFetch",
                         id = "src_aaaaaaaa")
  raw <- ContentToolResult(
    value = "body",
    extra = list(codeagent = list(sources = list(src)),
                 display = list(markdown = "body")))
  adapted <- .adapt_tool_result(raw)
  expect_identical(adapted@extra$codeagent$sources[[1L]]$id, "src_aaaaaaaa")
  expect_false(is.null(adapted@extra$codeagent$artifact))
})

test_that("DDG parser returns structured records", {
  html <- paste(readLines(test_path("fixtures", "web", "ddg-results.html"),
                          warn = FALSE), collapse = "\n")
  records <- .ddg_html_parse_records(html, 5L)
  expect_length(records, 1L)
  expect_identical(records[[1L]]$title, "Example Alpha")
  expect_identical(records[[1L]]$url, "https://example.com/alpha")
  expect_identical(records[[1L]]$snippet, "A deterministic public snippet.")
})

test_that("DDG Instant fixture produces structured citation sources offline", {
  body <- paste(readLines(test_path("fixtures", "web", "ddg-instant.json"),
                          warn = FALSE), collapse = "\n")
  testthat::local_mocked_bindings(
    .safe_web_request = function(...) list(
      status = 200L, body = body,
      url = "https://api.duckduckgo.com/", content_type = "application/json")
  )
  result <- .search_ddg_instant("fixture", 5L, citations = TRUE)
  expect_length(result@extra$codeagent$sources, 2L)
  expect_match(result@value, "<web-sources ", fixed = TRUE)
  expect_identical(result@extra$codeagent$sources[[1L]]$url,
                   "https://example.com/topic")
})

test_that("untrusted web fixtures cannot retain executable markup", {
  xss <- paste(readLines(test_path("fixtures", "web", "xss.html"),
                         warn = FALSE), collapse = "\n")
  injection <- paste(readLines(test_path("fixtures", "web", "prompt-injection.txt"),
                               warn = FALSE), collapse = "\n")
  clean <- .sanitize_web_source_text(paste(xss, injection), 5000L)
  expect_false(grepl("<script", clean, fixed = TRUE))
  expect_false(grepl("<shiny-aside", clean, fixed = TRUE))
  expect_match(clean, "&lt;shiny-aside", fixed = TRUE)
})

test_that("citation title, quote, and URL fields are independently output-gated", {
  shield <- structure(new.env(parent = emptyenv()), class = "DataShield")
  shield$scan_response <- function(text, ...) {
    if (grepl("SECRET", text, fixed = TRUE)) {
      list(action = "redact", text = "[redacted]", matches = 1L)
    } else {
      list(action = "pass", text = text, matches = 0L)
    }
  }
  settings <- list(data_shield_engine = shield)

  cases <- list(
    .new_web_source("https://example.com/a", "SECRET title", "safe", "WebFetch"),
    .new_web_source("https://example.com/b", "safe", "SECRET quote", "WebFetch"),
    .new_web_source("https://example.com/SECRET", "safe", "safe", "WebFetch")
  )
  for (source in cases) {
    registry <- .new_citation_registry()
    .citation_registry_add(registry, source)
    marker <- sprintf("[[cite:%s|safe claim]]", source$id)
    rendered <- .render_citation_markers(marker, registry, settings, chat = NULL)
    expect_false(grepl("<shiny-aside", rendered, fixed = TRUE))
    expect_false(grepl("SECRET", rendered, fixed = TRUE))
    expect_match(rendered, "safe claim", fixed = TRUE)
  }
})

test_that("URL policy rejects non-global and credentialed targets", {
  bad <- c(
    "http://127.0.0.1/x", "http://10.0.0.1", "http://169.254.169.254/latest",
    "http://192.0.2.1", "http://[::1]/", "http://[fc00::1]/", "http://[dead::1]/",
    "file:///etc/passwd", "//example.com/path",
    "https://user:pass@example.com/")
  for (url in bad) expect_error(.authorize_web_url(url), info = url)
  expect_identical(.authorize_web_url("https://93.184.216.34/path")$host,
                   "93.184.216.34")
})

test_that("safe fetch pins a validated public IP and revalidates redirects", {
  seen <- list()
  testthat::local_mocked_bindings(
    .resolve_web_host = function(host) {
      if (identical(host, "example.com")) "93.184.216.34" else "127.0.0.1"
    },
    .perform_pinned_web_request = function(url, host, port, ip, ...) {
      seen[[length(seen) + 1L]] <<- list(url = url, host = host, ip = ip)
      list(status = 200L, headers = list(), body = "ok",
           content_type = "text/plain", url = url)
    },
    .package = "codeagent")
  out <- .safe_web_request("https://example.com/a")
  expect_identical(out$body, "ok")
  expect_identical(seen[[1L]]$ip, "93.184.216.34")

  testthat::local_mocked_bindings(
    .resolve_web_host = function(host) "93.184.216.34",
    .perform_pinned_web_request = function(url, ...) list(
      status = 302L, headers = list(location = "http://127.0.0.1/private"),
      body = "", content_type = "text/plain", url = url),
    .package = "codeagent")
  expect_error(.safe_web_request("https://example.com/start"), "private|loopback|global")
})

test_that("mixed public/private DNS answers fail closed before fetch", {
  called <- FALSE
  testthat::local_mocked_bindings(
    .resolve_web_host = function(host) c("93.184.216.34", "127.0.0.1"),
    .perform_pinned_web_request = function(...) { called <<- TRUE; stop("no") },
    .package = "codeagent")
  expect_error(.safe_web_request("https://example.com"), "non-global|private")
  expect_false(called)
})

test_that("cross-origin redirects drop caller headers and keep per-hop DNS pins", {
  seen <- list()
  testthat::local_mocked_bindings(
    .resolve_web_host = function(host) {
      if (identical(host, "example.com")) "93.184.216.34" else "93.184.216.35"
    },
    .perform_pinned_web_request = function(url, host, port, ip, timeout,
                                           headers = list()) {
      seen[[length(seen) + 1L]] <<- list(
        host = host, ip = ip, headers = headers)
      if (identical(host, "example.com")) {
        return(list(
          status = 302L,
          headers = list(location = "https://example.org/final"),
          body = "", content_type = "text/plain", url = url))
      }
      list(status = 200L, headers = list(), body = "ok",
           content_type = "text/plain", url = url)
    },
    .package = "codeagent")

  out <- .safe_web_request(
    "https://example.com/start",
    headers = list(Authorization = "Bearer fixture", `X-Fixture` = "present"))

  expect_identical(out$body, "ok")
  expect_identical(vapply(seen, `[[`, character(1L), "host"),
                   c("example.com", "example.org"))
  expect_identical(vapply(seen, `[[`, character(1L), "ip"),
                   c("93.184.216.34", "93.184.216.35"))
  expect_named(seen[[1L]]$headers, c("Authorization", "X-Fixture"))
  expect_identical(seen[[2L]]$headers, list())
})


test_that("citation prompt and app opt-in are explicit", {
  expect_identical(.prompt_web_citations(list(web_citations = FALSE)), "")
  prompt <- .prompt_web_citations(list(web_citations = TRUE))
  expect_match(prompt, "[[cite:SOURCE_ID|visible claim]]", fixed = TRUE)
  expect_match(prompt, "Never write <shiny-aside>", fixed = TRUE)
  expect_false(isTRUE(formals(codeagent_app)$web_citations))
})

test_that("WebFetch retains sources and only adds marker protocol when enabled", {
  response <- list(status = 200L, headers = list(), body = "<title>Example</title><p>Useful body</p>",
                   content_type = "text/html", url = "https://example.com/a")
  testthat::local_mocked_bindings(
    .safe_web_request = function(...) response,
    .package = "codeagent")

  off <- web_fetch_tool(citations = FALSE)("https://example.com/a")
  on <- web_fetch_tool(citations = TRUE)("https://example.com/a")
  expect_length(off@extra$codeagent$sources, 1L)
  expect_false(grepl("<web-sources", off@value, fixed = TRUE))
  expect_match(on@value, "<web-sources", fixed = TRUE)
  expect_match(on@value, "[[cite:SOURCE_ID|visible claim]]", fixed = TRUE)
})

test_that("citation stream buffers and emits only rebuilt current-turn markup", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")
  src <- .new_web_source("https://example.com/a", "Example", "Quoted", "WebSearch",
                         id = "src_aaaaaaaa")
  tool_result <- ContentToolResult(
    value = "source", extra = list(codeagent = list(sources = list(src))))
  chunks <- list(tool_result, ContentText("Fact [[cite:src_aaaaaaaa|supported fact]]"))
  chat <- .citation_fake_chat(chunks)
  chat$last_turn <- function(...) AssistantTurn(
    contents = list(ContentText("Fact [[cite:src_aaaaaaaa|supported fact]]")),
    finish_reason = "stop")
  client <- structure(list(
    chat = chat,
    settings = list(web_citations = TRUE, cwd = getwd(), model_limit = 1000L,
                    model = "fake")), class = "CodeagentClient")
  deltas <- character()
  result <- .citation_pump(codeagent_stream_async(
    client, "test", on_delta = function(x) deltas <<- c(deltas, x)))

  expect_length(deltas, 1L)
  expect_match(result$text, "<shiny-aside data-citation", fixed = TRUE)
  expect_false(grepl("[[cite:", result$text, fixed = TRUE))
  expect_false(grepl("evil.invalid", result$text, fixed = TRUE))
})

test_that("lossless session codec preserves source records", {
  src <- .new_web_source("https://example.com/a", "Example", "Quote", "WebFetch",
                         id = "src_aaaaaaaa")
  tool <- ellmer::tool(function(url) url, name = "WebFetch",
                       description = "fixture",
                       arguments = list(url = ellmer::type_string()))
  request <- ContentToolRequest(id = "req1", name = "WebFetch",
                                arguments = list(url = src$url), tool = tool)
  result <- ContentToolResult(
    value = "source", request = request,
    extra = list(codeagent = list(sources = list(src))))
  chat <- chat_anthropic(model = "test")
  chat$set_turns(list(Turn("user", contents = list(result))))
  encoded <- .session_state_encode(chat)
  decoded <- .session_state_decode(encoded, tools = list(WebFetch = tool))
  restored <- decoded[[1L]]@contents[[1L]]@extra$codeagent$sources[[1L]]
  expect_identical(restored$id, "src_aaaaaaaa")
  expect_identical(restored$url, "https://example.com/a")
})

test_that("last-round registry excludes prior-turn sources", {
  old <- .new_web_source("https://example.com/old", "Old", "Old", "WebSearch",
                         id = "src_aaaaaaaa")
  current <- .new_web_source("https://example.com/new", "New", "New", "WebSearch",
                             id = "src_bbbbbbbb")
  old_result <- ContentToolResult(
    value = "old", extra = list(codeagent = list(sources = list(old))))
  current_result <- ContentToolResult(
    value = "new", extra = list(codeagent = list(sources = list(current))))
  chat <- chat_anthropic(model = "test")
  chat$set_turns(list(
    Turn("user", "first"), Turn("user", contents = list(old_result)),
    Turn("assistant", "done"), Turn("user", "second"),
    Turn("user", contents = list(current_result)), Turn("assistant", "answer")))
  reg <- .citation_registry_from_last_round(chat)
  expect_null(.citation_registry_get(reg, "src_aaaaaaaa"))
  expect_identical(.citation_registry_get(reg, "src_bbbbbbbb")$title, "New")
})


test_that("session presentation stores rebuilt text while chat-state stays lossless", {
  dir <- tempfile("citation-session-"); dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  home <- file.path(dir, "home"); dir.create(home)
  withr::local_envvar(CODEAGENT_HOME = home)
  withr::local_options(codeagent._migrated = TRUE)
  chat <- chat_anthropic(model = "test")
  chat$set_turns(list(
    Turn("user", "question"),
    AssistantTurn(contents = list(ContentText("raw [[cite:src_aaaaaaaa|claim]]")),
                  finish_reason = "stop")))
  safe <- "claim<shiny-aside data-citation url=\"https://example.com\" grounded-span=\"claim\" cited-quote=\"quote\"><a href=\"https://example.com\">Example</a></shiny-aside>"
  save_session(chat, cwd = dir, session_id = "citation",
               assistant_text_override = safe)
  lines <- jsonlite::stream_in(
    file(file.path(.get_project_session_dir(dir), "citation.jsonl")),
    verbose = FALSE)
  assistant <- lines[lines$type == "assistant", , drop = FALSE]
  expect_identical(assistant$message$content[[1L]], safe)
  restored <- chat_anthropic(model = "test")
  restore_session_into_chat(restored, "citation", cwd = dir)
  expect_match(restored$last_turn()@text, "[[cite:src_aaaaaaaa|claim]]", fixed = TRUE)
})


test_that("citation replay applies the full output gate before browser text", {
  source <- .new_web_source(
    "https://example.com/replay", "Replay source", "Public quote", "WebFetch",
    id = "src_replay01")
  registry <- .new_citation_registry()
  .citation_registry_add(registry, list(source))
  sentinel <- "REPLAYSECRET123"
  marker <- paste0(
    "restored [[cite:src_replay01|protected ", sentinel, "]] response")

  make_replay_shield <- function() {
    shield <- DataShield$new(strategies = list(
      shield_egress(max_rows = 0L), shield_regex()))
    shield$register_data(data.frame(
      id = c(sentinel, sprintf("REPLAYSECRET%03d", 1:20))),
      name = "replay")
    shield
  }
  redact_shield <- make_replay_shield()
  redact <- .finalize_replay_assistant_text(
    marker, registry,
    settings = list(
      web_citations = "shiny_aside",
      data_shield_engine = redact_shield,
      data_shield_output_scanners = "value_match",
      data_shield_response_on_fail = "redact"))
  expect_false(grepl(sentinel, redact, fixed = TRUE))
  expect_match(redact, "[REDACTED]", fixed = TRUE)
  expect_match(redact, "<shiny-aside", fixed = TRUE)

  block_shield <- make_replay_shield()
  blocked <- .finalize_replay_assistant_text(
    marker, registry,
    settings = list(
      web_citations = "shiny_aside",
      data_shield_engine = block_shield,
      data_shield_output_scanners = "value_match",
      data_shield_response_on_fail = "block"))
  expect_false(grepl(sentinel, blocked, fixed = TRUE))
  expect_false(grepl("<shiny-aside", blocked, fixed = TRUE))
  expect_match(blocked, "block", ignore.case = TRUE)
})
