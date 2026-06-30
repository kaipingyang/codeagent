#' @title Settings Server Logic
#' @name server_settings
#' @keywords internal
NULL

server_settings <- function(input, output, session, chat, settings, cwd,
                            hooks = NULL, stream_task = NULL) {

  # Live Customizations counts (Copilot style)
  output$customizations_counts <- shiny::renderUI({
    n_skills <- tryCatch(length(list_skills_meta(cwd)), error = function(e) 0L)
    n_hooks  <- if (!is.null(hooks)) tryCatch(hooks$count(), error = function(e) 0L) else 0L
    n_tools  <- tryCatch(length(chat$get_tools()), error = function(e) 0L)

    make_row <- function(icon, label, count = NULL) {
      htmltools::tags$div(
        class = "custom-item",
        style = "padding:3px 0; display:flex; align-items:center; gap:7px; cursor:pointer;",
        htmltools::tags$span(class = "ci-icon", icon),
        htmltools::tags$span(class = "ci-label", style = "flex:1; font-size:0.78rem;", label),
        if (!is.null(count) && count > 0L)
          htmltools::tags$span(
            class = "ci-count",
            style = "font-size:0.7rem; background:var(--bs-tertiary-bg, #f8f9fa); border-radius:3px; padding:0 4px; color:var(--bs-secondary-color, #6c757d);",
            count
          )
      )
    }

    htmltools::tags$div(
      class = "ca-customizations",
      make_row("✨", "Skills",  n_skills),
      make_row("🔧", "Tools",   n_tools),
      make_row("🪝", "Hooks",   n_hooks),
      make_row("🔌", "MCP",     NULL)
    )
  })

  shiny::observeEvent(input$perm_mode, {
    settings$permission_mode <<- input$perm_mode
    tryCatch(.register_all_tools(chat, settings), error = function(e) NULL)
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$btw_groups_input, {
    tryCatch(
      register_r_tools(chat, groups = input$btw_groups_input),
      error = function(e) NULL)
  }, ignoreInit = TRUE)

  # Model switch — Route A (in-place provider swap) keeps the SAME Chat object,
  # so the chat captured by every other server module stays valid. We swap the
  # provider directly rather than calling switch_model() (which may return a NEW
  # client via Route B) to guarantee the Chat identity is preserved in Shiny.
  shiny::observeEvent(input$model_select, ignoreInit = TRUE, {
    new_spec <- input$model_select
    if (is.null(new_spec) || !nzchar(new_spec)) return()
    if (identical(new_spec, settings$model)) return()

    if (!is.null(stream_task) && stream_task$status() == "running") {
      tryCatch(bslib::show_toast("Streaming in progress — cannot switch model now.",
                                 type = "warning"),
               error = function(e) shiny::showNotification(
                 "Streaming in progress; cannot switch model.", type = "warning"))
      return()
    }

    ok <- tryCatch({
      new_chat <- .resolve_model_chat(new_spec, cwd)
      if (!.swap_provider(chat, new_chat))
        stop("in-place provider swap unavailable")
      settings$model <<- tryCatch(new_chat$get_model(), error = function(e) new_spec)
      TRUE
    }, error = function(e) {
      tryCatch(bslib::show_toast(paste0("Model switch failed: ", conditionMessage(e)),
                                 type = "error"),
               error = function(e2) shiny::showNotification(
                 paste0("Model switch failed: ", conditionMessage(e)), type = "error"))
      FALSE
    })

    if (ok) {
      tryCatch(bslib::show_toast(sprintf("Switched to %s — history preserved.",
                                         settings$model), type = "success"),
               error = function(e) shiny::showNotification(
                 sprintf("Switched to %s.", settings$model), type = "message"))
    }
  })
}
