#' @title UI Panel Definitions
#' @description Pure UI functions for codeagent_app(). No server logic here.
#' @name ui_panels
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Head assets
# ---------------------------------------------------------------------------

head_assets <- function(theme) {
  htmltools::tags$head(
    htmltools::tags$link(rel = "stylesheet", type = "text/css",
                         href = "codeagent-www/styles.css"),
    htmltools::tags$script(src = "codeagent-www/agent.js"),
    htmltools::tags$script(htmltools::HTML(sprintf(
      'document.documentElement.setAttribute("data-theme", "%s");', theme
    )))
  )
}

# ---------------------------------------------------------------------------
# Left sidebar: Sessions + Customizations
# ---------------------------------------------------------------------------

left_sidebar_ui <- function(permission_mode, btw_available_groups,
                             btw_groups_selected) {
  bslib::sidebar(
    id       = "ca_left_sidebar",
    width    = 240,
    resizable = TRUE,
    padding  = 0,

    # Token budget bar
    htmltools::tags$div(
      class = "ca-budget-wrap",
      style = "padding:8px 10px 4px;",
      htmltools::tags$div(
        class = "ca-budget-label",
        htmltools::tags$span("Context"),
        htmltools::tags$span(id = "token-budget-text", "0 tokens")
      ),
      htmltools::tags$div(
        class = "token-budget-bar",
        htmltools::tags$div(class = "token-budget-bar-fill", style = "width:0%")
      )
    ),

    # Accordion: Sessions / Skills / Customizations
    bslib::accordion(
      id       = "ca_left_accordion",
      class    = "ca-sidebar-accordion",
      multiple = TRUE,
      open     = "Sessions",

      # ── Sessions ──────────────────────────────────────────────────────────
      bslib::accordion_panel(
        title = "Sessions",
        value = "Sessions",
        htmltools::tags$div(
          class = "d-flex gap-1 mb-2",
          shiny::actionButton("new_session", "New",
            class = "ca-session-action-btn primary flex-fill btn-sm"),
          shiny::actionButton("save_session_btn", "Save",
            class = "ca-session-action-btn flex-fill btn-sm")
        ),
        shiny::uiOutput("session_list_ui")
      ),

      # ── Skills ────────────────────────────────────────────────────────────
      bslib::accordion_panel(
        title = "⚡ Skills",
        value = "Skills",
        shiny::textInput("skill_search", NULL,
          placeholder = "Search skills…", width = "100%") |>
          htmltools::tagAppendAttributes(class = "ca-skill-search"),
        htmltools::tags$div(
          class = "ca-skill-scroll",
          shiny::uiOutput("skill_list_ui")
        ),
        htmltools::tags$hr(
          style = "border-color:var(--ca-border); margin:10px 0 6px;"),
        shiny::actionButton("install_skill_btn", "+ Install skill",
          class = "ca-session-action-btn w-100 btn-sm")
      ),

      # ── Customizations ────────────────────────────────────────────────────
      bslib::accordion_panel(
        title = "⚙️ Settings",
        value = "Settings",
        htmltools::tags$div(
          class = "ca-settings",
          htmltools::tags$span("Permission mode", class = "ca-settings-label"),
          shiny::selectInput("perm_mode", NULL,
            choices  = unlist(PermissionMode),
            selected = permission_mode,
            width    = "100%"),
          if (length(btw_available_groups) > 0L) {
            htmltools::tagList(
              htmltools::tags$span("btw tools", class = "ca-settings-label"),
              shiny::checkboxGroupInput(
                "btw_groups_input", NULL,
                choices  = btw_available_groups,
                selected = btw_groups_selected %||% btw_available_groups,
                inline   = FALSE)
            )
          },
          htmltools::tags$span("Theme", class = "ca-settings-label"),
          shiny::selectInput("theme_select", NULL,
            choices  = c("Light" = "light",
                         "Glassmorphism" = "glassmorphism",
                         "Dark" = "dark"),
            selected = "light",
            width    = "100%")
        )
      )
    ),

    # Footer
    htmltools::tags$div(
      class = "ca-footer",
      "codeagent v0.1.0 · ESC to interrupt"
    )
  )
}

# ---------------------------------------------------------------------------
# Chat sidebar (right-of-left, position="left" in inner layout)
# ---------------------------------------------------------------------------

chat_sidebar_ui <- function() {
  bslib::sidebar(
    id        = "ca_chat_sidebar",
    width     = 420,
    resizable = TRUE,
    padding   = 0,
    position  = "left",
    shinychat::chat_ui(
      "chat",
      fill        = TRUE,
      placeholder = "Ask codeagent… (/ for skills, ESC to interrupt)"
    )
  )
}

# ---------------------------------------------------------------------------
# Main output panel (right, largest area)
# ---------------------------------------------------------------------------

main_output_ui <- function() {
  htmltools::tags$div(
    class = "ca-main-output",
    style = "height:100%; display:flex; flex-direction:column; overflow:hidden;",
    bslib::navset_tab(
      id = "main_tab",
      selected = "output",
      bslib::nav_panel(
        title = "Output",
        value = "output",
        htmltools::tags$div(
          class = "ca-output-panel",
          style = "flex:1; overflow:auto; padding:0;",
          htmltools::tags$div(
            id    = "ca_immediate_area",
            style = "display:none;"
          ),
          shiny::uiOutput("main_output")
        )
      ),
      bslib::nav_panel(
        title = "Files",
        value = "files",
        jsTreeR::treeNavigatorUI("file_tree", height = "100%")
      )
    )
  )
}
