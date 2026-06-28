#' @title Web Tools
#' @description WebFetch and WebSearch tools for codeagent.
#'
#' WebSearch: DuckDuckGo HTML scraping (no key, general queries) with
#'   DDG Instant Answer fallback for entity queries.
#'
#' WebFetch: Jina Reader (r.jina.ai, no key, returns clean Markdown) as
#'   primary; httr2 direct fetch as fallback.
#'
#' @name tools_web
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# WebFetch tool
# ---------------------------------------------------------------------------

#' Create the WebFetch tool
#'
#' Primary: Jina Reader (r.jina.ai) — converts any URL to clean Markdown
#' without Chrome. Fallback: httr2 direct fetch with HTML stripping.
#'
#' @return An `ellmer::tool()` object.
#' @export
web_fetch_tool <- function() {
  ellmer::tool(
    fun = function(url, prompt = NULL) {
      # --- Primary: Jina Reader ---
      result <- tryCatch({
        jina_url <- paste0("https://r.jina.ai/", url)
        resp <- httr2::request(jina_url) |>
          httr2::req_headers(
            "User-Agent" = "codeagent/0.1 (R)",
            "Accept"     = "text/plain"
          ) |>
          httr2::req_timeout(30) |>
          httr2::req_error(is_error = function(r) FALSE) |>
          httr2::req_perform()

        status <- httr2::resp_status(resp)
        if (status == 200L) {
          text <- httr2::resp_body_string(resp)
          if (nchar(trimws(text)) > 100L) {
            text <- truncate_tool_result(text, "WebFetch")
            return(ellmer::ContentToolResult(
              value = text,
              extra = list(display = list(
                title    = htmltools::HTML(sprintf(
                  "WebFetch <code>%s</code> <small style='color:#888'>(Jina)</small>",
                  htmltools::htmlEscape(.url_host(url))
                )),
                markdown = sprintf("**URL:** %s\n\n%s", url, substr(text, 1L, 500L))
              ))
            ))
          }
        }
        NULL
      }, error = function(e) NULL)

      if (!is.null(result)) return(result)

      # --- Fallback: httr2 direct fetch ---
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
        text <- if (grepl("html", content_type, ignore.case = TRUE))
          .strip_html(body_raw)
        else
          body_raw
        text <- truncate_tool_result(text, "WebFetch")

        ellmer::ContentToolResult(
          value = text,
          extra = list(display = list(
            title    = htmltools::HTML(sprintf(
              "WebFetch <code>%s</code>",
              htmltools::htmlEscape(.url_host(url))
            )),
            markdown = sprintf("**URL:** %s\n\n%s", url, substr(text, 1L, 500L))
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
      "Fetch the content of a URL and return it as clean Markdown text. ",
      "Uses Jina Reader (r.jina.ai) for clean extraction; falls back to direct fetch. ",
      "No API key required. Works without Chrome/Chromium."
    ),
    arguments = list(
      url    = ellmer::type_string("The URL to fetch.", required = TRUE),
      prompt = ellmer::type_string(
        "What to look for in the content (optional context).", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title           = "WebFetch",
      read_only_hint  = TRUE,
      open_world_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# WebSearch tool
# ---------------------------------------------------------------------------

#' Create the WebSearch tool
#'
#' Primary: DuckDuckGo HTML scraping — real search results, no API key.
#' Fallback: DuckDuckGo Instant Answer API for entity queries.
#'
#' @return An `ellmer::tool()` object.
#' @export
web_search_tool <- function() {
  ellmer::tool(
    fun = function(query, num_results = 8L) {
      n <- min(as.integer(num_results), 20L)

      # --- Primary: DDG HTML scraping ---
      result <- .search_ddg_html(query, n)
      if (!is.null(result)) return(result)

      # --- Fallback: DDG Instant Answer (entity queries) ---
      .search_ddg_instant(query, n)
    },
    description = paste0(
      "Search the web for a query and return a list of results with titles and URLs. ",
      "Uses DuckDuckGo HTML search — no API key required, supports general queries. ",
      "Results include title + URL; use WebFetch to read a specific page."
    ),
    arguments = list(
      query       = ellmer::type_string("The search query.", required = TRUE),
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

.search_ddg_html <- function(query, n) {
  tryCatch({
    url <- paste0(
      "https://html.duckduckgo.com/html/?q=",
      utils::URLencode(query, reserved = TRUE)
    )
    resp <- httr2::request(url) |>
      httr2::req_headers(
        "User-Agent" = paste0(
          "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) ",
          "Gecko/20100101 Firefox/115.0"
        )
      ) |>
      httr2::req_timeout(15) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform()

    status <- httr2::resp_status(resp)
    if (status >= 400L) return(NULL)

    html <- httr2::resp_body_string(resp)

    # Parse result blocks
    blocks <- .ddg_html_parse(html, n)
    if (length(blocks) == 0L) return(NULL)

    text <- paste(blocks, collapse = "\n\n")
    text <- truncate_tool_result(text, "WebSearch")

    ellmer::ContentToolResult(
      value = text,
      extra = list(display = list(
        title    = htmltools::HTML(sprintf(
          "WebSearch <em>%s</em> (%d results)",
          htmltools::htmlEscape(query), length(blocks)
        )),
        markdown = sprintf("**Query:** %s\n\n%s", query, text)
      ))
    )
  }, error = function(e) NULL)
}

# Parse DuckDuckGo HTML search results
.ddg_html_parse <- function(html, n) {
  results <- character(0)

  # Split on result divs
  parts <- strsplit(html, '<div class="result results_links', fixed = TRUE)[[1L]]
  if (length(parts) <= 1L) return(results)
  parts <- parts[-1L]  # drop preamble

  for (part in utils::head(parts, n)) {
    # Title: <a ... class="result__a" ...>TITLE</a>
    title_m <- regexpr('<a[^>]+class="result__a"[^>]*>(.*?)</a>', part, perl = TRUE)
    title <- if (title_m > 0L)
      gsub("<[^>]+>", "", regmatches(part, title_m))
    else ""

    # URL from uddg= parameter
    url_m <- regexpr("uddg=([^&\" >]+)", part, perl = TRUE)
    url <- if (url_m > 0L) {
      raw <- sub("uddg=", "", regmatches(part, url_m))
      utils::URLdecode(raw)
    } else ""

    # Snippet
    snip_m <- regexpr('class="result__snippet">(.*?)</span>', part, perl = TRUE)
    snippet <- if (snip_m > 0L)
      trimws(gsub("<[^>]+>", "", regmatches(part, snip_m)))
    else ""

    if (nzchar(title) && nzchar(url)) {
      entry <- paste0("**", trimws(title), "**\n", url)
      if (nzchar(snippet)) entry <- paste0(entry, "\n", snippet)
      results <- c(results, entry)
    }
  }
  results
}

.search_ddg_instant <- function(query, n) {
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
        results <- c(results, paste0(
          "- ", text,
          if (nzchar(href)) paste0("\n  ", href) else ""
        ))
    }

    abstract     <- body[["Abstract"]]    %||% ""
    abstract_url <- body[["AbstractURL"]] %||% ""
    if (nzchar(abstract))
      results <- c(
        sprintf("Summary: %s%s", abstract,
                if (nzchar(abstract_url)) paste0("\n", abstract_url) else ""),
        results
      )

    if (length(results) == 0L) {
      msg <- paste0("No results found for: ", query)
      return(ellmer::ContentToolResult(
        value = msg,
        extra = list(display = list(
          title    = htmltools::HTML(sprintf(
            "WebSearch <em>%s</em> — no results",
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
          "WebSearch <em>%s</em> (%d results, instant)",
          htmltools::htmlEscape(query), length(results)
        )),
        markdown = sprintf("**Query:** %s\n\n%s", query, text)
      ))
    )
  }, error = function(e) {
    msg <- paste0("[Error] WebSearch: ", conditionMessage(e))
    ellmer::ContentToolResult(
      value = msg,
      extra = list(display = list(
        title    = htmltools::HTML(sprintf(
          "WebSearch <em>%s</em> — error",
          htmltools::htmlEscape(query)
        )),
        markdown = msg
      ))
    )
  })
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

.url_host <- function(url) {
  m <- regmatches(url, regexpr("https?://([^/]+)", url, perl = TRUE))
  if (length(m) > 0L) sub("https?://", "", m) else url
}

.strip_html <- function(html) {
  text <- gsub("<script[^>]*>.*?</script>", " ", html, ignore.case = TRUE, perl = TRUE)
  text <- gsub("<style[^>]*>.*?</style>",   " ", text, ignore.case = TRUE, perl = TRUE)
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
