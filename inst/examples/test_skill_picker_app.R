# Test app: toolbar footer with grouped skills (documented subtext behavior)
#
# Run with:
#   shiny::runApp("inst/examples/test_skill_picker_app.R")

library(shiny)
library(bslib)
library(shinychat)
library(shinyWidgets)
library(htmltools)

if (file.exists(".Renviron")) {
  readRenviron(".Renviron")
}

devtools::load_all(quiet = TRUE)


`%||%` <- function(x, y) if (is.null(x) || !nzchar(x)) y else x

load_demo_skill_meta <- function() {
  repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  metas <- tryCatch(codeagent:::list_skills_meta(cwd = repo_root), error = function(e) NULL)

  if (is.null(metas) || !length(metas)) {
    return(data.frame(
      group = c("Slash Commands", "Slash Commands"),
      key = c("plan", "compact"),
      label = c("/plan", "/compact"),
      desc = c(
        "Break work into clear, ordered steps",
        "Make replies shorter and denser"
      ),
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    group = rep("Slash Commands", length(metas)),
    key = vapply(metas, `[[`, character(1), "name"),
    label = paste0("/", vapply(metas, `[[`, character(1), "name")),
    desc = vapply(metas, function(meta) meta$description %||% "", character(1)),
    stringsAsFactors = FALSE
  )
}

skill_meta <- load_demo_skill_meta()

group_order <- unique(skill_meta$group)
choice_groups <- lapply(group_order, function(group_name) {
  rows <- skill_meta[skill_meta$group == group_name, , drop = FALSE]
  stats::setNames(rows$key, rows$label)
})
names(choice_groups) <- group_order

picker_footer <- bslib::toolbar(
  width = "100%",
  shinyWidgets::pickerInput(
    inputId = "skill_picker",
    label = NULL,
    choices = choice_groups,
    selected = character(0),
    multiple = FALSE,
    width = "100%",
    choicesOpt = list(
      subtext = skill_meta$desc,
      tokens  = paste(skill_meta$key, skill_meta$label, skill_meta$desc)
    ),
    options = shinyWidgets::pickerOptions(
      liveSearch            = TRUE,
      noneSelectedText      = "请选择skill",
      liveSearchPlaceholder = "搜索 skill 或描述",
      showSubtext           = FALSE,
      size                  = 10,
      container             = "body",
      width                 = "100%"
    )
  )
)

ui <- page_fillable(
  bslib::card(
    full_screen = FALSE,
    height = "100%",
    shinychat::chat_ui(
      "chat",
      fill = TRUE,
      placeholder = "Enter a message...",
      footer = picker_footer
    )
  )
)

server <- function(input, output, session) {
  session$onFlushed(function() {
    shinyWidgets::updatePickerInput(
      session = session,
      inputId = "skill_picker",
      selected = character(0)
    )
  }, once = TRUE)

  observeEvent(input$skill_picker, ignoreInit = TRUE, {
    req(input$skill_picker)
    shinychat::update_chat_user_input(
      id = "chat",
      value = paste0("/", input$skill_picker, " "),
      focus = TRUE,
      submit = FALSE,
      session = session
    )
  })

  observeEvent(input$chat_user_input, {
    req(nzchar(trimws(input$chat_user_input)))
    shinychat::chat_append(
      id = "chat",
      response = paste("You entered:", input$chat_user_input),
      session = session
    )
  })
}

shinyApp(ui, server)
