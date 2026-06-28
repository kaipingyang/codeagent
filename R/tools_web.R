#' @title Web Tools
#' @description WebFetch and WebSearch tools for codeagent.
#'
#' WebSearch backend priority:
#'   1. Brave Search API (BRAVE_API_KEY set) — real search results
#'   2. DuckDuckGo Instant Answer API (no key) — entity queries only
#'
#' @name tools_web
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# WebFetch tool
# ---------------------------------------------------------------------------

#' Create the WebFetch tool
#'
#' Fetches a URL and returns its content as plain text (HTML stripped).
#'
#' @return An `ellmer::tool()` object.
#' @export
web_fetch_tool <- function() {
  ellmer::tool(
    fun = function(url, prompt = NULL) {
      tryCatch({
        resp <- httr2::request(url) |>
          httr2::req_headers(
            "User-Agent" = "codeagent/0.1 (R; https://github.com/kaipingyang/codeagent)"
          ) |>
          httr2::req_timeout(30) |>
          httr2::req_error(is_error = function(r) FALSE) |>
          httr2::req_perform()

        status <- httr2::resp_status(resp)
        if (status >= 400L) {
          msg <- paste0("[WebFetch] HTTP ", status, " for ", url)
          return(ellmer::ContentToolResult(
            value = msg,
            extra = list(display = list(
              title    = htmltools::HTML(sprintf(
                "WebFetch <code>%s</code> — HTTP %d",
                htmltools::htmlEscape(.url_host(url)), status
              )),
              markdown = msg
            ))
          ))
        }

        content_type <- httr2::resp_content_type(resp)
        body_raw     <- httr2::resp_body_string(resp)

        text <- if (grepl("html", content_type, ignore.case = TRUE)) {
          .strip_html(body_raw)
        } else {
          body_raw
        }
        text <- truncate_tool_result(text, "WebFetch")

        ellmer::ContentToolResult(
          value = text,
          extra = list(display = list(
            title    = htmltools::HTML(sprintf(
              "WebFetch <code>%s</code>",
              htmltools::htmlEscape(.url_host(url))
            )),
            markdown = sprintf("**URL:** %s\n\n```\n%s\n```",
                               url, substr(text, 1L, 500L))
          ))
        )
      }, error = function(e) {
        msg <- paste0("[Error] WebFetch: ", conditionMessage(e))
        ellmer::ContentToolResult(
          value = msg,
          extra = list(display = list(
            title    = htmltools::HTML(sprintf(
              "WebFetch <code>%s</code> — error",
              htmltools::htmlEscape(.url_host(url))
            )),
            markdown = msg
          ))
        )
      })
    },
    description = paste0(
      "Fetch the content of a URL and return it as plain text. ",
      "HTML is stripped to readable text. ",
      "Use prompt to describe what information to extract (informational only)."
    ),
    arguments = list(
      url    = ellmer::type_string(
        "The URL to fetch.", required = TRUE),
      prompt = ellmer::type_string(
        "What to look for in the fetched content (optional context).",
        required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "WebFetch",
      read_only_hint = TRUE,
      open_world_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# WebSearch tool
# ---------------------------------------------------------------------------

#' Create the WebSearch tool
#'
#' Performs a web search. Uses Brave Search API when `BRAVE_API_KEY` is set;
#' falls back to DuckDuckGo Instant Answer API (entity queries only).
#'
#' @return An `ellmer::tool()` object.
#' @export
web_search_tool <- function() {
  ellmer::tool(
    fun = function(query, num_results = 8L) {
      n <- min(as.integer(num_results), 20L)

      # --- Try Brave Search first ---
      brave_key <- Sys.getenv("BRAVE_API_KEY", "")
      if (nzchar(brave_key)) {
        return(.search_brave(query, n, brave_key))
      }

      # --- Fallback: DuckDuckGo Instant Answer API ---
      .search_ddg(query, n)
    },
    description = paste0(
      "Search the web for a query and return results with titles, snippets, and URLs. ",
      "Uses Brave Search API (set BRAVE_API_KEY) for real search results; ",
      "falls back to DuckDuckGo Instant Answer API for entity queries. ",
      "For general questions without BRAVE_API_KEY, use WebFetch with a direct URL instead."
    ),
    arguments = list(
      query       = ellmer::type_string(
        "The search query.", required = TRUE),
      num_results = ellmer::type_number(
        "Number of results to return (default 8, max 20).", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title           = "WebSearch",
      read_only_hint  = TRUE,
      open_world_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Search backends
# ---------------------------------------------------------------------------

.search_brave <- function(query, n, api_key) {
  tryCatch({
    resp <- httr2::request("https://api.search.brave.com/res/v1/web/search") |>
      httr2::req_headers(
        "Accept"               = "application/json",
        "Accept-Encoding"      = "gzip",
        "X-Subscription-Token" = api_key
      ) |>
      httr2::req_url_query(q = query, count = n, safesearch = "moderate") |>
      httr2::req_timeout(15) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform()

    status <- httr2::resp_status(resp)
    if (status >= 400L)
      return(.search_result_error(query, paste("Brave API HTTP", status)))

    body    <- tryCatch(
      jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE),
      error = function(e) list()
    )
    results_raw <- body[["web"]][["results"]] %||% list()
    results <- character(0)
    for (r in utils::head(results_raw, n)) {
      title   <- r[["title"]]       %||% ""
      url     <- r[["url"]]         %||% ""
      snippet <- r[["description"]] %||% ""
      if (nzchar(title))
        results <- c(results, sprintf("**%s**\n%s\n%s", title, snippet, url))
    }
    if (length(results) == 0L)
      return(.search_result_empty(query, "Brave"))

    text <- paste(results, collapse = "\n\n")
    text <- truncate_tool_result(text, "WebSearch")

    ellmer::ContentToolResult(
      value = text,
      extra = list(display = list(
        title    = htmltools::HTML(sprintf(
          "WebSearch <em>%s</em> (%d results, Brave)",
          htmltools::htmlEscape(query), length(results)
        )),
        markdown = sprintf("**Query:** %s\n\n%s", query, text)
      ))
    )
  }, error = function(e) {
    .search_result_error(query, conditionMessage(e))
  })
}

.search_ddg <- function(query, n) {
  tryCatch({
    url  <- paste0(
      "https://api.duckduckgo.com/?q=",
      utils::URLencode(query, reserved = TRUE),
      "&format=json&no_redirect=1&no_html=1"
    )
    resp <- httr2::request(url) |>
      httr2::req_headers("User-Agent" = "codeagent/0.1") |>
      httr2::req_timeout(15) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform()

    body_str <- httr2::resp_body_string(resp)
    body     <- tryCatch(
      jsonlite::fromJSON(body_str, simplifyVector = FALSE),
      error = function(e) list()
    )

    items   <- body[["RelatedTopics"]] %||% list()
    results <- character(0)
    for (item in utils::head(items, n)) {
      text <- item[["Text"]]     %||% ""
      href <- item[["FirstURL"]] %||% ""
      if (nzchar(text))
        results <- c(results, paste0("- ", text,
                                     if (nzchar(href)) paste0("\n  ", href) else ""))
    }

    abstract     <- body[["Abstract"]]    %||% ""
    abstract_url <- body[["AbstractURL"]] %||% ""
    if (nzchar(abstract))
      results <- c(sprintf("Summary: %s%s", abstract,
                           if (nzchar(abstract_url)) paste0("\n", abstract_url) else ""),
                   results)

    if (length(results) == 0L) {
      msg <- paste0(
        "No results found for: ", query,
        "\n[Note: DuckDuckGo Instant Answer only works for entity queries. ",
        "Set BRAVE_API_KEY for general web search.]"
      )
      return(ellmer::ContentToolResult(
        value = msg,
        extra = list(display = list(
          title    = htmltools::HTML(sprintf(
            "WebSearch <em>%s</em> — no results (DDG)",
            htmltools::htmlEscape(query)
          )),
          markdown = msg
        ))
      ))
    }

    text <- paste(results, collapse = "\n\n")
    text <- truncate_tool_result(text, "WebSearch")

    ellmer::ContentToolResult(
      value = text,
      extra = list(display = list(
        title    = htmltools::HTML(sprintf(
          "WebSearch <em>%s</em> (%d results, DDG)",
          htmltools::htmlEscape(query), length(results)
        )),
        markdown = sprintf("**Query:** %s\n\n%s", query, text)
      ))
    )
  }, error = function(e) {
    .search_result_error(query, conditionMessage(e))
  })
}

.search_result_error <- function(query, msg) {
  full_msg <- paste0("[Error] WebSearch: ", msg)
  ellmer::ContentToolResult(
    value = full_msg,
    extra = list(display = list(
      title    = htmltools::HTML(sprintf(
        "WebSearch <em>%s</em> — error",
        htmltools::htmlEscape(query)
      )),
      markdown = full_msg
    ))
  )
}

.search_result_empty <- function(query, backend) {
  msg <- paste0("No results found for: ", query, " (", backend, ")")
  ellmer::ContentToolResult(
    value = msg,
    extra = list(display = list(
      title    = htmltools::HTML(sprintf(
        "WebSearch <em>%s</em> — no results",
        htmltools::htmlEscape(query)
      )),
      markdown = msg
    ))
  )
}

# ---------------------------------------------------------------------------
# Register web tools
# ---------------------------------------------------------------------------

#' Register web tools to an ellmer Chat object
#'
#' @param chat An `ellmer::Chat` object.
#' @return Invisibly returns `chat`.
#' @export
register_web_tools <- function(chat) {
  chat$register_tool(web_fetch_tool())
  chat$register_tool(web_search_tool())
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Extract hostname from URL for display
.url_host <- function(url) {
  m <- regmatches(url, regexpr("https?://([^/]+)", url, perl = TRUE))
  if (length(m) > 0L) sub("https?://", "", m) else url
}

# Strip HTML tags and normalise whitespace
.strip_html <- function(html) {
  text <- gsub("<script[^>]*>.*?</script>", " ", html,
               ignore.case = TRUE, perl = TRUE)
  text <- gsub("<style[^>]*>.*?</style>", " ", text,
               ignore.case = TRUE, perl = TRUE)
  text <- gsub("<[^>]+>", " ", text, perl = TRUE)
  text <- gsub("&amp;",  "&",  text, fixed = TRUE)
  text <- gsub("&lt;",   "<",  text, fixed = TRUE)
  text <- gsub("&gt;",   ">",  text, fixed = TRUE)
  text <- gsub("&quot;", "\"", text, fixed = TRUE)
  text <- gsub("&#39;",  "'",  text, fixed = TRUE)
  text <- gsub("&nbsp;", " ",  text, fixed = TRUE)
  text <- gsub("[ \t]+", " ", text)
  text <- gsub("\n{3,}", "\n\n", text)
  trimws(text)
}
