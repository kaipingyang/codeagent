#!/usr/bin/env Rscript
# inst/examples/test_web_tools.R
#
# Test script for WebFetch and WebSearch tools.
# Diagnoses common failure modes.
#
# Run from package root:
#   Rscript inst/examples/test_web_tools.R

devtools::load_all(quiet = TRUE)

.n_pass <- 0L; .n_fail <- 0L
ok <- function(cond, label) {
  if (isTRUE(cond)) {
    cat(sprintf("  \033[32mPASS\033[0m  %s\n", label)); .n_pass <<- .n_pass + 1L
  } else {
    cat(sprintf("  \033[31mFAIL\033[0m  %s\n", label)); .n_fail <<- .n_fail + 1L
  }
}
section <- function(t) cat(sprintf("\n\033[1m== %s ==\033[0m\n", t))

# Helper: extract value from ContentToolResult or character
.val <- function(x) {
  if (S7::S7_inherits(x, ellmer::ContentToolResult)) as.character(x@value)
  else as.character(x)
}

# ---------------------------------------------------------------------------
# A. WebFetch — fetch a known stable URL
# ---------------------------------------------------------------------------
section("A. WebFetch")

fetch_tool <- codeagent:::web_fetch_tool()

# Try multiple URLs — some may be blocked by network policy
test_urls <- list(
  list(url = "https://httpbin.org/get",         expect = "httpbin|url|origin"),
  list(url = "https://r-project.org/",          expect = "R|statistical|computing"),
  list(url = "https://cran.r-project.org/",     expect = "CRAN|package|R")
)
fetch_ok <- FALSE
for (u in test_urls) {
  result_fetch <- fetch_tool(u$url)
  val_fetch    <- .val(result_fetch)
  if (!startsWith(val_fetch, "[Error]") && nchar(val_fetch) > 100) {
    ok(TRUE,  sprintf("WebFetch: succeeded on %s", u$url))
    ok(grepl(u$expect, val_fetch, ignore.case = TRUE),
       sprintf("WebFetch: response contains expected content from %s", u$url))
    fetch_ok <- TRUE
    break
  }
  cat(sprintf("  [SKIP] %s unavailable (%d chars)\n", u$url, nchar(val_fetch)))
}
if (!fetch_ok) {
  ok(FALSE, "WebFetch: all test URLs failed — network policy may block external access")
  cat("  [WARN] This is a network issue, not a code issue.\n")
  cat("  [WARN] btw web_read_url (Section C) may have better network handling.\n")
}

# ---------------------------------------------------------------------------
# B. WebSearch — DuckDuckGo Instant Answer API (limited: entity queries only)
# ---------------------------------------------------------------------------
section("B. WebSearch (DuckDuckGo Instant Answer API)")

search_tool <- codeagent:::web_search_tool()

# The DDG Instant Answer API works best for named entities
result_entity <- search_tool("R programming language")
val_entity     <- .val(result_entity)
ok(!startsWith(val_entity, "[Error]"),         "WebSearch: API call succeeded (no HTTP error)")
cat(sprintf("  [INFO] Query: 'R programming language'\n"))
cat(sprintf("  [INFO] Response: %s\n", substr(val_entity, 1, 120)))

# Diagnose if results are empty (common for non-entity queries)
if (grepl("No results found", val_entity)) {
  cat("  [WARN] DDG Instant Answer returned empty RelatedTopics.\n")
  cat("  [WARN] This API is limited to entity lookups, not general search.\n")
  cat("  [WARN] Consider replacing with SerpAPI, Brave Search API, or btw_tool_web_read_url.\n")
} else {
  ok(nchar(val_entity) > 50,                   "WebSearch: results contain content")
}

# Test a direct entity query (should reliably return something)
result_wiki <- search_tool("Hadley Wickham")
val_wiki    <- .val(result_wiki)
cat(sprintf("  [INFO] Query: 'Hadley Wickham'\n"))
cat(sprintf("  [INFO] Response: %s\n", substr(val_wiki, 1, 120)))
if (grepl("No results found", val_wiki)) {
  cat("  [WARN] Even entity query returned empty — DDG API may be blocked or changed.\n")
}

# ---------------------------------------------------------------------------
# C. btw web_read_url (alternative to WebFetch)
# ---------------------------------------------------------------------------
section("C. btw web_read_url (via register_r_tools)")

if (requireNamespace("btw", quietly = TRUE)) {
  btw_web <- btw::btw_tools("web_read_url")
  if (length(btw_web) > 0L) {
    result_btw <- tryCatch(
      btw_web[[1L]](url = "https://httpbin.org/get"),
      error = function(e) paste0("[Error] ", conditionMessage(e))
    )
    val_btw <- if (S7::S7_inherits(result_btw, ellmer::ContentToolResult))
      as.character(result_btw@value)
    else as.character(result_btw)
    ok(!startsWith(val_btw, "[Error]"),        "btw web_read_url: no error")
    ok(nchar(val_btw) > 50,                    "btw web_read_url: has content")
    cat(sprintf("  [INFO] btw web response: %s\n", substr(val_btw, 1, 80)))
  } else {
    cat("  [SKIP] btw web_read_url not available\n")
  }
} else {
  cat("  [SKIP] btw not installed\n")
}

# ---------------------------------------------------------------------------
# D. Diagnosis: why WebSearch fails for general queries
# ---------------------------------------------------------------------------
section("D. WebSearch diagnosis")

cat("  Implementation: DDG HTML scraping (primary) + DDG Instant Answer (fallback)\n")
cat("  No API key required. General queries and entity queries both supported.\n\n")

# Verify general query works with HTML scraping
test_general <- search_tool("how to do linear regression in R")
val_general  <- .val(test_general)
if (grepl("No results found", val_general)) {
  cat("  [WARN] DDG HTML scraping returned no results — may be blocked or changed.\n")
  ok(FALSE, "WebSearch: general query returned results via DDG HTML scraping")
} else {
  ok(TRUE,  "WebSearch: general query works (DDG HTML scraping)")
  ok(nchar(val_general) > 50, "WebSearch: general query result has content")
  cat(sprintf("  [INFO] First result: %s\n", substr(val_general, 1, 80)))
}

# ---------------------------------------------------------------------------
cat(sprintf(
  "\n\033[1m=== Results: %d passed  %d failed ===\033[0m\n",
  .n_pass, .n_fail
))
