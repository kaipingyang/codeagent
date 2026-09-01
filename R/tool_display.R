#' @title Typed Tool-Result Display Contract + Render Dispatcher
#' @description Rich, interactive tool-card rendering for both the in-chat bubble
#'   and the right Output panel. Defines a typed artifact contract stored under
#'   `extra$codeagent$artifact` (a private key ellmer only transports, so
#'   shinychat never warns about it), a render dispatcher that branches on the
#'   artifact kind (code/image/table/diff/text/error), and a generalized adapter
#'   that normalizes any native `ContentToolResult` -- raw `btw::btw_tools()`
#'   results included -- into the typed contract.
#'
#'   Design: the artifact lives on `extra$codeagent`, never under `extra$display`,
#'   so `display` carries ONLY shinychat-official fields (title/icon/markdown/
#'   html/full_screen/open). The in-chat card keeps
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


.shinychat_tool_result_constructor <- function() {
  .shinychat_export("tool_result_display")
}

.tool_display_preview <- function(value, max_chars = 160L) {
  value <- paste(as.character(value %||% ""), collapse = " ")
  value <- gsub("<[^>]+>", "", value)
  value <- gsub("[[:space:]]+", " ", value)
  value <- trimws(value)
  if (nchar(value) > max_chars)
    paste0(substr(value, 1L, max_chars - 3L), "...") else value
}

.new_tool_result_display <- function(title = NULL, icon = NULL, html = NULL,
                                     markdown = NULL, text = NULL,
                                     show_request = TRUE, open = FALSE,
                                     full_screen = FALSE, footer = NULL,
                                     label = NULL, value_preview = NULL,
                                     open_style = c("minimal", "framed")) {
  open_style <- match.arg(open_style)
  args <- list(
    title = title, icon = icon, html = html, markdown = markdown, text = text,
    show_request = isTRUE(show_request), open = isTRUE(open),
    full_screen = isTRUE(full_screen), footer = footer,
    label = label, value_preview = value_preview, open_style = open_style)
  constructor <- .shinychat_tool_result_constructor()
  if (is.function(constructor)) {
    # The constructor predates open_style in the 0.2.0 release baseline. Omit the
    # new argument there rather than making old installed packages fail.
    constructor_args <- args
    if (!.shinychat_framed_tool_results_available())
      constructor_args$open_style <- NULL
    return(do.call(constructor, constructor_args))
  }

  # Compatibility fallback for an installed shinychat version predating the
  # constructor. Keep only its documented fields and validate scalar flags.
  args$open_style <- NULL
  args <- args[!vapply(args, is.null, logical(1L))]
  args$show_request <- isTRUE(args$show_request)
  args$open <- isTRUE(args$open)
  args$full_screen <- isTRUE(args$full_screen)
  args
}

# ---------------------------------------------------------------------------

.official_tool_display <- function(display = list(), text = "", title = NULL) {
  display <- display %||% list()
  .new_tool_result_display(
    title = display$title %||% title,
    icon = display$icon,
    html = display$html,
    markdown = display$markdown,
    text = display$text,
    show_request = display$show_request %||% TRUE,
    open = display$open %||% FALSE,
    full_screen = display$full_screen %||% !is.null(display$html),
    footer = display$footer,
    label = display$label %||% .tool_display_preview(title %||% "Tool", 60L),
    value_preview = display$value_preview %||% .tool_display_preview(text, 160L),
    open_style = display$open_style %||%
      if (!is.null(display$html)) "framed" else "minimal")
}

# Typed contract constructor
# ---------------------------------------------------------------------------

#' Build a typed ContentToolResult
#'
#' Superset of the legacy `.tool_result()`: in addition to `title`/`markdown`,
#' carries a typed `artifact` payload (on `extra$codeagent`) consumed by
#' [render_artifact()], and renders the panel view into `display$html` so the
#' in-chat card is rich without a separate stored copy.
#'
#' @param text Character. LLM-facing value.
#' @param kind One of `"code"`, `"image"`, `"table"`, `"diff"`, `"text"`,
#'   `"error"`.
#' @param status One of `"success"`, `"error"`, `"denied"`.
#' @param icon bsicons name (character) for the in-chat card + right panel.
#' @param title Character or HTML. Card title (HTML allowed for the in-chat card).
#' @param payload List. Kind-specific data (see file docs).
#' @param markdown Character. In-chat card body + two-phase fallback.
#' @param footer Optional official shinychat footer content.
#' @param label Optional compact activity label.
#' @param value_preview Optional compact result preview.
#' @return An `ellmer::ContentToolResult`.
#' @keywords internal
.tool_result2 <- function(text, kind = "text", status = "success",
                          icon = NULL, title = NULL, payload = list(),
                          markdown = NULL, footer = NULL,
                          label = NULL, value_preview = NULL) {
  # artifact = the single, UI-agnostic structured data source (kind/status/
  # payload). It lives on `extra$codeagent` (NOT `extra$display`) so shinychat --
  # which validates `extra$display` against its official field set and warns
  # "Unrecognized field ... ignoring" -- never sees it. Other UIs (shinyAssistantUI,
  # a React host, future A2UI) read `extra$codeagent$artifact` and render it
  # themselves. This is the artifact/canvas pattern: one data source, multiple
  # views. (plan 35 B1 step 1.)
  artifact <- list(
    kind    = kind,
    status  = status,
    icon    = icon,
    title   = if (!is.null(title)) gsub("<[^>]+>", "", as.character(title)) else NULL,
    payload = payload
  )

  # Render the artifact once. Bubble and panel currently share one render; the
  # right Output panel re-renders from the artifact on demand.
  rendered <- tryCatch(render_artifact(artifact, mode = "panel"),
                       error = function(e) NULL)
  display_title <- if (!is.null(title))
    htmltools::HTML(as.character(title)) else NULL
  display_label <- label %||%
    .tool_display_preview(title %||% tools::toTitleCase(kind), 60L)
  display_preview <- value_preview %||% .tool_display_preview(text, 160L)
  display <- .new_tool_result_display(
    title = display_title,
    icon = if (!is.null(icon)) .icon_tag(icon) else NULL,
    html = rendered,
    markdown = markdown,
    show_request = TRUE,
    open = identical(status, "error") || (nchar(text %||% "") > 500L),
    full_screen = !is.null(rendered),
    footer = footer,
    label = display_label,
    value_preview = display_preview,
    open_style = if (!is.null(rendered)) "framed" else "minimal")

  ellmer::ContentToolResult(
    value = text,
    extra = list(
      display   = display,                    # shinychat-only (official fields)
      codeagent = list(artifact = artifact)   # private data source (right panel / other UIs)
    )
  )
}

#' Build a rich tool result (typed display card) for a host tool
#'
#' @description
#' Construct an [ellmer::ContentToolResult] that carries a **typed display card**,
#' so a tool's output renders as a table / image / code / error / rich text both
#' in codeagent's Shiny app and in any host UI that consumes the
#' `on_tool_result$display` callback of [codeagent_stream()].
#'
#' `value` is the text the model sees; `payload` carries the rich artifact for
#' the UI. Return the result from your tool's function body.
#'
#' A host UI reads `extra$codeagent$artifact$kind` + `...$payload` (the
#' structured artifact, e.g. `payload$df` for a table); codeagent's Shiny app
#' additionally receives a pre-rendered `display$html`.
#'
#' @param value Character(1). Text summary returned to the model.
#' @param kind One of `"text"`, `"table"`, `"image"`, `"code"`, `"diff"`,
#'   `"error"`.
#' @param payload Named list holding the artifact, keyed by `kind`:
#'   * `table`: `list(df = <data.frame>)`
#'   * `image`: `list(images = list(list(mime = "image/png", b64 = <string>)), output = <text>)`
#'   * `code` : `list(text = <code>, lang = , filename = , output = )`
#'   * `error`: `list(message = , detail = )`
#'   * `text` : `list(text = )`
#' @param title,icon Optional card title / icon name.
#' @param status One of `"success"`, `"error"` (forced to `"error"` when
#'   `kind = "error"`).
#' @param markdown Optional markdown string attached to the display.
#' @return An [ellmer::ContentToolResult]; return it from your tool function.
#' @examples
#' \dontrun{
#' summarise <- ellmer::tool(
#'   function(data_name) {
#'     df <- summary_frame(data_name)
#'     tool_result(sprintf("%d x %d summary", nrow(df), ncol(df)),
#'                 kind = "table", payload = list(df = df),
#'                 title = "Summary")
#'   },
#'   name = "Summarise", description = "...", arguments = list(...))
#' chat$register_tool(summarise)
#' register_tool_meta("Summarise", "read")
#' }
#' @seealso [codeagent_stream()], [register_tool_meta()]
#' @export
tool_result <- function(value,
                        kind    = c("text", "table", "image", "code", "diff", "error"),
                        payload = list(),
                        title   = NULL,
                        icon    = NULL,
                        status  = c("success", "error"),
                        markdown = NULL) {
  kind   <- match.arg(kind)
  status <- match.arg(status)
  if (identical(kind, "error")) status <- "error"
  if (!is.character(value) || length(value) != 1L)
    stop("`value` must be a character(1).", call. = FALSE)
  if (!is.list(payload))
    stop("`payload` must be a named list.", call. = FALSE)
  .tool_result2(value, kind = kind, status = status, icon = icon,
                title = title, payload = payload, markdown = markdown)
}

# ---------------------------------------------------------------------------
# Render dispatcher
# ---------------------------------------------------------------------------

# Extract a plain-text Output-panel card title from an artifact (or a display).
# PURE: strips HTML, falls back title -> artifact$title -> "Output". Used by
# server_chat's .push_output; kept unit-testable.
.artifact_title <- function(artifact) {
  tryCatch(
    gsub("<[^>]+>", "",
         as.character(artifact$title %||% artifact$toolcard$title %||%
                      artifact$payload$title %||% "Output")),
    error = function(e) "Output"
  )
}

#' Render an artifact (typed tool-result data source) into an htmltools tag
#'
#' Branches on `artifact$kind` (code/image/table/diff/text/error). This is the
#' single renderer both the in-chat bubble and the right Output panel use.
#'
#' @param artifact The structured data source: `list(kind, status, icon, title,
#'   payload)` from `extra$codeagent$artifact`. (Also tolerates being handed a
#'   whole `display` list carrying a legacy `$toolcard`, for backward-compat.)
#' @param mode `"bubble"` (compact, in-chat) or `"panel"` (full, right Output).
#'   Step 1: accepted but not yet branched -- both render identically. Step 2
#'   will split compact vs full. (plan 35 B1.)
#' @return An htmltools tag.
#' @keywords internal
render_artifact <- function(artifact, mode = c("panel", "bubble")) {
  mode <- match.arg(mode)
  # Backward-compat: accept a legacy `display` list (has $toolcard) or a raw
  # artifact. Resolve to the artifact.
  if (is.list(artifact) && !is.null(artifact$toolcard))
    artifact <- artifact$toolcard

  if (is.null(artifact) || is.null(artifact$kind)) {
    # Fallback: markdown -> <pre>.
    md <- tryCatch(artifact$markdown %||% artifact$payload$markdown, error = function(e) NULL)
    if (!is.null(md) && nzchar(md)) {
      html <- tryCatch(commonmark::markdown_html(md),
                       error = function(e) paste0("<pre>", md, "</pre>"))
      return(htmltools::HTML(html))
    }
    return(htmltools::tags$pre("(no output)"))
  }

  body <- switch(
    artifact$kind,
    code  = .render_code(artifact$payload),
    image = .render_image(artifact$payload),
    table = .render_table(artifact$payload),
    diff  = .render_diff(artifact$payload),
    error = .render_error(artifact$payload),
    text  = .render_text(artifact$payload),
    .render_text(artifact$payload)  # default
  )

  status_class <- paste0("toolcard-status-", artifact$status %||% "success")
  htmltools::tags$div(
    class            = paste("toolcard", status_class),
    `data-toolcard-kind`   = artifact$kind,
    `data-toolcard-status` = artifact$status %||% "success",
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
#' Idempotent: if `result@extra$codeagent$artifact` already exists it is returned
#' unchanged. Otherwise inspects the result (and btw's `@extra$contents` Content
#' objects) to classify a kind and build a typed `ContentToolResult` whose
#' `@value` is preserved for the LLM.
#'
#' @param result An `ellmer::ContentToolResult` (codeagent, RunR, or raw btw).
#' @return A typed `ContentToolResult`.
#' @keywords internal
.adapt_tool_result <- function(result) {
  # Already typed: preserve the private artifact/sources, but normalize a legacy
  # plain display list on the presentation copy.
  if (isTRUE(tryCatch(!is.null(result@extra$codeagent$artifact),
                      error = function(e) FALSE))) {
    display <- tryCatch(result@extra$display, error = function(e) list())
    if (!inherits(display, "shinychat_tool_result_display")) {
      ex <- result@extra
      title <- result@extra$codeagent$artifact$title %||% "Tool"
      ex$display <- .official_tool_display(
        display, tryCatch(result@value, error = function(e) ""), title)
      result@extra <- ex
    }
    return(result)
  }

  # Pre-migration session: a typed card sits under extra$display$toolcard (which
  # shinychat now warns on + drops). Promote it to extra$codeagent$artifact,
  # strip it from display, and re-render the panel html into the official
  # display$html field so old sessions render rich + warning-free.
  legacy_card <- tryCatch(result@extra$display$toolcard, error = function(e) NULL)
  if (!is.null(legacy_card)) {
    ex <- tryCatch(result@extra, error = function(e) list()) %||% list()
    disp <- ex$display %||% list()
    disp$toolcard <- NULL
    disp$right_output <- NULL
    rendered <- tryCatch(render_artifact(legacy_card, mode = "panel"),
                         error = function(e) NULL)
    if (!is.null(rendered)) {
      disp$html <- rendered
      if (is.null(disp$full_screen)) disp$full_screen <- TRUE
    }
    ex$display <- .official_tool_display(
      disp,
      tryCatch(result@value, error = function(e) ""),
      legacy_card$title %||% disp$title %||% "Tool")
    ex$codeagent <- c(ex$codeagent %||% list(), list(artifact = legacy_card))
    result@extra <- ex
    return(result)
  }

  tool_name <- tryCatch(result@request@name, error = function(e) NULL) %||% "tool"
  icon      <- .icon_for_tool(tool_name)
  value     <- tryCatch(as.character(result@value), error = function(e) "")
  contents  <- tryCatch(result@extra$contents, error = function(e) NULL)

  # Legacy display keys from raw btw / pre-migration results (markdown/title).
  # right_output is no longer produced or consumed (removed in plan 35 B1).
  legacy_md <- tryCatch(result@extra$display$markdown, error = function(e) NULL)
  legacy_ti <- tryCatch(result@extra$display$title, error = function(e) NULL)
  legacy_footer <- tryCatch(result@extra$display$footer, error = function(e) NULL)

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
  } else if (grepl("(^|\\n)(diff --git |@@ [-+])", output_text, perl = TRUE)) {
    payload <- list(old = "", new = output_text, path = "patch", verb = "Diff")
    kind <- "diff"; status <- "success"
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
    markdown = legacy_md,
    footer   = legacy_footer
  )
  original_codeagent <- tryCatch(result@extra$codeagent, error = function(e) NULL)
  if (length(original_codeagent)) {
    ex <- res@extra
    ex$codeagent <- utils::modifyList(original_codeagent,
                                      ex$codeagent %||% list())
    res@extra <- ex
  }
  original_request <- tryCatch(result@request, error = function(e) NULL)
  if (!is.null(original_request)) res@request <- original_request
  res
}
