#' @title Typed Tool-Result Display Contract + Render Dispatcher
#' @description Rich, interactive tool-card rendering for the right Output panel.
#'   Defines a typed display contract (`extra$display$toolcard`) layered on top of the
#'   existing `{title, markdown, right_output}` keys, a render dispatcher that
#'   branches on result kind (code/image/table/diff/text/error), and a
#'   generalized adapter that normalizes any native `ContentToolResult` -- raw
#'   `btw::btw_tools()` results included -- into the typed contract.
#'
#'   Design: the private `card` sub-list never collides with shinychat's reserved
#'   display keys (title/icon/markdown/html/text), so the in-chat card keeps
#'   rendering natively while codeagent owns the right-panel rendering.
#' @name tool_display
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Per-tool icon lookup (bsicons names). Used for in-chat card icon + adapter.
# ---------------------------------------------------------------------------

.TOOL_ICONS <- list(
  Bash      = "terminal",
  Read      = "file-text",
  Write     = "file-earmark-plus",
  Edit      = "pencil",
  MultiEdit = "pencil-square",
  Glob      = "search",
  Grep      = "search",
  LS        = "folder",
  RunR      = "play-circle"
)

# btw tool-name prefix -> icon
.BTW_ICON_PREFIXES <- list(
  "btw_tool_docs_"        = "book",
  "btw_tool_git_"         = "git",
  "btw_tool_env_"         = "table",
  "btw_tool_files_"       = "file-earmark",
  "btw_tool_pkg_"         = "box-seam",
  "btw_tool_web_"         = "globe",
  "btw_tool_cran_"        = "box",
  "btw_tool_ide_"         = "window",
  "btw_tool_sessioninfo_" = "info-circle",
  "btw_tool_agent_"       = "robot"
)

.icon_for_tool <- function(tool_name) {
  if (is.null(tool_name) || !nzchar(tool_name)) return("wrench")
  if (!is.null(.TOOL_ICONS[[tool_name]])) return(.TOOL_ICONS[[tool_name]])
  for (p in names(.BTW_ICON_PREFIXES)) {
    if (startsWith(tool_name, p)) return(.BTW_ICON_PREFIXES[[p]])
  }
  "wrench"
}

# Build an icon tag: bsicons when available, FontAwesome fallback (already
# loaded via head_assets()). Returns NULL on total failure (shinychat tolerates).
.icon_tag <- function(name) {
  if (is.null(name) || !nzchar(name)) return(NULL)
  tryCatch(
    bsicons::bs_icon(name),
    error = function(e) htmltools::tags$i(class = paste0("fa fa-", name))
  )
}

# ---------------------------------------------------------------------------
# Typed contract constructor
# ---------------------------------------------------------------------------

#' Build a typed ContentToolResult
#'
#' Superset of the legacy `.tool_result()`: in addition to `title`/`markdown`,
#' carries a typed `card` payload consumed by [render_tool_output()] and eagerly
#' precomputes `right_output` so the existing server push path keeps working.
#'
#' @param text Character. LLM-facing value.
#' @param kind One of `"code"`, `"image"`, `"table"`, `"diff"`, `"text"`,
#'   `"error"`.
#' @param status One of `"success"`, `"error"`, `"denied"`.
#' @param icon bsicons name (character) for the in-chat card + right panel.
#' @param title Character or HTML. Card title (HTML allowed for the in-chat card).
#' @param payload List. Kind-specific data (see file docs).
#' @param markdown Character. In-chat card body + two-phase fallback.
#' @return An `ellmer::ContentToolResult`.
#' @keywords internal
.tool_result2 <- function(text, kind = "text", status = "success",
                          icon = NULL, title = NULL, payload = list(),
                          markdown = NULL) {
  toolcard <- list(
    kind    = kind,
    status  = status,
    icon    = icon,
    title   = if (!is.null(title)) gsub("<[^>]+>", "", as.character(title)) else NULL,
    payload = payload
  )

  display <- list(toolcard = toolcard)
  if (!is.null(title))    display$title    <- htmltools::HTML(as.character(title))
  if (!is.null(icon))     display$icon     <- .icon_tag(icon)
  if (!is.null(markdown)) display$markdown <- markdown

  # Render the rich card once, reuse for BOTH the in-chat bubble (display$html,
  # rendered natively by shinychat inside <shiny-tool-result>) and the right
  # Output panel (display$right_output, consumed by server_chat.R).
  #
  # full_screen=TRUE gives the whole card a single expand affordance (shinychat
  # for the bubble, bslib card for the panel). The in-card toolbar only carries
  # zoom/download (NO separate fullscreen button) so there is exactly one
  # fullscreen control and no event conflict. All toolbar buttons are
  # type="button" + document-delegated, so they survive card re-render/expand.
  rendered <- tryCatch(render_tool_output(display), error = function(e) NULL)
  if (!is.null(rendered)) {
    display$html         <- rendered   # in-chat card body (shinychat-native)
    display$right_output <- rendered   # right Output panel
    display$full_screen  <- TRUE       # single expand affordance per card
    display$open         <- FALSE      # collapsed by default in the chat stream
  }

  ellmer::ContentToolResult(
    value = text,
    extra = list(display = display)
  )
}

# ---------------------------------------------------------------------------
# Render dispatcher
# ---------------------------------------------------------------------------

#' Render a typed tool-result display into an htmltools tag
#'
#' Branches on `display$toolcard$kind`. Falls back to `right_output`, then markdown,
#' then a plain `<pre>` so untyped / raw results still render.
#'
#' @param display A `display` list (the `extra$display` of a ContentToolResult).
#' @return An htmltools tag.
#' @keywords internal
render_tool_output <- function(display) {
  toolcard <- tryCatch(display$toolcard, error = function(e) NULL)

  if (is.null(toolcard) || is.null(toolcard$kind)) {
    # Backward-compat fallback paths.
    ro <- tryCatch(display$right_output, error = function(e) NULL)
    if (!is.null(ro)) return(ro)
    md <- tryCatch(display$markdown, error = function(e) NULL)
    if (!is.null(md) && nzchar(md)) {
      html <- tryCatch(commonmark::markdown_html(md),
                       error = function(e) paste0("<pre>", md, "</pre>"))
      return(htmltools::HTML(html))
    }
    return(htmltools::tags$pre("(no output)"))
  }

  body <- switch(
    toolcard$kind,
    code  = .render_code(toolcard$payload),
    image = .render_image(toolcard$payload),
    table = .render_table(toolcard$payload),
    diff  = .render_diff(toolcard$payload),
    error = .render_error(toolcard$payload),
    text  = .render_text(toolcard$payload),
    .render_text(toolcard$payload)  # default
  )

  status_class <- paste0("toolcard-status-", toolcard$status %||% "success")
  htmltools::tags$div(
    class            = paste("toolcard", status_class),
    `data-toolcard-kind`   = toolcard$kind,
    `data-toolcard-status` = toolcard$status %||% "success",
    body
  )
}

# ---------------------------------------------------------------------------
# Per-kind renderers
# ---------------------------------------------------------------------------

# Header row: icon + title + copy button (copies from target pre)
.card_header <- function(icon, title, copy_target = NULL, lang = NULL,
                         extra_actions = NULL) {
  htmltools::tags$div(
    class = "toolcard-header",
    if (!is.null(icon)) .icon_tag(icon),
    htmltools::tags$span(class = "toolcard-title", title %||% ""),
    if (!is.null(lang))
      htmltools::tags$span(class = "toolcard-lang-badge", lang),
    htmltools::tags$span(class = "toolcard-spacer"),
    extra_actions,
    if (!is.null(copy_target))
      htmltools::tags$button(
        type             = "button",
        class            = "toolcard-copy-btn",
        `data-toolcard-copy`   = copy_target,
        title            = "Copy",
        .icon_tag("clipboard")
      )
  )
}

.render_code <- function(p) {
  lang     <- p$lang %||% "text"
  cid      <- paste0("tccode_", .rand_id())
  htmltools::tagList(
    .card_header(p$icon %||% "file-text", p$filename %||% "Code",
                 copy_target = paste0("#", cid), lang = lang),
    htmltools::tags$pre(
      class = "toolcard-pre",
      htmltools::tags$code(id = cid, class = paste0("language-", lang),
                           p$text %||% "")
    ),
    if (!is.null(p$output) && nzchar(p$output))
      htmltools::tags$pre(class = "toolcard-pre toolcard-pre-output", p$output)
  )
}

.render_text <- function(p) {
  lang <- p$lang %||% NULL
  tid  <- paste0("tctext_", .rand_id())
  # With a language hint -> syntax-highlighted <pre><code>.
  # Without -> render as markdown so rich content (tables, bold, links)
  # displays properly rather than appearing as raw markup in a <pre>.
  content <- if (!is.null(lang)) {
    htmltools::tags$pre(
      class = "toolcard-pre",
      htmltools::tags$code(id = tid,
                           class = paste0("language-", lang),
                           p$text %||% ""))
  } else {
    md <- tryCatch(
      commonmark::markdown_html(p$text %||% ""),
      error = function(e) paste0("<pre>", htmltools::htmlEscape(p$text %||% ""), "</pre>"))
    htmltools::div(id = tid, class = "toolcard-md", htmltools::HTML(md))
  }
  htmltools::tagList(
    .card_header(p$icon %||% "text-left", p$title %||% "Output",
                 copy_target = paste0("#", tid)),
    content
  )
}

.render_error <- function(p) {
  htmltools::tagList(
    .card_header(p$icon %||% "exclamation-triangle", p$title %||% "Error"),
    htmltools::tags$div(
      class = "toolcard-error-box",
      htmltools::tags$div(class = "toolcard-error-msg", p$message %||% "Error"),
      if (!is.null(p$detail) && nzchar(p$detail))
        htmltools::tags$pre(class = "toolcard-pre toolcard-pre-output", p$detail)
    )
  )
}

.render_image <- function(p) {
  images <- p$images %||% list()
  frames <- lapply(images, function(im) {
    src <- paste0("data:", im$mime %||% "image/png", ";base64,", im$b64 %||% "")
    htmltools::tags$div(
      class = "toolcard-img-frame",
      htmltools::tags$div(
        class = "toolcard-zoom-toolbar",
        htmltools::tags$button(class = "toolcard-icon-btn", `data-toolcard-zoom` = "out",
                               title = "Zoom out", .icon_tag("zoom-out")),
        htmltools::tags$button(class = "toolcard-icon-btn", `data-toolcard-zoom` = "fit",
                               title = "Fit", .icon_tag("aspect-ratio")),
        htmltools::tags$button(class = "toolcard-icon-btn", `data-toolcard-zoom` = "in",
                               title = "Zoom in", .icon_tag("zoom-in")),
        htmltools::tags$button(class = "toolcard-icon-btn", `data-toolcard-fullscreen` = "1",
                               title = "Fullscreen", .icon_tag("arrows-fullscreen")),
        htmltools::tags$button(class = "toolcard-icon-btn", `data-toolcard-download` = "1",
                               `data-toolcard-src` = src,
                               title = "Download", .icon_tag("download"))
      ),
      htmltools::tags$div(
        class = "toolcard-img-scroll",
        htmltools::tags$img(class = "toolcard-zoomable", src = src)
      )
    )
  })
  htmltools::tagList(
    .card_header(p$icon %||% "image", p$title %||% "Plot"),
    if (!is.null(p$code) && nzchar(p$code))
      htmltools::tags$pre(class = "toolcard-pre",
        htmltools::tags$code(class = "language-r", p$code)),
    frames,
    if (!is.null(p$output) && nzchar(p$output))
      htmltools::tags$pre(class = "toolcard-pre toolcard-pre-output", p$output)
  )
}

.render_table <- function(p) {
  df   <- p$df %||% NULL
  html <- p$html %||% NULL
  body <- if (!is.null(df) && is.data.frame(df) &&
              requireNamespace("reactable", quietly = TRUE)) {
    tryCatch(
      reactable::reactable(df, compact = TRUE, striped = TRUE,
                           searchable = TRUE, bordered = TRUE,
                           defaultPageSize = 15, highlight = TRUE),
      error = function(e) .html_table(df)
    )
  } else if (!is.null(html)) {
    htmltools::HTML(as.character(html))
  } else if (!is.null(df) && is.data.frame(df)) {
    .html_table(df)
  } else {
    htmltools::tags$pre(class = "toolcard-pre", p$text %||% "(no table)")
  }
  htmltools::tagList(
    .card_header(p$icon %||% "table", p$title %||% "Table"),
    htmltools::tags$div(class = "toolcard-table-wrap", body)
  )
}

.render_diff <- function(p) {
  path <- p$path %||% ""
  verb <- p$verb %||% "Edited"
  old  <- p$old %||% NULL
  new  <- p$new %||% NULL

  if (!is.null(old) || !is.null(new)) {
    lines <- .line_diff(old %||% "", new %||% "")
    rows  <- lapply(lines, function(ln) {
      cls <- switch(ln$type,
                    add = "toolcard-diff-add", del = "toolcard-diff-del", "toolcard-diff-ctx")
      sign <- switch(ln$type, add = "+", del = "-", " ")
      htmltools::tags$div(class = paste("toolcard-diff-line", cls),
                          paste0(sign, " ", ln$text))
    })
    return(htmltools::tagList(
      .card_header(p$icon %||% "pencil",
                   sprintf("%s %s", verb, basename(path))),
      htmltools::tags$div(class = "toolcard-diff", rows)
    ))
  }

  # Only verb/path known -> compact status chip + (optional) new content.
  htmltools::tagList(
    .card_header(p$icon %||% "file-earmark-plus",
                 sprintf("%s %s", verb, basename(path))),
    htmltools::tags$div(class = "toolcard-diff-chip",
      sprintf("%s: %s", verb, path)),
    if (!is.null(new) && nzchar(new))
      htmltools::tags$pre(class = "toolcard-pre", htmltools::tags$code(new))
  )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Pseudo-random id without Math.random/Date dependence concerns (R-side ok).
.rand_id <- function() {
  paste0(sample(c(letters, 0:9), 8, replace = TRUE), collapse = "")
}

# Minimal hand-rolled HTML table (no reactable dependency path).
.html_table <- function(df, max_rows = 100L) {
  df <- utils::head(df, max_rows)
  hdr <- htmltools::tags$tr(lapply(names(df),
    function(nm) htmltools::tags$th(nm)))
  rows <- lapply(seq_len(nrow(df)), function(i) {
    htmltools::tags$tr(lapply(df[i, , drop = FALSE],
      function(v) htmltools::tags$td(format(v))))
  })
  htmltools::tags$table(class = "toolcard-html-table",
    htmltools::tags$thead(hdr), htmltools::tags$tbody(rows))
}

# Line-level diff via base R LCS (no diffobj dependency).
# Returns list of list(type = "add"|"del"|"ctx", text = <line>).
.line_diff <- function(old, new) {
  a <- if (length(old) == 1L) strsplit(old, "\n", fixed = TRUE)[[1]] else old
  b <- if (length(new) == 1L) strsplit(new, "\n", fixed = TRUE)[[1]] else new
  a <- a %||% character(0); b <- b %||% character(0)
  na <- length(a); nb <- length(b)

  # LCS length matrix
  L <- matrix(0L, na + 1L, nb + 1L)
  if (na > 0L && nb > 0L) {
    for (i in seq_len(na)) {
      for (j in seq_len(nb)) {
        L[i + 1L, j + 1L] <- if (identical(a[i], b[j]))
          L[i, j] + 1L else max(L[i, j + 1L], L[i + 1L, j])
      }
    }
  }
  # Backtrack
  out <- list()
  i <- na; j <- nb
  while (i > 0L || j > 0L) {
    if (i > 0L && j > 0L && identical(a[i], b[j])) {
      out[[length(out) + 1L]] <- list(type = "ctx", text = a[i]); i <- i - 1L; j <- j - 1L
    } else if (j > 0L && (i == 0L || L[i + 1L, j] >= L[i, j + 1L])) {
      out[[length(out) + 1L]] <- list(type = "add", text = b[j]); j <- j - 1L
    } else {
      out[[length(out) + 1L]] <- list(type = "del", text = a[i]); i <- i - 1L
    }
  }
  rev(out)
}

# ---------------------------------------------------------------------------
# Generalized adapter: normalize any ContentToolResult into the typed contract
# ---------------------------------------------------------------------------

#' Normalize any tool result into the typed display contract
#'
#' Idempotent: if `result@extra$display$toolcard` already exists it is returned
#' unchanged. Otherwise inspects the result (and btw's `@extra$contents` Content
#' objects) to classify a kind and build a typed `ContentToolResult` whose
#' `@value` is preserved for the LLM.
#'
#' @param result An `ellmer::ContentToolResult` (codeagent, RunR, or raw btw).
#' @return A typed `ContentToolResult`.
#' @keywords internal
.adapt_tool_result <- function(result) {
  # Already typed?
  has_toolcard <- tryCatch(!is.null(result@extra$display$toolcard),
                     error = function(e) FALSE)
  if (isTRUE(has_toolcard)) return(result)

  tool_name <- tryCatch(result@request@name, error = function(e) NULL) %||% "tool"
  icon      <- .icon_for_tool(tool_name)
  value     <- tryCatch(as.character(result@value), error = function(e) "")
  contents  <- tryCatch(result@extra$contents, error = function(e) NULL)

  # If it has codeagent-legacy display keys but no `card`, keep them and just
  # attach a generic text `card` so the dispatcher has a kind.
  legacy_md <- tryCatch(result@extra$display$markdown, error = function(e) NULL)
  legacy_ro <- tryCatch(result@extra$display$right_output, error = function(e) NULL)
  legacy_ti <- tryCatch(result@extra$display$title, error = function(e) NULL)

  images <- list(); text_parts <- character(0); has_error <- FALSE
  for (ct in (contents %||% list())) {
    cls <- class(ct)[1]
    if (grepl("ContentImageInline", cls, fixed = TRUE)) {
      images[[length(images) + 1L]] <- list(
        mime = tryCatch(ct@type, error = function(e) "image/png"),
        b64  = tryCatch(ct@data, error = function(e) "")
      )
    } else if (grepl("ContentError", cls, fixed = TRUE)) {
      has_error <- TRUE
      t <- tryCatch(ct@text, error = function(e) "")
      if (nzchar(t)) text_parts <- c(text_parts, t)
    } else if (grepl("ContentOutput|ContentText|ContentWarning|ContentMessage", cls)) {
      t <- tryCatch(ct@text, error = function(e) "")
      if (nzchar(t)) text_parts <- c(text_parts, t)
    }
  }
  output_text <- paste(text_parts, collapse = "\n")
  if (!nzchar(output_text)) output_text <- value

  # Classify kind
  if (length(images) > 0L) {
    payload <- list(images = images, output = output_text, icon = icon)
    kind <- "image"; status <- "success"
  } else if (isTRUE(has_error)) {
    payload <- list(message = output_text, icon = icon)
    kind <- "error"; status <- "error"
  } else {
    payload <- list(text = output_text, icon = icon)
    kind <- "text"; status <- "success"
  }

  title <- if (!is.null(legacy_ti)) as.character(legacy_ti) else tool_name

  res <- .tool_result2(
    text     = value,
    kind     = kind,
    status   = status,
    icon     = icon,
    title    = title,
    payload  = payload,
    markdown = legacy_md
  )
  # Preserve a pre-rendered legacy right_output if the adapter produced none.
  if (is.null(res@extra$display$right_output) && !is.null(legacy_ro)) {
    res@extra$display$right_output <- legacy_ro
  }
  res
}
