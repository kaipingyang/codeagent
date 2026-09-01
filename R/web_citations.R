.web_citations_enabled <- function(value) {
  isTRUE(value) || identical(value, "shiny_aside")
}

# Web citation source records, deterministic marker bridge, and URL policy.
# All helpers are internal; model output never directly supplies HTML attributes.

.sanitize_web_source_text <- function(x, max_chars = 1000L) {
  if (is.null(x) || !length(x)) return("")
  x <- enc2utf8(as.character(x)[1L])
  ints <- utf8ToInt(x)
  ints <- ints[ints == 9L | ints == 10L | ints == 13L | ints >= 32L]
  x <- intToUtf8(ints)
  x <- gsub("(?is)<script[^>]*>.*?</script>", " ", x, perl = TRUE)
  x <- gsub("(?is)<style[^>]*>.*?</style>", " ", x, perl = TRUE)
  x <- gsub("<[^>]*>", "", x, perl = TRUE)
  x <- gsub("[[:space:]]+", " ", x, perl = TRUE)
  x <- trimws(x)
  if (nchar(x, type = "chars") > max_chars)
    x <- paste0(substr(x, 1L, max_chars), "...")
  x
}

.is_ipv4_literal <- function(x) {
  grepl("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", x, perl = TRUE)
}

.ipv4_parts <- function(x) {
  out <- suppressWarnings(as.integer(strsplit(x, ".", fixed = TRUE)[[1L]]))
  if (length(out) != 4L || anyNA(out) || any(out < 0L | out > 255L)) integer() else out
}

.is_global_ip <- function(ip) {
  ip <- tolower(gsub("^\\[|\\]$", "", trimws(as.character(ip)[1L])))
  if (.is_ipv4_literal(ip)) {
    p <- .ipv4_parts(ip)
    if (!length(p)) return(FALSE)
    if (p[1] == 0L || p[1] == 10L || p[1] == 127L || p[1] >= 224L) return(FALSE)
    if (p[1] == 100L && p[2] >= 64L && p[2] <= 127L) return(FALSE)
    if (p[1] == 169L && p[2] == 254L) return(FALSE)
    if (p[1] == 172L && p[2] >= 16L && p[2] <= 31L) return(FALSE)
    if (p[1] == 192L && p[2] == 168L) return(FALSE)
    if (p[1] == 192L && p[2] == 0L && p[3] %in% c(0L, 2L)) return(FALSE)
    if (p[1] == 198L && p[2] %in% c(18L, 19L, 51L)) return(FALSE)
    if (p[1] == 203L && p[2] == 0L && p[3] == 113L) return(FALSE)
    return(TRUE)
  }
  if (!grepl(":", ip, fixed = TRUE)) return(FALSE)
  if (startsWith(ip, "::ffff:"))
    return(.is_global_ip(sub("^::ffff:", "", ip)))
  # Conservatively allow only IPv6 global-unicast 2000::/3, excluding the
  # documentation range. This rejects ULA, link-local, multicast, unspecified,
  # IPv4-compatible, benchmarking, and other special-purpose prefixes.
  first <- suppressWarnings(strtoi(strsplit(ip, ":", fixed = TRUE)[[1L]][1L],
                                   base = 16L))
  if (is.na(first) || first < 0x2000L || first > 0x3fffL ||
      startsWith(ip, "2001:db8:")) return(FALSE)
  TRUE
}

.safe_web_source_url <- function(url) {
  if (!is.character(url) || length(url) != 1L || is.na(url) || !nzchar(trimws(url)))
    stop("URL must be a non-empty character scalar.", call. = FALSE)
  url <- trimws(url)
  if (grepl("[\\x00-\\x1f\\x7f]", url, perl = TRUE) || startsWith(url, "//"))
    stop("URL contains control characters or is protocol-relative.", call. = FALSE)
  parsed <- tryCatch(httr2::url_parse(url), error = function(e) NULL)
  if (is.null(parsed) || !tolower(parsed$scheme %||% "") %in% c("http", "https"))
    stop("Only absolute http/https URLs are allowed.", call. = FALSE)
  if (nzchar(parsed$username %||% "") || nzchar(parsed$password %||% ""))
    stop("URL credentials/userinfo are not allowed.", call. = FALSE)
  host <- tolower(sub("\\.$", "", parsed$hostname %||% ""))
  if (!nzchar(host) || grepl("[[:space:]/@]", host))
    stop("URL hostname is invalid.", call. = FALSE)
  if (host == "localhost" || endsWith(host, ".localhost") ||
      endsWith(host, ".local") || endsWith(host, ".internal"))
    stop("Local/private hostnames are not allowed.", call. = FALSE)
  bare_host <- gsub("^\\[|\\]$", "", host)
  if ((.is_ipv4_literal(bare_host) || grepl(":", bare_host, fixed = TRUE)) &&
      !.is_global_ip(bare_host))
    stop("URL resolves to a private, loopback, link-local, or non-global address.",
         call. = FALSE)
  parsed$scheme <- tolower(parsed$scheme)
  parsed$hostname <- host
  parsed$fragment <- NULL
  httr2::url_build(parsed)
}

.web_source_id <- function(...) {
  bytes <- as.integer(charToRaw(enc2utf8(paste(..., collapse = "\u001f"))))
  # Two independent 16-bit modular accumulators avoid R integer overflow and
  # the precision loss of multiplying a 32-bit hash in a double.
  h1 <- 5381
  h2 <- 52711
  for (b in bytes) {
    h1 <- (h1 * 251 + b + 1) %% 65521
    h2 <- (h2 * 257 + b + h1) %% 65521
  }
  paste0("src_", sprintf("%04x%04x", as.integer(h1), as.integer(h2)))
}

.new_web_source <- function(url, title, cited_quote, tool, id = NULL) {
  url <- .safe_web_source_url(url)
  title <- .sanitize_web_source_text(title, 300L)
  cited_quote <- .sanitize_web_source_text(cited_quote, 1200L)
  tool <- .sanitize_web_source_text(tool, 40L)
  if (!nzchar(title)) title <- .url_host(url)
  if (is.null(id)) id <- .web_source_id(url, title, cited_quote, tool)
  id <- as.character(id)[1L]
  if (!grepl("^src_[a-z0-9]{8}$", id))
    stop("Source id must match src_ plus eight lowercase alphanumeric characters.",
         call. = FALSE)
  list(id = id, url = url, title = title, cited_quote = cited_quote, tool = tool)
}

.validate_web_source <- function(source) {
  if (!is.list(source) || !all(c("id", "url", "title", "cited_quote", "tool") %in% names(source)))
    return(NULL)
  tryCatch(.new_web_source(source$url, source$title, source$cited_quote,
                           source$tool, source$id), error = function(e) NULL)
}

.dedupe_web_sources <- function(sources) {
  out <- list(); seen <- character()
  for (source in sources %||% list()) {
    source <- .validate_web_source(source)
    if (is.null(source) || source$url %in% seen) next
    seen <- c(seen, source$url)
    out[[length(out) + 1L]] <- source
  }
  out
}

.format_web_sources_for_model <- function(sources) {
  sources <- .dedupe_web_sources(sources)
  if (!length(sources)) return("")
  blocks <- vapply(sources, function(x) paste0(
    "[SOURCE ", x$id, "]\nTitle: ", x$title, "\nURL: ", x$url,
    "\nQuote: ", x$cited_quote, "\n[/SOURCE]"), character(1L))
  paste0("<web-sources untrusted=\"true\">\n",
         paste(blocks, collapse = "\n\n"),
         "\n</web-sources>\nUse [[cite:SOURCE_ID|visible claim]] to cite only these sources.")
}

.new_citation_registry <- function() {
  reg <- new.env(parent = emptyenv())
  reg$values <- new.env(hash = TRUE, parent = emptyenv())
  reg$urls <- new.env(hash = TRUE, parent = emptyenv())
  reg$conflicts <- new.env(hash = TRUE, parent = emptyenv())
  # Native provider citations use opaque ref ids so untrusted grounded spans
  # never enter marker syntax. The span is kept server-side in this registry.
  reg$refs <- new.env(hash = TRUE, parent = emptyenv())
  class(reg) <- c("codeagent_citation_registry", "environment")
  reg
}

.citation_registry_clear <- function(registry) {
  for (env in list(registry$values, registry$urls, registry$conflicts,
                   registry$refs)) {
    keys <- ls(env, all.names = TRUE)
    if (length(keys)) rm(list = keys, envir = env)
  }
  invisible(registry)
}

.citation_registry_add <- function(registry, sources) {
  for (source in sources %||% list()) {
    source <- .validate_web_source(source)
    if (is.null(source)) next
    id <- source$id
    if (exists(id, registry$conflicts, inherits = FALSE)) next
    if (exists(id, registry$values, inherits = FALSE)) {
      old <- get(id, registry$values, inherits = FALSE)
      if (!identical(old, source)) {
        rm(list = id, envir = registry$values)
        assign(id, TRUE, envir = registry$conflicts)
      }
      next
    }
    if (exists(source$url, registry$urls, inherits = FALSE)) next
    assign(id, source, envir = registry$values)
    assign(source$url, id, envir = registry$urls)
  }
  invisible(registry)
}

.citation_registry_get <- function(registry, id) {
  if (is.null(registry) || exists(id, registry$conflicts, inherits = FALSE) ||
      !exists(id, registry$values, inherits = FALSE)) return(NULL)
  get(id, registry$values, inherits = FALSE)
}

.citation_registry_add_ref <- function(registry, source_id,
                                       grounded_span = "") {
  grounded_span <- if (is.character(grounded_span) &&
                       length(grounded_span) == 1L && !is.na(grounded_span))
    grounded_span else ""
  ref_id <- sub(
    "^src_", "ref_",
    .web_source_id(source_id, grounded_span), fixed = FALSE)
  ref <- list(source_id = source_id, grounded_span = grounded_span)
  if (exists(ref_id, registry$refs, inherits = FALSE)) {
    if (!identical(get(ref_id, registry$refs, inherits = FALSE), ref))
      return(NULL)
    return(ref_id)
  }
  assign(ref_id, ref, envir = registry$refs)
  ref_id
}

.citation_registry_get_ref <- function(registry, ref_id) {
  if (is.null(registry) || !exists(ref_id, registry$refs, inherits = FALSE))
    return(NULL)
  get(ref_id, registry$refs, inherits = FALSE)
}

.citation_sources_from_result <- function(result) {
  sources <- tryCatch(result@extra$codeagent$sources, error = function(e) NULL)
  .dedupe_web_sources(sources %||% list())
}

.native_citations_from_turn <- function(turn) {
  contents <- tryCatch(turn@contents, error = function(e) list())
  Filter(function(content)
    inherits(content, "ellmer::ContentCitation"), contents)
}

.native_citations_from_chat <- function(chat) {
  turn <- tryCatch(chat$last_turn(role = "assistant"), error = function(e) NULL)
  .native_citations_from_turn(turn)
}

.native_citation_source <- function(citation) {
  source <- tryCatch(citation@source, error = function(e) NULL)
  if (!inherits(source, "ellmer::WebSource")) return(NULL)
  tryCatch(
    .new_web_source(
      url = source@url,
      title = source@title %||% "",
      cited_quote = tryCatch(citation@cited_quote, error = function(e) "") %||% "",
      tool = "ProviderCitation"),
    error = function(e) NULL)
}

# Convert trusted ellmer ContentCitation objects into opaque internal markers.
# Provider fields remain server-side; only ref ids enter the text renderer.
.inject_native_citation_markers <- function(text, citations, registry) {
  text <- as.character(text %||% "")[1L]
  insertions <- list()
  for (citation in citations %||% list()) {
    if (!inherits(citation, "ellmer::ContentCitation")) next
    source <- .native_citation_source(citation)
    if (is.null(source)) next
    .citation_registry_add(registry, list(source))
    source_id <- if (exists(source$url, registry$urls, inherits = FALSE))
      get(source$url, registry$urls, inherits = FALSE) else NULL
    if (is.null(source_id) ||
        is.null(.citation_registry_get(registry, source_id))) next

    span <- tryCatch(citation@grounded_span, error = function(e) "") %||% ""
    if (!is.character(span) || length(span) != 1L || is.na(span)) span <- ""
    positions <- if (nzchar(span)) gregexpr(span, text, fixed = TRUE)[[1L]] else -1L
    matched <- length(positions) && !identical(positions[1L], -1L)
    if (matched) {
      position <- positions[length(positions)] +
        nchar(span, type = "chars") - 1L
    } else {
      position <- nchar(text, type = "chars")
      span <- ""
    }
    ref_id <- .citation_registry_add_ref(registry, source_id, span)
    if (is.null(ref_id)) next
    key <- as.character(position)
    insertions[[key]] <- paste0(
      insertions[[key]] %||% "", "[[cite-ref:", ref_id, "]]"
    )
  }
  if (!length(insertions)) return(text)
  positions <- sort(as.integer(names(insertions)), decreasing = TRUE)
  for (position in positions) {
    prefix <- if (position > 0L) substr(text, 1L, position) else ""
    suffix <- if (position < nchar(text, type = "chars"))
      substr(text, position + 1L, nchar(text, type = "chars")) else ""
    text <- paste0(prefix, insertions[[as.character(position)]], suffix)
  }
  text
}

.render_turn_citations <- function(text, registry, settings, chat,
                                   turn = NULL) {
  if (is.null(turn))
    turn <- tryCatch(chat$last_turn(role = "assistant"), error = function(e) NULL)
  text <- .inject_native_citation_markers(
    text, .native_citations_from_turn(turn), registry)
  .render_citation_markers(text, registry, settings, chat)
}

.citation_scan_field <- function(value, settings, chat) {
  out <- tryCatch(.output_gate_guarded(value, settings, chat), error = function(e) NULL)
  if (is.null(out) || out$action %in% c("block", "ask")) return(NULL)
  as.character(out$text %||% value)[1L]
}

.escape_html <- function(x, attribute = FALSE) {
  as.character(htmltools::htmlEscape(x %||% "", attribute = attribute))
}

.format_shiny_aside_tag <- function(grounded_span, source) {
  grounded_attr <- if (nzchar(grounded_span %||% "")) paste0(
    "grounded-span=\"", .escape_html(grounded_span, TRUE), "\" ") else ""
  paste0(
    "<shiny-aside data-citation ",
    "url=\"", .escape_html(source$url, TRUE), "\" ",
    "display=\"compact\" ",
    grounded_attr,
    "cited-quote=\"", .escape_html(source$cited_quote, TRUE), "\">",
    "<a href=\"", .escape_html(source$url, TRUE), "\">",
    .escape_html(source$title), "</a></shiny-aside>")
}

.format_shiny_aside <- function(claim, source) {
  paste0(
    .escape_html(claim),
    .format_shiny_aside_tag(claim, source)
  )
}

.render_citation_markers <- function(text, registry, settings, chat) {
  text <- as.character(text %||% "")[1L]
  cite_pattern <- "\\[\\[cite:(src_[a-z0-9]{8})\\|([^]\\r\\n]+)\\]\\]"
  ref_pattern <- "\\[\\[cite-ref:(ref_[a-z0-9]{8})\\]\\]"
  pattern <- paste0("(?:", cite_pattern, "|", ref_pattern, ")")
  matches <- gregexpr(pattern, text, perl = TRUE)[[1L]]
  if (identical(matches[1L], -1L)) return(.escape_html(text))
  lengths <- attr(matches, "match.length")
  out <- character(); cursor <- 1L
  for (i in seq_along(matches)) {
    start <- matches[i]; end <- start + lengths[i] - 1L
    if (start > cursor) out <- c(out, .escape_html(substr(text, cursor, start - 1L)))
    marker <- substr(text, start, end)
    rendered <- NULL

    if (startsWith(marker, "[[cite-ref:")) {
      captures <- regmatches(
        marker, regexec(ref_pattern, marker, perl = TRUE))[[1L]]
      ref <- .citation_registry_get_ref(registry, captures[2L])
      source <- if (!is.null(ref))
        .citation_registry_get(registry, ref$source_id) else NULL
      if (!is.null(source)) {
        fields <- list(
          grounded_span = .citation_scan_field(
            ref$grounded_span, settings, chat),
          title = .citation_scan_field(source$title, settings, chat),
          quote = .citation_scan_field(source$cited_quote, settings, chat),
          url = .citation_scan_field(source$url, settings, chat))
        if (all(vapply(fields, function(x) !is.null(x), logical(1L)))) {
          safe_url <- tryCatch(
            .safe_web_source_url(fields$url), error = function(e) NULL)
          if (!is.null(safe_url)) {
            source$title <- .sanitize_web_source_text(fields$title, 300L)
            source$cited_quote <- .sanitize_web_source_text(fields$quote, 1200L)
            source$url <- safe_url
            grounded_span <- .sanitize_web_source_text(
              fields$grounded_span, 500L)
            rendered <- .format_shiny_aside_tag(grounded_span, source)
          }
        }
      }
    } else {
      captures <- regmatches(
        marker, regexec(cite_pattern, marker, perl = TRUE))[[1L]]
      source <- .citation_registry_get(registry, captures[2L])
      if (!is.null(source)) {
        claim <- .sanitize_web_source_text(captures[3L], 500L)
        fields <- list(
          claim = .citation_scan_field(claim, settings, chat),
          title = .citation_scan_field(source$title, settings, chat),
          quote = .citation_scan_field(source$cited_quote, settings, chat),
          url = .citation_scan_field(source$url, settings, chat))
        if (all(vapply(fields, function(x) !is.null(x), logical(1L)))) {
          safe_url <- tryCatch(
            .safe_web_source_url(fields$url), error = function(e) NULL)
          if (!is.null(safe_url) && nzchar(fields$claim)) {
            source$title <- .sanitize_web_source_text(fields$title, 300L)
            source$cited_quote <- .sanitize_web_source_text(fields$quote, 1200L)
            source$url <- safe_url
            rendered <- .format_shiny_aside(fields$claim, source)
          }
        }
      }
    }
    out <- c(out, rendered %||% .escape_html(marker))
    cursor <- end + 1L
  }
  if (cursor <= nchar(text))
    out <- c(out, .escape_html(substr(text, cursor, nchar(text))))
  paste0(out, collapse = "")
}

.resolve_web_host <- function(host) {
  host <- gsub("^\\[|\\]$", "", host)
  if (.is_ipv4_literal(host) || grepl(":", host, fixed = TRUE)) return(host)
  curl::nslookup(host, ipv4_only = FALSE, multiple = TRUE, error = TRUE)
}

.authorize_web_url <- function(url) {
  safe <- .safe_web_source_url(url)
  parsed <- httr2::url_parse(safe)
  host <- gsub("^\\[|\\]$", "", tolower(parsed$hostname))
  ips <- unique(as.character(.resolve_web_host(host)))
  if (!length(ips) || any(!vapply(ips, .is_global_ip, logical(1L))))
    stop("Web URL DNS returned a private or non-global address; request denied.",
         call. = FALSE)
  port <- suppressWarnings(as.integer(parsed$port %||%
    if (identical(parsed$scheme, "https")) 443L else 80L))
  if (is.na(port) || port < 1L || port > 65535L)
    stop("Web URL port is invalid.", call. = FALSE)
  list(url = safe, host = host, port = port, ip = ips[1L], scheme = parsed$scheme)
}

.perform_pinned_web_request <- function(url, host, port, ip, timeout = 30,
                                        headers = list()) {
  pin_ip <- if (grepl(":", ip, fixed = TRUE)) paste0("[", ip, "]") else ip
  req <- httr2::request(url)
  if (length(headers)) req <- do.call(httr2::req_headers, c(list(req), headers))
  req <- httr2::req_timeout(req, timeout) |>
    httr2::req_options(
      resolve = paste0(host, ":", port, ":", pin_ip),
      followlocation = FALSE,
      proxy = "", noproxy = "*",
      maxfilesize = 5 * 1024 * 1024) |>
    httr2::req_error(is_error = function(r) FALSE)
  resp <- httr2::req_perform(req)
  list(
    status = httr2::resp_status(resp),
    headers = as.list(httr2::resp_headers(resp)),
    body = httr2::resp_body_string(resp),
    content_type = httr2::resp_content_type(resp) %||% "",
    url = url)
}

.absolute_redirect_url <- function(location, base_url) {
  location <- trimws(as.character(location)[1L])
  if (grepl("^https?://", location, ignore.case = TRUE)) return(location)
  base <- httr2::url_parse(base_url)
  origin <- paste0(base$scheme, "://", base$hostname,
                   if (nzchar(base$port %||% "")) paste0(":", base$port) else "")
  if (startsWith(location, "//")) return(paste0(base$scheme, ":", location))
  if (startsWith(location, "/")) return(paste0(origin, location))
  path <- base$path %||% "/"
  directory <- sub("[^/]*$", "", path)
  paste0(origin, directory, location)
}

.safe_web_request <- function(url, timeout = 30, headers = list(), max_redirects = 5L) {
  current <- url; visited <- character()
  current_headers <- headers
  previous_origin <- NULL
  for (hop in 0:as.integer(max_redirects)) {
    auth <- .authorize_web_url(current)
    origin <- paste0(auth$scheme, "://", auth$host, ":", auth$port)
    if (!is.null(previous_origin) && !identical(origin, previous_origin))
      current_headers <- list()
    if (auth$url %in% visited) stop("Web redirect loop detected.", call. = FALSE)
    visited <- c(visited, auth$url)
    response <- .perform_pinned_web_request(
      auth$url, auth$host, auth$port, auth$ip,
      timeout = timeout, headers = current_headers)
    if (!response$status %in% c(301L, 302L, 303L, 307L, 308L)) return(response)
    location <- response$headers$location %||% response$headers$Location %||% NULL
    if (is.null(location) || !nzchar(location))
      stop("Web redirect response omitted Location.", call. = FALSE)
    if (hop >= as.integer(max_redirects))
      stop("Web redirect limit exceeded.", call. = FALSE)
    previous_origin <- origin
    current <- .absolute_redirect_url(location, auth$url)
  }
  stop("Web redirect limit exceeded.", call. = FALSE)
}


.citation_registry_from_last_round <- function(chat) {
  registry <- .new_citation_registry()
  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  if (!length(turns)) return(registry)
  for (turn in rev(turns)) {
    role <- tryCatch(turn@role, error = function(e) "")
    contents <- tryCatch(turn@contents, error = function(e) list())
    is_result <- vapply(contents, function(content)
      inherits(content, "ellmer::ContentToolResult"), logical(1L))
    if (any(is_result)) {
      for (result in contents[is_result])
        .citation_registry_add(
          registry, .citation_sources_from_result(result))
    } else if (identical(role, "user")) {
      break
    }
  }
  registry
}
