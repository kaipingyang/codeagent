#' @title Web Tools
#' @description WebFetch and WebSearch tools for codeagent. Every successful
#'   result carries validated source records under `extra$codeagent$sources`.
#'   Network requests use the shared URL policy and DNS pinning layer.
#' @name tools_web
#' @keywords internal
NULL

.web_tool_result <- function(value, title, markdown, sources = list()) {
  result <- .artifact_tool_result(
    value,
    kind = "text",
    title = htmltools::HTML(title),
    payload = list(text = value),
    markdown = markdown
  )
  ex <- result@extra
  ex$codeagent$sources <- .dedupe_web_sources(sources)
  result@extra <- ex
  result
}

#' Create the WebFetch tool
#'
#' Fetches an authorized public HTTP(S) URL directly. DNS answers are validated
#' and the selected public IP is pinned for the connection; redirects are
#' re-authorized one hop at a time.
#'
#' @param citations Logical. Append the source-ID marker protocol to model-facing
#'   output. Source metadata is always retained in the tool result.
#' @return An `ellmer::tool()` object.
#' @export
web_fetch_tool <- function(citations = FALSE) {
  force(citations)
  ellmer::tool(
    name = "WebFetch",
    fun = function(url, prompt = NULL) {
      safe_url <- tryCatch(.safe_web_source_url(url), error = function(e) NULL)
      host_label <- if (!is.null(safe_url)) .url_host(safe_url) else "blocked URL"
      tryCatch({
        response <- .safe_web_request(
          url, timeout = 30,
          headers = list(
            `User-Agent` = "codeagent/0.1 (R)",
            Accept = "text/html,text/plain,application/json;q=0.9,*/*;q=0.5"))
        status <- response$status
        if (status >= 400L) {
          msg <- paste0("[WebFetch] HTTP ", status, " for ", host_label)
          return(.web_tool_result(
            msg,
            sprintf("WebFetch <code>%s</code> -- HTTP %d",
                    htmltools::htmlEscape(host_label), status),
            msg, list()))
        }

        body <- response$body %||% ""
        content_type <- response$content_type %||% ""
        title <- host_label
        if (grepl("html", content_type, ignore.case = TRUE)) {
          title_match <- regmatches(body, regexpr(
            "(?is)<title[^>]*>(.*?)</title>", body, perl = TRUE))
          if (length(title_match) && nzchar(title_match))
            title <- .sanitize_web_source_text(title_match, 300L)
          text <- .strip_html(body)
        } else {
          text <- body
        }
        text <- truncate_tool_result(text, "WebFetch")
        quote <- .sanitize_web_source_text(substr(text, 1L, 1200L), 1200L)
        source <- .new_web_source(response$url %||% safe_url, title, quote, "WebFetch")
        sources <- list(source)
        value <- text
        if (isTRUE(citations))
          value <- paste0(value, "\n\n", .format_web_sources_for_model(sources))
        .web_tool_result(
          value,
          sprintf("WebFetch <code>%s</code>", htmltools::htmlEscape(host_label)),
          sprintf("**URL:** %s\n\n%s", source$url, substr(text, 1L, 500L)),
          sources)
      }, error = function(e) {
        msg <- paste0("[Error] WebFetch denied or failed for ", host_label, ": ",
                      conditionMessage(e))
        .web_tool_result(
          msg,
          sprintf("WebFetch <code>%s</code> -- error",
                  htmltools::htmlEscape(host_label)),
          msg, list())
      })
    },
    description = paste0(
      "Fetch a public HTTP(S) URL as text. Private, loopback, link-local, ",
      "credentialed, unsafe redirect, and mixed-DNS targets are rejected. ",
      "Successful results include source IDs for deterministic citations."),
    arguments = list(
      url = ellmer::type_string("The public HTTP(S) URL to fetch.", required = TRUE),
      prompt = ellmer::type_string(
        "What to look for in the content (optional context).", required = FALSE)),
    annotations = ellmer::tool_annotations(
      title = "WebFetch", read_only_hint = TRUE, open_world_hint = TRUE))
}

#' Create the WebSearch tool
#'
#' @param citations Logical. Append the source-ID marker protocol to model-facing
#'   output. Source metadata is always retained in the tool result.
#' @return An `ellmer::tool()` object.
#' @export
web_search_tool <- function(citations = FALSE) {
  force(citations)
  ellmer::tool(
    name = "WebSearch",
    fun = function(query, num_results = 8L) {
      n <- suppressWarnings(as.integer(num_results)[1L])
      if (is.na(n)) n <- 8L
      n <- max(1L, min(n, 20L))
      result <- .search_ddg_html(query, n, citations = citations)
      if (!is.null(result)) return(result)
      .search_ddg_instant(query, n, citations = citations)
    },
    description = paste0(
      "Search the public web and return titles, URLs, snippets, and stable ",
      "source IDs. Use WebFetch to read a selected page."),
    arguments = list(
      query = ellmer::type_string("The search query.", required = TRUE),
      num_results = ellmer::type_number(
        "Number of results (default 8, max 20).", required = FALSE)),
    annotations = ellmer::tool_annotations(
      title = "WebSearch", read_only_hint = TRUE, open_world_hint = TRUE))
}

.search_records_to_result <- function(records, query, backend, citations) {
  sources <- list(); blocks <- character()
  for (record in records) {
    source <- tryCatch(.new_web_source(
      record$url, record$title, record$snippet %||% "", "WebSearch"),
      error = function(e) NULL)
    if (is.null(source)) next
    sources[[length(sources) + 1L]] <- source
    block <- paste0("[", source$id, "] **", source$title, "**\n", source$url)
    if (nzchar(source$cited_quote))
      block <- paste0(block, "\n", source$cited_quote)
    blocks <- c(blocks, block)
  }
  sources <- .dedupe_web_sources(sources)
  if (!length(sources)) return(NULL)
  text <- truncate_tool_result(paste(blocks, collapse = "\n\n"), "WebSearch")
  value <- text
  if (isTRUE(citations))
    value <- paste0(value, "\n\n", .format_web_sources_for_model(sources))
  suffix <- if (identical(backend, "instant")) ", instant" else ""
  .web_tool_result(
    value,
    sprintf("WebSearch <em>%s</em> (%d results%s)",
            htmltools::htmlEscape(query), length(sources), suffix),
    sprintf("**Query:** %s\n\n%s", query, text),
    sources)
}

.search_ddg_html <- function(query, n, citations = FALSE) {
  tryCatch({
    url <- paste0("https://html.duckduckgo.com/html/?q=",
                  utils::URLencode(query, reserved = TRUE))
    response <- .safe_web_request(
      url, timeout = 15,
      headers = list(`User-Agent` = paste0(
        "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) ",
        "Gecko/20100101 Firefox/115.0")))
    if (response$status >= 400L) return(NULL)
    records <- .ddg_html_parse_records(response$body, n)
    if (!length(records)) return(NULL)
    .search_records_to_result(records, query, "html", citations)
  }, error = function(e) NULL)
}

.ddg_html_parse_records <- function(html, n) {
  records <- list()
  parts <- strsplit(html, '<div class="result results_links', fixed = TRUE)[[1L]]
  if (length(parts) <= 1L) return(records)
  for (part in utils::head(parts[-1L], n)) {
    title_m <- regexpr('<a[^>]+class="result__a"[^>]*>(.*?)</a>', part, perl = TRUE)
    title <- if (title_m > 0L)
      .sanitize_web_source_text(regmatches(part, title_m), 300L) else ""
    url_m <- regexpr("uddg=([^&\" >]+)", part, perl = TRUE)
    url <- if (url_m > 0L)
      utils::URLdecode(sub("uddg=", "", regmatches(part, url_m))) else ""
    snip_m <- regexpr('<span[^>]*class="result__snippet"[^>]*>(.*?)</span>', part, perl = TRUE)
    snippet <- if (snip_m > 0L)
      .sanitize_web_source_text(regmatches(part, snip_m), 1200L) else ""
    if (nzchar(title) && nzchar(url))
      records[[length(records) + 1L]] <- list(
        title = title, url = url, snippet = snippet)
  }
  records
}

# Backward-compatible formatter used by older internal callers/tests.
.ddg_html_parse <- function(html, n) {
  records <- .ddg_html_parse_records(html, n)
  vapply(records, function(x) paste0(
    "**", x$title, "**\n", x$url,
    if (nzchar(x$snippet)) paste0("\n", x$snippet) else ""), character(1L))
}

.search_ddg_instant <- function(query, n, citations = FALSE) {
  tryCatch({
    url <- paste0("https://api.duckduckgo.com/?q=",
                  utils::URLencode(query, reserved = TRUE),
                  "&format=json&no_redirect=1&no_html=1")
    response <- .safe_web_request(
      url, timeout = 15,
      headers = list(`User-Agent` = "codeagent/0.1"))
    body <- tryCatch(jsonlite::fromJSON(response$body, simplifyVector = FALSE),
                     error = function(e) list())
    records <- list()
    abstract <- body[["Abstract"]] %||% ""
    abstract_url <- body[["AbstractURL"]] %||% ""
    if (nzchar(abstract) && nzchar(abstract_url))
      records[[length(records) + 1L]] <- list(
        title = body[["Heading"]] %||% .url_host(abstract_url),
        url = abstract_url, snippet = abstract)
    for (item in utils::head(body[["RelatedTopics"]] %||% list(), n)) {
      text <- item[["Text"]] %||% ""; href <- item[["FirstURL"]] %||% ""
      if (nzchar(text) && nzchar(href))
        records[[length(records) + 1L]] <- list(
          title = text, url = href, snippet = text)
    }
    result <- .search_records_to_result(records, query, "instant", citations)
    if (!is.null(result)) return(result)
    msg <- paste0("No results found for: ", query)
    .web_tool_result(
      msg,
      sprintf("WebSearch <em>%s</em> -- no results",
              htmltools::htmlEscape(query)), msg, list())
  }, error = function(e) {
    msg <- paste0("[Error] WebSearch: ", conditionMessage(e))
    .web_tool_result(
      msg,
      sprintf("WebSearch <em>%s</em> -- error",
              htmltools::htmlEscape(query)), msg, list())
  })
}

#' Register web tools to an ellmer Chat object
#'
#' @param chat An `ellmer::Chat` object.
#' @param citations Logical. Enable marker-protocol instructions in tool output.
#' @return Invisibly returns `chat`.
#' @export
register_web_tools <- function(chat, citations = FALSE) {
  chat$register_tool(web_fetch_tool(citations = citations))
  chat$register_tool(web_search_tool(citations = citations))
  invisible(chat)
}

.url_host <- function(url) {
  parsed <- tryCatch(httr2::url_parse(url), error = function(e) NULL)
  if (is.null(parsed)) return(as.character(url)[1L])
  parsed$hostname %||% as.character(url)[1L]
}

.strip_html <- function(html) {
  text <- gsub("(?is)<script[^>]*>.*?</script>", " ", html, perl = TRUE)
  text <- gsub("(?is)<style[^>]*>.*?</style>", " ", text, perl = TRUE)
  text <- gsub("<[^>]+>", " ", text, perl = TRUE)
  text <- gsub("&amp;", "&", text, fixed = TRUE)
  text <- gsub("&lt;", "<", text, fixed = TRUE)
  text <- gsub("&gt;", ">", text, fixed = TRUE)
  text <- gsub("&quot;", "\"", text, fixed = TRUE)
  text <- gsub("&#39;", "'", text, fixed = TRUE)
  text <- gsub("&nbsp;", " ", text, fixed = TRUE)
  text <- gsub("[ \t]+", " ", text)
  text <- gsub("\n{3,}", "\n\n", text)
  trimws(text)
}
