#!/usr/bin/env Rscript

library(codeagent)

shiny::runApp(codeagent_app(ui_layout = "page_chat"))
