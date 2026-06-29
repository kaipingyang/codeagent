#!/usr/bin/env Rscript
# inst/examples/test_picker_bslib.R
# Minimal test: pickerInput with groups + subtext inside bslib page

library(shiny)
library(bslib)
library(shinyWidgets)

`%||%` <- function(x, y) if (is.null(x) || !nzchar(x)) y else x

# Load skill meta
skill_df <- tryCatch({
  devtools::load_all(quiet = TRUE)
  metas <- codeagent:::list_skills_meta()
  data.frame(
    key   = vapply(metas, `[[`, character(1), "name"),
    label = paste0("/", vapply(metas, `[[`, character(1), "name")),
    desc  = vapply(metas, function(m) m$description %||% "", character(1)),
    stringsAsFactors = FALSE
  )
}, error = function(e) {
  data.frame(
    key   = c("plan", "compact", "verify", "simplify"),
    label = c("/plan", "/compact", "/verify", "/simplify"),
    desc  = c("Break work into steps", "Make replies denser",
              "Verify the last action", "Simplify the last code"),
    stringsAsFactors = FALSE
  )
})

ui <- page_fluid(
  theme = bs_theme(version = 5),

  # Card 1a: subtext only (no groups) — direct from gallery
  card(
    card_header("pickerInput: subtext (no groups)"),
    card_body(
      pickerInput(
        inputId    = "pick_cars",
        label      = "Car model",
        choices    = rownames(mtcars),
        choicesOpt = list(
          subtext = paste("mpg:", mtcars$mpg)
        ),
        options = pickerOptions(liveSearch = TRUE, showSubtext = FALSE,
                                size = 10, container = "body"),
        width = "100%"
      ),
      verbatimTextOutput("res_cars")
    )
  ),

  # Card 1b: groups + subtext combined
  # Key: choicesOpt length must equal sum(lengths(choices)), in flattened order
  card(
    card_header("pickerInput: groups + subtext"),
    card_body({
      car_groups <- list(
        "4 cyl" = rownames(mtcars)[mtcars$cyl == 4],
        "6 cyl" = rownames(mtcars)[mtcars$cyl == 6],
        "8 cyl" = rownames(mtcars)[mtcars$cyl == 8]
      )
      flat_cars    <- unlist(car_groups, use.names = FALSE)
      flat_subtext <- paste("mpg:", mtcars[flat_cars, "mpg"])
      pickerInput(
        inputId    = "pick_cars_grp",
        label      = "Cars by cylinder (grouped)",
        choices    = car_groups,
        choicesOpt = list(subtext = flat_subtext),
        options    = pickerOptions(liveSearch = TRUE, showSubtext = FALSE,
                                   size = 10, container = "body"),
        width = "100%"
      )
    }),
    verbatimTextOutput("res_cars_grp")
  ),

  # Card 2: skills
  card(
    card_header("pickerInput: skills + descriptions"),
    card_body(
      pickerInput(
        inputId    = "pick_skill",
        label      = "Choose a skill",
        choices    = list(
          "Slash Commands" = stats::setNames(skill_df$key, skill_df$label)
        ),
        choicesOpt = list(
          subtext = skill_df$desc,
          tokens  = paste(skill_df$key, skill_df$desc)
        ),
        options = pickerOptions(
          liveSearch            = TRUE,
          liveSearchPlaceholder = "Search skills…",
          noneSelectedText      = "Select a skill",
          showSubtext           = FALSE,
          size                  = 10,
          container             = "body"
        ),
        width = "100%"
      ),
      verbatimTextOutput("res_skill")
    )
  )
)

server <- function(input, output, session) {
  output$res_cars     <- renderPrint(input$pick_cars)
  output$res_cars_grp <- renderPrint(input$pick_cars_grp)
  output$res_skill    <- renderPrint(input$pick_skill)
}

shinyApp(ui, server)
