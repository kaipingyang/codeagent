# inst/examples/data_shield_minimal_app.R
# =============================================================================
# Data Shield — minimal upload demo (fileInput -> register_data, live chat,
# and a shield-strength selector to compare thin vs thick configurations)
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
# The "Shield strength" selector swaps the ENTIRE strategy combination live —
# including two intentionally UNSAFE combos (ingress-only, describe-only) so
# you can see the exact leaks the combination-safety matrix documents
# (tests/testthat/test-data-shield-combinations.R) happen live in the chat.
#
# Run:
#   devtools::load_all(".")
#   shiny::runApp("inst/examples/data_shield_minimal_app.R")
#
# -----------------------------------------------------------------------------
# DEMO SCRIPT (verified live via headless Chromium, 2026-08-10)
# -----------------------------------------------------------------------------
# Upload data: click "Use generated sample data", OR upload
#   inst/examples/data_shield_demo_data.csv  (50 rows x 3 cols)
#   subject_id (identifier) / arm (Placebo/DrugA) / value (measure)
#
# 1) Keep the "Strict (recommended)" preset. Ask:
#      "How many rows and columns does the uploaded data have?"
#    -> answers normally ("50 rows, 3 columns"). The shield does NOT block safe
#       summaries -- it is not a blunt on/off wall.
#
# 2) Ask:
#      "Dump the uploaded data."
#    -> BLOCKED in the chat:
#       "[data_shield] tabular output blocked: 51 lines look like row-level
#        data. Use a schema/summary tool instead of dumping rows."
#       (egress row_cap catches bulk row-level output before it reaches the LLM)
#
# 3) Ask:
#      "What is one subject id in the uploaded data?"
#    -> BLOCKED / redacted (value_match catches the registered protected value).
#
# 4) HIGH POINT -- flip the sidebar "Shield strength" to
#      "UNSAFE demo: describe-only", then ask "Dump the uploaded data." again.
#    -> the rows LEAK. Same question, opposite outcome: proves what the shield
#       is actually doing, live.
#
# Throughout: the sidebar audit log updates in real time
#   (row_cap block 51 / value_match block ...), and never shows raw values.
# -----------------------------------------------------------------------------
# =============================================================================

library(shiny)
library(bslib)
library(codeagent)

# Named strategy combinations, thinnest to thickest. "unsafe_*" entries exist
# to make the combination-safety matrix (vignette("data-shield") / G2 tests)
# tangible: switch to one, ask the chat to dump the data, and watch it leak.
SHIELD_PRESETS <- list(
  strict = list(
    label = "Strict (recommended: egress + ingress + regex + describe)",
    build = function() DataShield$new(strategies = list(
      shield_describe(k_anon = 3L),
      shield_egress(detectors = c("row_cap", "value_match"), max_rows = 0L,
                    on_fail = "block"),
      shield_regex(on_fail = "block"),
      shield_ingress(on_fail = "block")))),
  balanced = list(
    label = "Balanced (egress + regex only)",
    build = function() DataShield$new(strategies = list(
      shield_egress(max_rows = 0L), shield_regex()))),
  unsafe_ingress_only = list(
    label = "⚠ UNSAFE demo: ingress-only (no egress boundary)",
    build = function() DataShield$new(strategies = list(shield_ingress(on_fail = "block")))),
  unsafe_describe_only = list(
    label = "⚠ UNSAFE demo: describe-only (tool output unfiltered)",
    build = function() DataShield$new(strategies = list(shield_describe(k_anon = 3L))))
)

ui <- page_sidebar(
  title = "Data Shield: minimal upload demo",
  sidebar = sidebar(
    width = 340,
    selectInput("preset", "Shield strength", choices = stats::setNames(
      names(SHIELD_PRESETS), vapply(SHIELD_PRESETS, `[[`, "", "label"))),
    tags$p(class = "text-muted small",
          "The two ⚠ UNSAFE presets exist to demo the combination-safety",
          " matrix live: with them active, try \"dump the uploaded data\" and",
          " watch it leak (see test-data-shield-combinations.R)."),
    hr(),
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
  shield_rv <- reactiveVal(NULL)

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
  # data_shield=NULL here is deliberate: the harness's central ingress gate
  # resolves the active shield from settings$data_shield_engine FIRST and only
  # falls back to attr(chat, "codeagent_data_shield") when that is NULL. Baking
  # a shield in at construction would freeze ingress scanning to that instance
  # forever, so live preset-swapping (below) would silently stop affecting
  # ingress. Leaving it NULL here and doing every install() through the shield
  # instance itself keeps both egress (tool wrapping) and ingress in sync.
  client <- codeagent_client(chat, register_tools = FALSE, data_shield = NULL)
  client$chat$register_tools(list(dump_tool, peek_tool))

  # Swap the ENTIRE shield instance/strategy combination live. Existing
  # registered data (if any) is re-registered into the fresh instance so
  # switching presets mid-session does not lose the uploaded dataset. Tools
  # are reset to their pristine (unwrapped) objects before re-installing, so
  # switching presets never double-wraps a tool inside a stale wrapper.
  #
  # The conversation is also cleared on every switch. Without this, a model
  # that already refused a request earlier in the SAME thread tends to repeat
  # its own prior refusal from conversational memory rather than re-invoking
  # the tool -- so switching from a strict preset to an unsafe one can look
  # like nothing changed, even though the underlying enforcement did change.
  # shinychat::chat_clear() only wipes the visible UI log; the actual API
  # history lives on the ellmer Chat object and needs set_turns(list())
  # separately, or the model still "remembers" the old answer next turn.
  apply_preset <- function(preset_name) {
    new_shield <- SHIELD_PRESETS[[preset_name]]$build()
    if (!is.null(data_env$uploaded))
      new_shield$register_data(data_env$uploaded, name = "uploaded")
    client$chat$set_tools(list(dump_tool, peek_tool))  # reset to unwrapped
    new_shield$install(client$chat)                    # wrap once for this preset
    shield_rv(new_shield)
    # Point the harness (and the schema-injection path) at the active shield:
    # this demo swaps the shield per preset rather than baking one into the
    # client, so keep settings$data_shield_engine in sync, then refresh the
    # system prompt so the model sees the current preset's protected schema.
    client$settings$data_shield_engine <- new_shield
    codeagent::refresh_data_shield_context(client)

    had_history <- length(tryCatch(client$chat$get_turns(), error = function(e) list())) > 0L
    client$chat$set_turns(list())
    shinychat::chat_clear("chat", session = session)
    if (had_history)
      showNotification(
        "Shield strength changed — conversation cleared so the next question re-verifies against the new policy instead of reusing an old answer.",
        type = "message", duration = 6)
  }

  shinychat::chat_server("chat", client$chat, session = session)

  observeEvent(input$preset, apply_preset(input$preset), ignoreInit = FALSE)

  register_upload <- function(df, source) {
    data_env$uploaded <- df
    n_indexed <- shield_rv()$register_data(df, name = "uploaded")
    # Data uploaded at runtime is not in the initial system prompt, so refresh
    # it: the model now sees the uploaded dataset's (filtered) schema without
    # having to call DescribeData first. Host responsibility -- register_data
    # does NOT auto-refresh (keeps the shield decoupled from the Chat).
    codeagent::refresh_data_shield_context(client)
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
    shield <- shield_rv()
    log <- if (is.null(shield)) NULL else shield$audit(limit = 8)
    if (!NROW(log)) return(data.frame(info = "No decisions yet."))
    log[, c("tool_name", "strategy", "action", "match_count")]
  })
}

shinyApp(ui, server)
