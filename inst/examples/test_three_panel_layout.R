#!/usr/bin/env Rscript
# inst/examples/test_three_panel_layout.R
#
# Test: three-panel layout — left sidebar + center chat_ui + right sidebar
#
# Run with:  shiny::runApp("inst/examples/test_three_panel_layout.R")

library(shiny)
library(bslib)
library(shinychat)

ui <- page_sidebar(
  fillable = TRUE,
  sidebar = sidebar(
    id        = "left_sidebar",
    width     = 240,
    resizable = TRUE,
    padding   = 12,
    br(),
    card(
      fill = TRUE,
      card_header("Left Panel"),
      card_body(
        p("Sessions, settings, etc.")
      )
    )
  ),
  layout_sidebar(
    fill     = TRUE,
    fillable = TRUE,
    border   = FALSE,
    sidebar  = sidebar(
      id        = "right_sidebar",
      position  = "right",
      width     = "40%",
      resizable = TRUE,
      fillable  = TRUE,
      padding   = 0,
      card(
        fill = TRUE,
        card_header(
          class = "d-flex justify-content-end",
          "Right Panel"
        ),
        card_body(p("Output here."))
      )
    ),
    card(
      fill = TRUE,
      chat_ui("chat", fill = TRUE, placeholder = "Ask something...")
    )
  )
)

server <- function(input, output, session) {}

shinyApp(ui, server)
