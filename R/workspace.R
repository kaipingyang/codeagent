#' @title Workspace tabs
#' @description The right-panel workspace: one tab per opened thing (a tool
#'   result, a file, a host's own content), keyed by `(kind, content_id)`.
#'   Layout logic lives in [workspace_layout]; this file holds the kind
#'   registry, the UI and the per-session server.
#' @name workspace
#' @keywords internal
NULL

#' Declare a kind of workspace tab
#'
#' A kind says how a tab of that kind renders. Pass kinds to
#' [workspace_options()]; open tabs with the `ws` object
#' [codeagent_server()] returns (`ws$open(kind, content_id)`).
#'
#' @param kind Name of the kind, e.g. `"tfl"`.
#' @param render `function(content_id, session)` returning UI for one tab. It
#'   runs inside a `renderUI()`, so it may read reactive values.
#' @param title Optional `function(content_id)` giving the tab title when the
#'   caller does not pass one.
#' @param pinned If `TRUE`, one tab of this kind (content id = the kind name)
#'   opens when the workspace starts, sorts first and cannot be closed.
#' @return A `codeagent_workspace_kind` object.
#' @export
codeagent_workspace_kind <- function(kind, render, title = NULL, pinned = FALSE) {
  if (!is.character(kind) || length(kind) != 1L || is.na(kind) ||
      !grepl("^[A-Za-z][A-Za-z0-9_.-]*$", kind))
    stop("`kind` must be a name (letters, digits, '_', '.', '-').", call. = FALSE)
  if (!is.function(render))
    stop("`render` must be a function(content_id, session).", call. = FALSE)
  if (!is.null(title) && !is.function(title))
    stop("`title` must be NULL or a function(content_id).", call. = FALSE)
  structure(list(kind = kind, render = render, title = title, pinned = isTRUE(pinned)),
            class = "codeagent_workspace_kind")
}

#' Workspace options for a codeagent server
#'
#' @param kinds A list of [codeagent_workspace_kind()] objects.
#' @param max_tabs Most tabs open at once. Opening one more closes the least
#'   recently viewed tab that is not pinned.
#' @param builtin If `TRUE`, add codeagent's kinds: `result` (a tool result by
#'   its request id) and `file` (a project file by its path). A host kind with
#'   the same name replaces a built-in one.
#' @return A `codeagent_workspace_options` object for
#'   `codeagent_server(workspace = )`.
#' @export
workspace_options <- function(kinds = list(), max_tabs = 12, builtin = TRUE) {
  if (inherits(kinds, "codeagent_workspace_kind")) kinds <- list(kinds)
  if (!is.list(kinds) || !all(vapply(kinds, inherits, NA, "codeagent_workspace_kind")))
    stop("`kinds` must be a list of codeagent_workspace_kind() objects.", call. = FALSE)
  if (!is.numeric(max_tabs) || length(max_tabs) != 1L || is.na(max_tabs) || max_tabs < 1)
    stop("`max_tabs` must be a positive number.", call. = FALSE)
  names(kinds) <- vapply(kinds, `[[`, "", "kind")
  structure(list(kinds = kinds, max_tabs = as.integer(max_tabs), builtin = isTRUE(builtin)),
            class = "codeagent_workspace_options")
}

#' Workspace tabs UI
#'
#' The tab strip and the tab contents. Place it where the workspace should
#' show (a sidebar, a drawer, a card) and pass [workspace_options()] to
#' [codeagent_server()].
#'
#' @param id Element id; one workspace per page.
#' @return An htmltools tag.
#' @export
codeagent_workspace_ui <- function(id = "ca_ws") {
  htmltools::tags$div(
    id = id, class = "ca-ws html-fill-container html-fill-item", `data-ca-ws` = id,
    shiny::uiOutput(paste0(id, "_strip"), class = "ca-ws-strip-out"),
    htmltools::tags$div(
      id = paste0(id, "_body"), class = "ca-ws-body html-fill-container html-fill-item",
      htmltools::tags$div(class = "ca-ws-empty", "Open a tool result or a file to see it here.")))
}

# ---------------------------------------------------------------------------
# Built-in kinds
# ---------------------------------------------------------------------------

.ws_builtin_kinds <- function(chat, cwd) {
  root <- tryCatch(.canonical_security_path(cwd, cwd, allow_missing = FALSE),
                   error = function(e) NULL)
  list(
    result = codeagent_workspace_kind("result",
      render = function(content_id, session) {
        res <- tryCatch(.find_tool_result(chat$get_turns(), content_id),
                        error = function(e) NULL)
        if (is.null(res))
          return(.ws_note("This result is no longer in the conversation."))
        res <- tryCatch(.adapt_tool_result(res), error = function(e) res)
        htmltools::tags$div(class = "ca-ws-result",
          render_artifact(tool_result_artifact(res), mode = "panel"))
      },
      title = function(content_id) "Result"),
    file = codeagent_workspace_kind("file",
      render = function(content_id, session) {
        path <- if (!is.null(root)) tryCatch(
          .canonical_security_path(file.path(root, content_id), root, allow_missing = FALSE),
          error = function(e) NULL)
        if (is.null(path) || !file.exists(path) || dir.exists(path) ||
            !.path_is_within(path, root))
          return(.ws_note("This file cannot be shown."))
        .build_file_preview(path, tools::file_ext(path),
                            id = paste0("ws__", gsub("[^A-Za-z0-9]+", "_", content_id)))
      },
      title = function(content_id) basename(content_id)))
}

.ws_note <- function(text) htmltools::tags$div(class = "ca-ws-note", text)

# Tab title for a tool result: the artifact's title, else the tool name.
.ws_result_title <- function(result) {
  t <- tryCatch(.artifact_title(tool_result_artifact(result)), error = function(e) NULL)
  t <- if (is.character(t) && length(t) == 1L && nzchar(t)) t else
    tryCatch(result@request@name, error = function(e) "Result")
  gsub("<[^>]*>", "", t)
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

.ws_strip_ui <- function(layout) {
  if (!length(layout$tabs)) return(NULL)
  htmltools::tags$div(
    class = "ca-ws-strip", role = "tablist", `aria-label` = "Workspace tabs",
    lapply(layout$tabs, function(t) {
      active <- identical(t$id, layout$active)
      htmltools::tags$div(
        class = paste("ca-ws-tab", if (active) "is-active", if (isTRUE(t$pinned)) "is-pinned"),
        role = "tab", `data-tab` = t$id, `data-pinned` = if (isTRUE(t$pinned)) "true" else "false",
        `aria-selected` = if (active) "true" else "false",
        tabindex = if (active) "0" else "-1", title = t$title,
        htmltools::tags$span(class = "ca-ws-tab-title", t$title),
        if (!isTRUE(t$pinned)) htmltools::tags$button(
          type = "button", class = "ca-ws-tab-close", tabindex = "-1",
          `aria-label` = paste("Close", t$title), htmltools::HTML("&times;")))
    }))
}

# The workspace for one browser session. `state` is the session's
# reactiveValues (slot ws_layout); returns the control object.
.workspace_server <- function(input, output, session, state, options,
                              chat = NULL, cwd = getwd(), id = "ca_ws") {
  kinds <- options$kinds
  if (isTRUE(options$builtin)) {
    builtin <- .ws_builtin_kinds(chat, cwd)
    kinds <- c(kinds, builtin[setdiff(names(builtin), names(kinds))])
  }
  mounted <- new.env(parent = emptyenv())
  out_id <- function(tab) paste0(id, "_out_", tab)
  pane_id <- function(tab) paste0(id, "_pane_", tab)

  get <- function() shiny::isolate(state$ws_layout) %||% .ws_layout()
  set <- function(layout) { state$ws_layout <- layout; invisible(layout) }

  output[[paste0(id, "_strip")]] <- shiny::renderUI(.ws_strip_ui(state$ws_layout %||% .ws_layout()))

  mount <- function(t, active) {
    k <- kinds[[t$kind]]
    content_id <- t$content_id
    output[[out_id(t$id)]] <- shiny::renderUI({
      if (is.null(k)) return(.ws_note(paste0("Cannot show a tab of kind '", t$kind, "'.")))
      tryCatch(k$render(content_id, session),
               error = function(e) .ws_note(paste("Could not show this tab:", conditionMessage(e))))
    })
    shiny::insertUI(
      paste0("#", id, "_body"), where = "beforeEnd", immediate = TRUE, session = session,
      ui = htmltools::tags$div(
        id = pane_id(t$id), class = paste("ca-ws-pane html-fill-container html-fill-item",
                                          if (active) "is-active"),
        role = "tabpanel", `data-tab` = t$id,
        shiny::uiOutput(out_id(t$id), class = "ca-ws-pane-out html-fill-container html-fill-item")))
    assign(t$id, TRUE, envir = mounted)
  }
  unmount <- function(tab) {
    shiny::removeUI(paste0("#", pane_id(tab)), immediate = TRUE, session = session)
    output[[out_id(tab)]] <- NULL
    rm(list = tab, envir = mounted)
  }

  # Bring the page in line with the layout: mount new tabs, drop closed ones,
  # show the active one. Contents of open tabs are never re-mounted.
  shiny::observe({
    state$ws_epoch
    layout <- state$ws_layout %||% .ws_layout()
    ids <- .ws_ids(layout)
    for (tab in setdiff(ls(mounted), ids)) unmount(tab)
    for (t in layout$tabs) if (!exists(t$id, envir = mounted, inherits = FALSE))
      mount(t, identical(t$id, layout$active))
    session$sendCustomMessage("ca_ws_show", list(ws = id, tab = layout$active %||% ""))
  })

  shiny::observeEvent(input[[paste0(id, "_event")]], {
    ev <- input[[paste0(id, "_event")]]
    tab <- ev$tab
    switch(ev$action %||% "",
      focus        = set(.ws_focus(get(), tab)),
      close        = set(.ws_close(get(), tab)),
      close_others = set(.ws_close_others(get(), tab)),
      pin          = set(.ws_pin(get(), tab, TRUE)),
      unpin        = set(.ws_pin(get(), tab, FALSE)),
      NULL)
  }, ignoreInit = TRUE)

  open_pinned <- function(layout) {
    for (k in kinds) if (isTRUE(k$pinned) && is.null(.ws_find(layout, k$kind, k$kind)))
      layout <- .ws_open(layout, k$kind, k$kind,
                         title = if (is.function(k$title)) k$title(k$kind) else k$kind,
                         pinned = TRUE, reveal = FALSE)
    layout
  }
  set(open_pinned(get()))

  ws <- list(
    open = function(kind, content_id, title = NULL, reveal = TRUE) {
      if (!is.character(kind) || length(kind) != 1L || !is.character(content_id) ||
          length(content_id) != 1L || is.na(content_id) || !nzchar(content_id))
        stop("`kind` and `content_id` must be strings.", call. = FALSE)
      k <- kinds[[kind]]
      if (is.null(title) && !is.null(k) && is.function(k$title))
        title <- tryCatch(k$title(content_id), error = function(e) NULL)
      layout <- .ws_open(get(), kind, content_id, title = title,
                         pinned = isTRUE(k$pinned), reveal = reveal,
                         max_tabs = options$max_tabs)
      set(layout)
      invisible(.ws_find(layout, kind, content_id))
    },
    close  = function(tab) invisible(set(.ws_close(get(), tab))),
    focus  = function(tab) invisible(set(.ws_focus(get(), tab))),
    pin    = function(tab, pinned = TRUE) invisible(set(.ws_pin(get(), tab, pinned))),
    active = function() {
      layout <- state$ws_layout %||% .ws_layout()
      i <- .ws_index(layout, layout$active)
      if (is.na(i)) NULL else layout$tabs[[i]]
    },
    tabs   = function() (state$ws_layout %||% .ws_layout())$tabs,
    layout = function() get(),
    # A conversation was opened or a new one started: its layout replaces the
    # current one; every tab re-renders from its content id.
    restore = function(layout = NULL) {
      for (tab in ls(mounted)) unmount(tab)
      state$ws_epoch <- (shiny::isolate(state$ws_epoch) %||% 0L) + 1L
      set(open_pinned(.ws_validate(layout)))
    })
  class(ws) <- "codeagent_workspace"
  ws
}
