#' @title UI Panel Definitions
#' @description Pure UI functions for codeagent_app(). No server logic here.
#' @name ui_panels
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Head assets
# ---------------------------------------------------------------------------

head_assets <- function() {
  htmltools::tags$head(
    htmltools::tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css"
    ),
    # Prism.js -- syntax highlighting for code/diff tool cards
    htmltools::tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism.min.css"
    ),
    htmltools::tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-core.min.js"),
    htmltools::tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/autoloader/prism-autoloader.min.js"),
    htmltools::tags$link(rel = "stylesheet", type = "text/css",
                         href = "codeagent-www/styles.css"),
    htmltools::tags$script(src = "codeagent-www/agent.js"),
    htmltools::tags$script(htmltools::HTML(
      paste(readLines(
        system.file("www/voice.js", package = "codeagent")
      ), collapse = "\n")
    ))
  )
}

# ---------------------------------------------------------------------------
# Skill picker footer -- shared by both chat sidebar variants
# ---------------------------------------------------------------------------

.skill_picker_footer <- function(skill_meta) {
  # NOTE: The skill pickerInput was removed in favour of shinychat's official
  # slash-command typeahead (type "/" in the chat input; see R/server_slash.R).
  # The historical pickerInput implementation is archived under
  # inst/experiments/pickerinput_skill_selector/. This footer now only carries
  # the file-upload / voice / server-browse buttons.
  htmltools::tags$div(
    class = "d-flex align-items-center gap-1 py-1",

    # NOTE: local file upload is handled by shinychat's native attachment
    # button (chat_ui(allow_attachments = TRUE)) in the input row -- the old
    # custom paperclip button (ca_upload_local_btn + ca_file_hidden) was a
    # duplicate and has been removed.
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
    # Hint that slash commands live in the input now.
    htmltools::tags$span(
      class = "text-muted small ms-1",
      style = "flex:1; min-width:0;",
      "Type / for commands & skills"
    )
  )
}

# ---------------------------------------------------------------------------
# Left sidebar: Sessions + Settings (Skills panel removed -- now in footer)
# ---------------------------------------------------------------------------

left_sidebar_ui <- function(permission_mode, btw_available_groups,
                             btw_groups_selected,
                             model_choices = NULL, current_model = NULL) {
  htmltools::tagList(
    # Light/dark toggle (Bootstrap 5 color mode). input_code_editor and bslib
    # components follow data-bs-theme automatically.
    htmltools::tags$div(
      class = "d-flex justify-content-end mb-1",
      bslib::input_dark_mode(id = "ca_dark_mode")
    ),
    # Active model as a toolbar select -- switch model in one click (was a
    # read-only badge + a duplicate selectInput buried in Settings). Reuses the
    # "model_select" input id, so the existing server observer handles it.
    if (length(model_choices) > 0L) {
      bslib::toolbar(
        class = "ca-model-toolbar mb-2",
        bslib::toolbar_input_select(
          "model_select", label = "Model",
          choices = model_choices, selected = current_model,
          show_label = FALSE, icon = shiny::icon("robot"),
          tooltip = "Switch model -- history preserved"
        )
      )
    } else {
      htmltools::tags$div(
        class = "ca-model-badge text-muted mb-2",
        style = "font-size:.8rem;",
        htmltools::tags$i(class = "fa fa-robot me-1"),
        "Model: ",
        htmltools::tags$span(id = "ca-current-model", current_model %||% "(auto)")
      )
    },
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
        htmltools::tags$div(
          class = "d-flex gap-2 mb-2",
          shiny::actionButton("new_session", "New",
            class = "btn-outline-secondary btn-sm flex-fill"),
          shiny::actionButton("delete_session_btn", "Delete",
            class = "btn-outline-danger btn-sm flex-fill")
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
          }
        )
      )
    ),

    htmltools::tags$div(
      class = "ca-footer mt-auto",
      "codeagent v0.1.0 - ESC to interrupt"
    )
  )
}

left_sidebar_ui_default <- left_sidebar_ui


# ---------------------------------------------------------------------------
# Chat sidebar -- chat_ui with skill picker + file/voice footer
# ---------------------------------------------------------------------------

chat_codeagent_ui <- function(skill_meta) {
  shinychat::chat_ui(
    "chat",
    fill             = TRUE,
    enable_cancel    = TRUE,
    placeholder      = "Ask codeagent... (/ for skills, ESC to interrupt)",
    allow_attachments = TRUE,
    # Greeting + clickable suggestion cards for a fresh session. shinychat
    # renders a markdown list whose items are <span class="suggestion"> as a
    # grid of clickable cards; clicking submits the card's text.
    messages = list(
      paste0(
        "**codeagent** -- an R-native coding agent on ellmer + btw. ",
        "Ask anything about this project, or start here:\n\n",
        "- <span class=\"suggestion\">List the R files in the R/ directory</span>\n",
        "- <span class=\"suggestion\">Read DESCRIPTION and summarize this package</span>\n",
        "- <span class=\"suggestion\">Run the test suite and report failures</span>\n",
        "- <span class=\"suggestion\" title=\"Plan\">/plan add a new feature</span>\n"
      )
    ),
    footer           = htmltools::tagList(
      # Phase 3 interaction bar (approval / question) sits just above the
      # skill picker + input area; rendered on demand by server_interaction().
      shiny::uiOutput("ca_interaction_ui"),
      .skill_picker_footer(skill_meta)
    )
  )
}


# ---------------------------------------------------------------------------
# Main output panel (right, largest area)
# ---------------------------------------------------------------------------

output_panel_ui <- function() {
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
