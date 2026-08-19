.stream_is_running <- function(stream_task) {
  !is.null(stream_task) &&
    identical(tryCatch(stream_task$status(), error = function(e) ""), "running")
}

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
      make_row("\u2728", "Skills",  n_skills),
      make_row("\U0001f527", "Tools",   n_tools),
      make_row("\U0001fa9d", "Hooks",   n_hooks),
      make_row("\U0001f50c", "MCP",     NULL)
    )
  })

  # Re-install the Data Shield egress wrapper after ANY tool re-registration
  # (kiro round-2 #5). .register_all_tools / register_r_tools replace ToolDefs on
  # the Chat, but the shield's egress filtering lives in a per-tool wrapper that
  # install() applies to the current get_tools() snapshot. New/replaced tools
  # have no wrapper, so their output would reach the model unfiltered until the
  # shield is re-installed. Failure is surfaced (toast), never silently swallowed
  # -- a UI running with the shield off is a security regression, not a no-op.
  reinstall_shield <- function() {
    shield <- settings$data_shield_engine %||%
      tryCatch(attr(chat, "codeagent_data_shield"), error = function(e) NULL)
    if (!inherits(shield, "DataShield")) return(invisible())
    ok <- tryCatch({ shield$install(chat); TRUE }, error = function(e) FALSE)
    if (!isTRUE(ok))
      .ui_toast("Data Shield re-install failed after tool refresh -- output filtering may be OFF.",
                "error")
  }

  shiny::observeEvent(input$perm_mode, {
    if (.stream_is_running(stream_task)) {
      .ui_toast("Permission mode cannot change while a response is running.", "warning")
      return()
    }
    settings$permission_mode <<- input$perm_mode
    ok <- tryCatch({ .register_all_tools(chat, settings); TRUE }, error = function(e) FALSE)
    if (!isTRUE(ok))
      .ui_toast("Tool re-registration failed after permission-mode change.", "warning")
    reinstall_shield()
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$btw_groups_input, {
    if (.stream_is_running(stream_task)) {
      .ui_toast("Tool groups cannot change while a response is running.", "warning")
      return()
    }
    result <- .replace_btw_tool_groups(chat, input$btw_groups_input, settings)
    if (isTRUE(result$ok)) {
      settings$btw_groups <<- input$btw_groups_input
      .ui_toast("btw tool groups updated.", "message")
      return()
    }
    .ui_toast(result$message %||% "btw tool-group update failed.",
              if (isTRUE(result$fatal)) "error" else "warning")
    if (isTRUE(result$fatal))
      session$sendCustomMessage("ca_input_busy", list(busy = TRUE))
  }, ignoreInit = TRUE, ignoreNULL = FALSE)
  # Model switch -- Route A (in-place provider swap) keeps the SAME Chat object,
  # so the chat captured by every other server module stays valid. We swap the
  # provider directly rather than calling switch_model() (which may return a NEW
  # client via Route B) to guarantee the Chat identity is preserved in Shiny.
  shiny::observeEvent(input$model_select, ignoreInit = TRUE, {
    new_spec <- input$model_select
    if (is.null(new_spec) || !nzchar(new_spec)) return()
    if (identical(new_spec, settings$model)) return()

    running <- !is.null(stream_task) &&
      identical(tryCatch(stream_task$status(), error = function(e) ""), "running")
    result <- .shiny_switch_model(chat, settings, new_spec, cwd, running)
    if (isTRUE(result$ok)) settings$model <<- result$model
    .ui_toast(result$message, result$type)
  })
}
