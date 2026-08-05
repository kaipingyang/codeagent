# =============================================================================
# Data Shield P0/P0.5 --- runtime upload demo (Shiny host pattern)
# =============================================================================
# Demonstrates the common case where the dataset is not known until a user
# uploads it. The host reads the file locally, stores it in a per-session env,
# and immediately calls register_protected_data(df, shield = shield). No column
# list is required.
#
# The tools are registered + wrapped ONCE at session startup. Their closures
# read the latest uploaded data from `data_env`; protected values may be
# registered later, after any number of uploads.
#
# MULTI-USER SAFE: every Shiny server session creates its own DataShieldState,
# data environment and Chat. Multiple chat threads in that browser session may
# share the state; other browser sessions cannot see or influence its index.
#
# Run from the repository:
#   devtools::load_all(".")
#   source("inst/examples/data_shield_upload_app.R")
# Or reinstall, RESTART R, then source(system.file(..., package="codeagent")).
# =============================================================================

library(shiny)
library(codeagent)

stopifnot(
  "install_data_shield()" = exists("install_data_shield"),
  "register_protected_data()" = exists("register_protected_data")
)

# Get a registered ellmer ToolDef by its model-facing name.
.demo_get_tool <- function(chat, name) {
  tools <- chat$get_tools()
  if (!is.null(tools[[name]])) return(tools[[name]])
  for (tool in tools) {
    tool_name <- tryCatch(S7::prop(tool, "name"), error = function(e) "")
    if (identical(tool_name, name)) return(tool)
  }
  NULL
}

# Choose one value that register_protected_data() will index: a value from a
# sufficiently high-cardinality column, at least 3 chars, not a small integer.
.demo_indexable_value <- function(df, min_card = 8L) {
  for (name in names(df)) {
    values <- unique(df[[name]][!is.na(df[[name]])])
    if (length(values) < min_card) next
    values <- as.character(values)
    values <- values[nchar(values) >= 3L & !grepl("^[0-9]{1,2}$", values)]
    if (length(values)) return(values[[1L]])
  }
  NULL
}

ui <- fluidPage(
  titlePanel("Data Shield: runtime upload demo"),
  tags$p(
    "Upload a CSV. Registration happens after upload, without knowing its columns in advance. ",
    "The app then invokes three local tools through the shield."
  ),
  fileInput("file", "Upload CSV", accept = c(".csv", "text/csv")),
  actionButton("sample", "Use generated sample data"),
  tags$hr(),
  verbatimTextOutput("status"),
  actionButton("test", "Run shield tests", class = "btn-primary"),
  verbatimTextOutput("result")
)

server <- function(input, output, session) {
  # Per-user state: both the data and its protected-value index live inside
  # this Shiny server session (never package-global).
  data_env <- new.env(parent = emptyenv())
  shield <- data_shield(max_rows = 0L)
  state <- reactiveValues(
    data = NULL,
    source = NULL,
    indexed = 0L,
    result = "Upload a CSV (or generate sample data), then run the tests."
  )

  # A provider is not needed: we invoke tools locally in this demo. The Chat is
  # only the standard ellmer registry that Data Shield wraps.
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://127.0.0.1:1", model = "demo",
    credentials = function() "demo")

  dump_tool <- ellmer::tool(
    function() {
      if (is.null(data_env$uploaded)) return("No data uploaded.")
      data_env$uploaded                       # bulk row-level return -> row_cap
    },
    name = "DumpUploadedData",
    description = "Return the complete uploaded dataset.",
    arguments = list()
  )

  leak_tool <- ellmer::tool(
    function() {
      if (is.null(data_env$uploaded)) return("No data uploaded.")
      value <- .demo_indexable_value(data_env$uploaded)
      if (is.null(value)) return("No indexable high-entropy value was found.")
      paste("One uploaded value is", value) # short targeted leak -> value_match
    },
    name = "LeakOneUploadedValue",
    description = "Return one high-cardinality value from the uploaded dataset.",
    arguments = list()
  )

  shape_tool <- ellmer::tool(
    function() {
      if (is.null(data_env$uploaded)) return("No data uploaded.")
      sprintf("Uploaded data has %d rows and %d columns.",
              nrow(data_env$uploaded), ncol(data_env$uploaded))
    },
    name = "DescribeUploadShape",
    description = "Return only the row and column counts.",
    arguments = list()
  )

  chat$register_tools(list(dump_tool, leak_tool, shape_tool))
  install_data_shield(chat, shield = shield) # wrap once; index may be added later

  register_upload <- function(df, source) {
    stopifnot(is.data.frame(df))
    data_env$uploaded <- df
    state$data <- df
    state$source <- source
    # Runtime registration: no advance knowledge of names/types is required.
    state$indexed <- register_protected_data(df, shield = shield)
    state$result <- "Registered. Click 'Run shield tests'."
  }

  observeEvent(input$file, {
    req(input$file$datapath)
    df <- tryCatch(
      utils::read.csv(input$file$datapath, stringsAsFactors = FALSE,
                      check.names = FALSE),
      error = function(e) e
    )
    if (inherits(df, "error")) {
      state$result <- paste("Upload failed:", conditionMessage(df))
      return()
    }
    register_upload(df, input$file$name)
  })

  observeEvent(input$sample, {
    sample_df <- data.frame(
      subject_id = sprintf("SUBJECT%03d", 1:50),
      arm = rep(c("Placebo", "DrugA"), 25),
      value = round(seq(10.1, 59.1, length.out = 50), 3),
      stringsAsFactors = FALSE
    )
    register_upload(sample_df, "generated sample")
  })

  output$status <- renderText({
    if (is.null(state$data)) return("No data registered.")
    sprintf("Source: %s\nShape: %d x %d\nProtected high-entropy values indexed: %d",
            state$source, nrow(state$data), ncol(state$data), state$indexed)
  })

  observeEvent(input$test, {
    req(state$data)
    dump_result <- .demo_get_tool(chat, "DumpUploadedData")()
    leak_result <- .demo_get_tool(chat, "LeakOneUploadedValue")()
    shape_result <- .demo_get_tool(chat, "DescribeUploadShape")()

    state$result <- paste(
      "1) Bulk dump (row_cap should withhold):",
      paste0("   ", substr(as.character(dump_result), 1L, 160L)),
      "",
      "2) One protected value (value_match should withhold):",
      paste0("   ", substr(as.character(leak_result), 1L, 160L)),
      "",
      "3) Harmless aggregate/shape (should pass):",
      paste0("   ", as.character(shape_result)),
      sep = "\n"
    )
  })

  output$result <- renderText(state$result)

  # Exposed only to shiny::testServer(); not needed by the app UI.
  session$userData$data_shield_demo <- list(state = state, data_env = data_env,
                                             chat = chat, shield = shield)
}

app <- shinyApp(ui, server)
if (interactive()) runApp(app)
