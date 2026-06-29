#' @title Customizations Modal UIs
#' @description One function per customization category. Each returns a
#'   modalDialog() ready to pass to showModal(). Keep them independent.
#' @name ui_customizations
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Customizations sidebar row — shared clickable row in left panel
# ---------------------------------------------------------------------------

customization_row_ui <- function(input_id, icon_name, label, count = NULL) {
  htmltools::tags$div(
    class  = "custom-item d-flex align-items-center gap-2 py-1 px-1",
    style  = "cursor:pointer; font-size:0.8rem; border-radius:4px;",
    onclick = sprintf(
      "Shiny.setInputValue('%s', Date.now(), {priority:'event'});", input_id
    ),
    shiny::icon(icon_name, class = "fa-fw ci-icon",
                style = "opacity:0.6; font-size:0.8rem; width:14px;"),
    htmltools::tags$span(class = "ci-label flex-fill", label),
    if (!is.null(count))
      shiny::uiOutput(paste0(input_id, "_badge"), inline = TRUE)
  )
}

# Helper: count badge span
.count_badge <- function(n) {
  if (is.null(n) || n == 0L) return(NULL)
  htmltools::tags$span(
    class = "badge bg-secondary",
    style = "font-size:0.65rem; font-weight:500;",
    n
  )
}

# ---------------------------------------------------------------------------
# 1. Agents modal
# ---------------------------------------------------------------------------

modal_agents_ui <- function(agent_list) {
  shiny::modalDialog(
    title = shiny::tagList(shiny::icon("robot"), " Agents"),
    size  = "l",
    easyClose = TRUE,
    footer = shiny::tagList(
      shiny::actionButton("agent_new_btn", "New Agent",
                          class = "btn-primary btn-sm"),
      shiny::modalButton("Close")
    ),
    if (length(agent_list) == 0L) {
      htmltools::tags$p(
        class = "text-muted fst-italic",
        "No agents defined. Agents live in .claude/agents/*.md or .btw/agent-*.md"
      )
    } else {
      htmltools::tags$div(
        class = "list-group list-group-flush",
        lapply(agent_list, function(a) {
          htmltools::tags$div(
            class = "list-group-item d-flex align-items-start gap-2 py-2",
            shiny::icon("robot", style = "margin-top:2px; opacity:0.5;"),
            htmltools::tags$div(
              htmltools::tags$strong(a$name),
              htmltools::tags$div(
                class = "text-muted small",
                a$description %||% ""
              ),
              if (!is.null(a$model))
                htmltools::tags$span(
                  class = "badge bg-light text-dark border small mt-1",
                  a$model
                )
            )
          )
        })
      )
    }
  )
}

# ---------------------------------------------------------------------------
# 2. Skills modal
# ---------------------------------------------------------------------------

modal_skills_ui <- function(skill_list) {
  shiny::modalDialog(
    title = shiny::tagList(shiny::icon("bolt"), " Skills"),
    size  = "l",
    easyClose = TRUE,
    footer = shiny::tagList(
      shiny::actionButton("install_skill_btn", "Install Skill",
                          class = "btn-primary btn-sm"),
      shiny::modalButton("Close")
    ),
    if (length(skill_list) == 0L) {
      htmltools::tags$p(class = "text-muted fst-italic", "No skills found.")
    } else {
      htmltools::tags$div(
        class = "list-group list-group-flush",
        lapply(skill_list, function(s) {
          htmltools::tags$div(
            class = "list-group-item d-flex align-items-start gap-2 py-2",
            shiny::icon("bolt", style = "margin-top:2px; opacity:0.5; color:var(--bs-warning, #f59e0b);"),
            htmltools::tags$div(
              class = "flex-fill",
              htmltools::tags$code(paste0("/", s$name)),
              htmltools::tags$div(class = "text-muted small", s$description %||% "")
            )
          )
        })
      )
    }
  )
}

# ---------------------------------------------------------------------------
# 3. Instructions modal
# ---------------------------------------------------------------------------

modal_instructions_ui <- function(instruction_files) {
  shiny::modalDialog(
    title = shiny::tagList(shiny::icon("file-lines"), " Instructions"),
    size  = "l",
    easyClose = TRUE,
    footer = shiny::tagList(
      shiny::actionButton("instruction_new_btn", "New Instruction",
                          class = "btn-primary btn-sm"),
      shiny::modalButton("Close")
    ),
    htmltools::tags$p(
      class = "text-muted small mb-2",
      "Persistent rules injected every session (like CLAUDE.md)."
    ),
    if (length(instruction_files) == 0L) {
      htmltools::tags$p(
        class = "text-muted fst-italic",
        "No instruction files found. Create .claude/instructions.md or CLAUDE.md."
      )
    } else {
      htmltools::tags$div(
        class = "list-group list-group-flush",
        lapply(instruction_files, function(f) {
          htmltools::tags$div(
            class = "list-group-item d-flex align-items-center gap-2 py-2",
            shiny::icon("file-lines", style = "opacity:0.5;"),
            htmltools::tags$span(class = "flex-fill", f$path),
            htmltools::tags$span(
              class = if (f$active) "badge bg-success" else "badge bg-secondary",
              if (f$active) "active" else "disabled"
            )
          )
        })
      )
    }
  )
}

# ---------------------------------------------------------------------------
# 4. Hooks modal
# ---------------------------------------------------------------------------

modal_hooks_ui <- function(hook_list) {
  event_order <- c("SessionStart", "UserPromptSubmit", "PreToolUse",
                   "PostToolUse", "PostToolUseFailure", "PermissionDenied",
                   "AssistantMessage", "Stop")
  shiny::modalDialog(
    title = shiny::tagList(shiny::icon("plug"), " Hooks"),
    size  = "l",
    easyClose = TRUE,
    footer = shiny::modalButton("Close"),
    htmltools::tags$p(
      class = "text-muted small mb-2",
      "Shell commands run automatically at lifecycle events."
    ),
    if (length(hook_list) == 0L) {
      htmltools::tags$p(
        class = "text-muted fst-italic",
        "No hooks registered. Configure in ~/.claude/settings.json hooks section."
      )
    } else {
      htmltools::tags$div(
        lapply(event_order, function(evt) {
          items <- Filter(function(h) h$event == evt, hook_list)
          if (length(items) == 0L) return(NULL)
          htmltools::tagList(
            htmltools::tags$div(
              class = "fw-semibold small text-muted mt-2 mb-1",
              style = "text-transform:uppercase; font-size:0.68rem; letter-spacing:.05em;",
              evt
            ),
            lapply(items, function(h) {
              htmltools::tags$div(
                class = "list-group-item font-monospace small py-1",
                style = "font-size:0.75rem;",
                h$command
              )
            })
          )
        })
      )
    }
  )
}

# ---------------------------------------------------------------------------
# 5. MCP Servers modal
# ---------------------------------------------------------------------------

modal_mcp_ui <- function(mcp_list) {
  shiny::modalDialog(
    title = shiny::tagList(shiny::icon("server"), " MCP Servers"),
    size  = "l",
    easyClose = TRUE,
    footer = shiny::tagList(
      shiny::actionButton("mcp_add_btn", "Add Server",
                          class = "btn-primary btn-sm"),
      shiny::modalButton("Close")
    ),
    if (length(mcp_list) == 0L) {
      htmltools::tags$p(
        class = "text-muted fst-italic",
        "No MCP servers configured. Add to mcp.json or use btw::btw_mcp_server()."
      )
    } else {
      htmltools::tags$div(
        class = "list-group list-group-flush",
        lapply(mcp_list, function(m) {
          htmltools::tags$div(
            class = "list-group-item d-flex align-items-center gap-2 py-2",
            shiny::icon("server", style = "opacity:0.5;"),
            htmltools::tags$div(
              class = "flex-fill",
              htmltools::tags$strong(m$name),
              htmltools::tags$div(
                class = "text-muted small font-monospace",
                m$command %||% m$url %||% ""
              )
            ),
            htmltools::tags$span(
              class = if (identical(m$status, "connected"))
                "badge bg-success" else "badge bg-secondary",
              m$status %||% "unknown"
            )
          )
        })
      )
    }
  )
}

# ---------------------------------------------------------------------------
# 6. Plugins modal
# ---------------------------------------------------------------------------

modal_plugins_ui <- function(plugin_list) {
  shiny::modalDialog(
    title = shiny::tagList(shiny::icon("puzzle-piece"), " Plugins"),
    size  = "l",
    easyClose = TRUE,
    footer = shiny::tagList(
      shiny::actionButton("plugin_install_btn", "Install Plugin",
                          class = "btn-primary btn-sm"),
      shiny::modalButton("Close")
    ),
    htmltools::tags$p(
      class = "text-muted small mb-2",
      "Plugins bundle Skills + Instructions + Hooks + MCP into one installable unit."
    ),
    if (length(plugin_list) == 0L) {
      htmltools::tags$p(
        class = "text-muted fst-italic",
        "No plugins installed."
      )
    } else {
      htmltools::tags$div(
        class = "list-group list-group-flush",
        lapply(plugin_list, function(p) {
          htmltools::tags$div(
            class = "list-group-item d-flex align-items-start gap-2 py-2",
            shiny::icon("puzzle-piece", style = "margin-top:2px; opacity:0.5;"),
            htmltools::tags$div(
              htmltools::tags$strong(p$name),
              htmltools::tags$span(
                class = "text-muted small ms-1",
                p$version %||% ""
              ),
              htmltools::tags$div(class = "text-muted small", p$description %||% "")
            )
          )
        })
      )
    }
  )
}
