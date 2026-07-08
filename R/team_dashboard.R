#' @title Live team-board dashboard
#' @description A standalone Shiny app that live-monitors a shared task board
#'   ([board_create()] / [team_coordinate()]): task table (coloured by status),
#'   a progress bar, and the inter-agent message log. Point it at the `db_path`
#'   of a team running in another process (or a background `team_coordinate()`).
#'
#'   Updates are event-driven via [board_watch()] (the `watcher` package) so the
#'   view refreshes the instant the board changes; it falls back to periodic
#'   polling when watcher is unavailable.
#' @name team_dashboard
#' @keywords internal
NULL

# Summarise a board_status() data.frame into counts + percent done. PURE.
.board_progress <- function(status_df) {
  if (is.null(status_df) || !nrow(status_df))
    return(list(total = 0L, done = 0L, claimed = 0L, pending = 0L, pct = 0))
  s <- status_df$status
  total   <- length(s)
  done    <- sum(s == "done")
  claimed <- sum(s == "claimed")
  pending <- sum(s == "pending")
  list(total = total, done = done, claimed = claimed, pending = pending,
       pct = if (total > 0L) round(done / total * 100) else 0)
}

# Bootstrap contextual class for a task status (for the table + badges).
.board_status_class <- function(status) {
  switch(status %||% "",
    done = "success", claimed = "warning", pending = "secondary", "secondary")
}

#' Launch the live team-board dashboard
#'
#' @param db_path Character. Path to the board SQLite file to monitor.
#' @param poll_ms Integer. Poll interval (ms) used only when the `watcher`
#'   package is unavailable (event-driven otherwise). Default 1500.
#' @param title Character. Dashboard title.
#' @param ... Passed to [shiny::shinyApp()] `options` (e.g. `port`).
#' @return A `shiny.appobj`.
#' @export
team_dashboard <- function(db_path, poll_ms = 1500L,
                           title = "codeagent \u2014 team board", ...) {
  ui <- bslib::page_fillable(
    theme = bslib::bs_theme(version = 5),
    shiny::tags$h4(title, class = "mt-2"),
    bslib::card(
      bslib::card_body(padding = 10, shiny::uiOutput("ca_board_progress"))
    ),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(
        bslib::card_header("Tasks"),
        reactable::reactableOutput("ca_board_tasks")
      ),
      bslib::card(
        bslib::card_header("Messages"),
        reactable::reactableOutput("ca_board_messages")
      )
    )
  )

  server <- function(input, output, session) {
    # A tick reactiveVal is bumped whenever the board file changes; every render
    # depends on it. Prefer event-driven watcher; fall back to polling.
    tick <- shiny::reactiveVal(0L)
    bump <- function(...) tick(shiny::isolate(tick()) + 1L)

    w <- board_watch(db_path, callback = bump)
    if (is.null(w)) {
      shiny::observe({
        shiny::invalidateLater(poll_ms, session)
        bump()
      })
    } else {
      session$onSessionEnded(function() try(w$stop(), silent = TRUE))
    }

    board <- shiny::reactive({ tick(); tryCatch(board_status(db_path),   error = function(e) NULL) })
    msgs  <- shiny::reactive({ tick(); tryCatch(board_messages(db_path), error = function(e) NULL) })

    output$ca_board_progress <- shiny::renderUI({
      p   <- .board_progress(board())
      pct <- p$pct
      htmltools::tagList(
        htmltools::div(
          class = "d-flex justify-content-between mb-1",
          htmltools::tags$strong(sprintf("%d / %d done", p$done, p$total)),
          htmltools::tags$span(class = "text-muted small",
            sprintf("%d running \u00b7 %d pending", p$claimed, p$pending))
        ),
        htmltools::div(
          class = "progress", style = "height:16px;",
          htmltools::div(
            class = "progress-bar bg-success",
            role  = "progressbar",
            style = sprintf("width:%d%%;", pct),
            sprintf("%d%%", pct)
          )
        )
      )
    })

    output$ca_board_tasks <- reactable::renderReactable({
      df <- board()
      if (is.null(df) || !nrow(df))
        df <- data.frame(id = integer(0), prompt = character(0),
                         owner = character(0), status = character(0))
      reactable::reactable(
        df[, intersect(c("id", "prompt", "owner", "status"), names(df)), drop = FALSE],
        compact = TRUE, highlight = TRUE, defaultPageSize = 15,
        columns = list(
          status = reactable::colDef(cell = function(value) {
            htmltools::tags$span(
              class = paste0("badge bg-", .board_status_class(value)), value)
          })
        )
      )
    })

    output$ca_board_messages <- reactable::renderReactable({
      m <- msgs()
      if (is.null(m) || !nrow(m))
        m <- data.frame(sender = character(0), body = character(0))
      reactable::reactable(
        m[, intersect(c("sender", "recipient", "body"), names(m)), drop = FALSE],
        compact = TRUE, defaultPageSize = 15)
    })
  }

  shiny::shinyApp(ui, server, options = list(...))
}
