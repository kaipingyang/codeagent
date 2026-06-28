#' @title Web Tools
#' @description WebFetch and WebSearch tools for codeagent.
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
          httr2::req_perform()

        content_type <- httr2::resp_content_type(resp)
        body_raw     <- httr2::resp_body_string(resp)

        # Strip HTML tags for readability
        text <- if (grepl("html", content_type, ignore.case = TRUE)) {
          .strip_html(body_raw)
        } else {
          body_raw
        }

        truncate_tool_result(text, "WebFetch")
      }, error = function(e) {
        paste0("[Error] WebFetch: ", conditionMessage(e))
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
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# WebSearch tool
# ---------------------------------------------------------------------------

#' Create the WebSearch tool
#'
#' Performs a web search and returns a list of results.
#' Requires the `httr2` package. Falls back to a simple DuckDuckGo query.
#'
#' @return An `ellmer::tool()` object.
#' @export
web_search_tool <- function() {
  ellmer::tool(
    fun = function(query, num_results = 8L) {
      tryCatch({
        n     <- min(as.integer(num_results), 20L)
        # DuckDuckGo Instant Answer API (no auth required)
        url   <- paste0(
          "https://api.duckduckgo.com/?q=",
          utils::URLencode(query, reserved = TRUE),
          "&format=json&no_redirect=1&no_html=1"
        )
        resp  <- httr2::request(url) |>
          httr2::req_headers("User-Agent" = "codeagent/0.1") |>
          httr2::req_timeout(15) |>
          httr2::req_perform()

        body_str <- httr2::resp_body_string(resp)
        body     <- tryCatch(
          jsonlite::fromJSON(body_str, simplifyVector = FALSE),
          error = function(e) list()
        )

        # Extract related topics as results
        items <- body[["RelatedTopics"]] %||% list()
        results <- character(0)

        for (item in utils::head(items, n)) {
          text <- item[["Text"]]    %||% ""
          href <- item[["FirstURL"]] %||% ""
          if (nzchar(text)) {
            results <- c(results,
                         paste0("- ", text,
                                if (nzchar(href)) paste0("\n  ", href) else ""))
          }
        }

        # Include abstract if available
        abstract <- body[["Abstract"]] %||% ""
        abstract_url <- body[["AbstractURL"]] %||% ""
        if (nzchar(abstract)) {
          results <- c(paste0("Summary: ", abstract,
                              if (nzchar(abstract_url))
                                paste0("\n", abstract_url) else ""),
                       results)
        }

        if (length(results) == 0L)
          return(paste0("No results found for: ", query))

        result <- paste(results, collapse = "\n\n")
        truncate_tool_result(result, "WebSearch")
      }, error = function(e) {
        paste0("[Error] WebSearch: ", conditionMessage(e))
      })
    },
    description = paste0(
      "Search the web for a query and return a list of results with titles, ",
      "snippets, and URLs. Uses DuckDuckGo Instant Answer API."
    ),
    arguments = list(
      query       = ellmer::type_string(
        "The search query.", required = TRUE),
      num_results = ellmer::type_number(
        "Number of results to return (default 8, max 20).", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "WebSearch",
      read_only_hint = TRUE
    )
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

# Strip HTML tags and normalise whitespace
.strip_html <- function(html) {
  # Remove script and style blocks
  text <- gsub("<script[^>]*>.*?</script>", " ", html,
               ignore.case = TRUE, perl = TRUE)
  text <- gsub("<style[^>]*>.*?</style>", " ", text,
               ignore.case = TRUE, perl = TRUE)
  # Remove all remaining tags
  text <- gsub("<[^>]+>", " ", text, perl = TRUE)
  # Decode common HTML entities
  text <- gsub("&amp;",  "&",  text, fixed = TRUE)
  text <- gsub("&lt;",   "<",  text, fixed = TRUE)
  text <- gsub("&gt;",   ">",  text, fixed = TRUE)
  text <- gsub("&quot;", "\"", text, fixed = TRUE)
  text <- gsub("&#39;",  "'",  text, fixed = TRUE)
  text <- gsub("&nbsp;", " ",  text, fixed = TRUE)
  # Collapse whitespace
  text <- gsub("[ \t]+", " ", text)
  text <- gsub("\n{3,}", "\n\n", text)
  trimws(text)
}
