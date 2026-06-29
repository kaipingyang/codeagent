#' @title UI Panel Definitions
#' @description Pure UI functions for codeagent_app(). No server logic here.
#' @name ui_panels
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Head assets
# ---------------------------------------------------------------------------

head_assets <- function(theme) {
  base <- htmltools::tagList(
    htmltools::tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css"
    ),
    htmltools::tags$link(rel = "stylesheet", type = "text/css",
                         href = "codeagent-www/styles.css"),
    htmltools::tags$script(src = "codeagent-www/voice.js"),
    htmltools::tags$script(src = "codeagent-www/agent.js")
  )

  if (identical(theme, "default")) {
    return(htmltools::tags$head(base))
  }

  htmltools::tags$head(
    base,
    htmltools::tags$script(htmltools::HTML(sprintf(
      'document.documentElement.setAttribute("data-theme", "%s");', theme
    )))
  )
}

# ---------------------------------------------------------------------------
# Skill picker footer — shared by both chat sidebar variants
# ---------------------------------------------------------------------------

.skill_picker_footer <- function(skill_meta) {
  skill_choices <- list(
    "Slash Commands" = stats::setNames(skill_meta$key, skill_meta$label)
  )
  htmltools::tags$div(
    class = "d-flex align-items-center gap-1 py-1",

    # Hidden file input
    htmltools::tags$input(
      type   = "file",
      id     = "ca_file_hidden",
      style  = "display:none;",
      accept = ".pdf,.txt,.csv,.R,.Rmd,.md,.docx,.xlsx,.png,.jpg"
    ),
    shiny::actionButton("ca_upload_local_btn", NULL,
      icon  = shiny::icon("paperclip"),
      class = "btn-outline-secondary btn-sm flex-shrink-0",
      title = "Upload local file"),
    shiny::actionButton("ca_voice_btn", NULL,
      icon  = shiny::icon("microphone"),
      class = "btn-outline-secondary btn-sm flex-shrink-0",
      title = "Voice input"),
    shinyFiles::shinyFilesButton(
      "ca_server_btn",
      label    = NULL,
      title    = "Browse server files",
      icon     = shiny::icon("server"),
      class    = "btn-outline-secondary btn-sm flex-shrink-0",
      multiple = FALSE),
    htmltools::tags$div(
      style = "flex:1; min-width:0;",
      shinyWidgets::pickerInput(
      inputId    = "skill_picker",
      label      = NULL,
      choices    = skill_choices,
      selected   = character(0),
      multiple   = FALSE,
      width      = "100%",
      choicesOpt = list(
        subtext = skill_meta$desc,
        tokens  = paste(skill_meta$key, skill_meta$desc)
      ),
      options = shinyWidgets::pickerOptions(
        liveSearch            = TRUE,
        noneSelectedText      = "Select a skill...",
        liveSearchPlaceholder = "Search skills...",
        showSubtext           = FALSE,
        size                  = 8,
        container             = "body",
        width                 = "100%"
      )
    )
    )   # close flex:1 div
  )     # close outer flex row
}

# ---------------------------------------------------------------------------
# Left sidebar: Sessions + Settings (Skills panel removed — now in footer)
# ---------------------------------------------------------------------------

left_sidebar_ui <- function(permission_mode, btw_available_groups,
                             btw_groups_selected) {
  htmltools::tagList(
    # Token budget bar
    htmltools::tags$div(
      class = "ca-budget-wrap",
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

    bslib::accordion(
      id       = "ca_left_accordion",
      class    = "ca-sidebar-accordion",
      multiple = TRUE,
      open     = "Sessions",

      bslib::accordion_panel(
        title = "Sessions",
        value = "Sessions",
        bslib::toolbar(
          gap = "0.5rem",
          bslib::toolbar_input_button(
            "new_session", "New", border = TRUE,
            class = "ca-session-action-btn primary btn-sm"
          ),
          bslib::toolbar_input_button(
            "save_session_btn", "Save", border = TRUE,
            class = "ca-session-action-btn btn-sm"
          )
        ),
        shiny::uiOutput("session_list_ui")
      ),

      bslib::accordion_panel(
        title = "Customizations",
        value = "Customizations",
        htmltools::tags$div(
          customization_row_ui("ca_open_agents",       "robot",        "Agents"),
          customization_row_ui("ca_open_skills",       "bolt",         "Skills"),
          customization_row_ui("ca_open_instructions", "file-lines",   "Instructions"),
          customization_row_ui("ca_open_hooks",        "plug",         "Hooks"),
          customization_row_ui("ca_open_mcp",          "server",       "MCP Servers"),
          customization_row_ui("ca_open_plugins",      "puzzle-piece", "Plugins")
        )
      ),

      bslib::accordion_panel(
        title = "Settings",
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
            choices  = c("Default" = "default",
                         "Flatly"  = "flatly",
                         "Darkly"  = "darkly",
                         "Glass"   = "glass"),
            selected = "default",
            width    = "100%")
        )
      )
    ),

    htmltools::tags$div(
      class = "ca-footer mt-auto",
      "codeagent v0.1.0 · ESC to interrupt"
    )
  )
}

left_sidebar_ui_default <- left_sidebar_ui


# ---------------------------------------------------------------------------
# Chat sidebar — chat_ui with skill picker + file/voice footer
# ---------------------------------------------------------------------------

chat_sidebar_ui <- function(skill_meta) {
  shinychat::chat_ui(
    "chat",
    fill          = TRUE,
    enable_cancel = TRUE,
    placeholder   = "Ask codeagent… (/ for skills, ESC to interrupt)",
    footer        = .skill_picker_footer(skill_meta)
  )
}

chat_sidebar_ui_default <- function(skill_meta) {
  shinychat::chat_ui(
    "chat",
    fill          = TRUE,
    enable_cancel = TRUE,
    placeholder   = "Ask codeagent…",
    footer        = .skill_picker_footer(skill_meta)
  )
}

# chat_sidebar_ui_default is an alias kept for back-compat
chat_sidebar_ui_default <- chat_sidebar_ui

# ---------------------------------------------------------------------------
# Main output panel (right, largest area)
# ---------------------------------------------------------------------------

main_output_ui <- function() {
  bslib::navset_tab(
      id       = "main_tab",
      selected = "output",
      bslib::nav_panel(
        title = "Output",
        value = "output",
        htmltools::tags$div(
          class = "ca-output-panel",
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
        jsTreeR::treeNavigatorUI("file_tree", height = "calc(100vh - 120px)")
      )
    )
}
