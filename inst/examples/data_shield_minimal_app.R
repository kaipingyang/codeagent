# inst/examples/data_shield_minimal_app.R
# =============================================================================
# Data Shield — minimal upload demo (single focus: fileInput -> register_data)
# =============================================================================
# A deliberately small companion to data_shield_upload_app.R (which manually
# invokes tools via buttons). This one wires a REAL codeagent_client into a
# REAL shinychat chat_ui, so you can type things like:
#   "dump the uploaded data"
#   "what's one subject id in the data?"
#   "how many rows and columns does the data have?"
# and watch Data Shield withhold/redact the tool results live, with the
# non-sensitive audit log shown in the sidebar as it happens.
#
# Run:
#   devtools::load_all(".")
#   shiny::runApp("inst/examples/data_shield_minimal_app.R")
# =============================================================================

library(shiny)
library(bslib)
library(codeagent)

ui <- page_sidebar(
  title = "Data Shield: minimal upload demo",
  sidebar = sidebar(
    width = 320,
    fileInput("file", "Upload CSV", accept = c(".csv", "text/csv")),
    actionButton("sample", "Use generated sample data", class = "btn-sm"),
    hr(),
    strong("Registered data"),
    verbatimTextOutput("status"),
    hr(),
    strong("Data Shield audit log"),
    tags$p(class = "text-muted small",
          "Non-sensitive: no raw values/rows ever appear here."),
    tableOutput("audit")
  ),
  shinychat::chat_ui("chat", fill = TRUE, allow_attachments = FALSE,
                     placeholder = "Upload data, then ask about it (e.g. \"dump the uploaded data\")")
)

server <- function(input, output, session) {
  # Per-session state: shield, uploaded data, and the Chat all live here.
  data_env <- new.env(parent = emptyenv())
  shield <- DataShield$new(strategies = list(
    shield_describe(k_anon = 3L),
    shield_egress(detectors = c("row_cap", "value_match"), max_rows = 0L),
    shield_regex()))

  dump_tool <- ellmer::tool(
    function() {
      if (is.null(data_env$uploaded)) return("No data uploaded yet.")
      data_env$uploaded                        # bulk rows -> row_cap withholds
    },
    name = "DumpUploadedData",
    description = "Return the complete uploaded dataset.",
    arguments = list())

  peek_tool <- ellmer::tool(
    function() {
      df <- data_env$uploaded
      if (is.null(df)) return("No data uploaded yet.")
      # first high-cardinality value: what register_data() indexes for value_match
      for (nm in names(df)) {
        v <- unique(as.character(df[[nm]][!is.na(df[[nm]])]))
        if (length(v) >= 8L) return(paste("One value in the data is", v[[1L]]))
      }
      "No high-cardinality column found."
    },
    name = "PeekOneValue",
    description = "Return one value from a high-cardinality column in the uploaded data.",
    arguments = list())

  chat <- ellmer::chat_openai_compatible(
    base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
    model       = Sys.getenv("CODEAGENT_MODEL", "gpt-4o-mini"),
    credentials = function() Sys.getenv("CODEAGENT_API_KEY"))
  client <- codeagent_client(chat, register_tools = FALSE, data_shield = shield)
  client$chat$register_tools(list(dump_tool, peek_tool))
  shield$install(client$chat)   # wrap tools; registering data later still applies

  shinychat::chat_server("chat", client$chat, session = session)

  register_upload <- function(df, source) {
    data_env$uploaded <- df
    n_indexed <- shield$register_data(df, name = "uploaded")
    output$status <- renderText(sprintf(
      "Source: %s\nShape: %d x %d\nHigh-entropy values indexed: %d",
      source, nrow(df), ncol(df), n_indexed))
  }

  observeEvent(input$file, {
    req(input$file$datapath)
    df <- tryCatch(
      utils::read.csv(input$file$datapath, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) e)
    if (inherits(df, "error")) {
      showNotification(paste("Upload failed:", conditionMessage(df)), type = "error")
      return()
    }
    register_upload(df, input$file$name)
  })

  observeEvent(input$sample, {
    register_upload(data.frame(
      subject_id = sprintf("SUBJECT%03d", 1:50),
      arm        = rep(c("Placebo", "DrugA"), 25),
      value      = round(seq(10.1, 59.1, length.out = 50), 3),
      stringsAsFactors = FALSE), "generated sample")
  })

  # Cheap live refresh of the non-sensitive audit log while a chat is running.
  output$audit <- renderTable({
    invalidateLater(1000, session)
    log <- shield$audit(limit = 8)
    if (!NROW(log)) return(data.frame(info = "No decisions yet."))
    log[, c("tool_name", "strategy", "action", "match_count")]
  })
}

shinyApp(ui, server)
