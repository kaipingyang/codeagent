#!/usr/bin/env Rscript
# inst/examples/demo_10_genui_canvas.R
#
# Demo: the model generates UI on the Canvas tab (shinygenui components)
#
# The model answers data questions by *drawing*: each canvas tool call mounts a
# live Shiny component (value box, sortable table, scatter plot, histogram,
# markdown note, card_row container) built from a data frame in this R session.
# Two host components show how to add your own:
#   canvas_boxplot     -- base Shiny plotOutput/renderPlot (no extra packages)
#   canvas_line_chart  -- an htmlwidget (plotly), offered only when installed
#
# Requirements:
#   pak::pak(c("nanxstats/shinygenui", "ggplot2", "DT"))   # canvas
#   install.packages("plotly")                              # optional
#   CODEAGENT_BASE_URL / CODEAGENT_MODEL / CODEAGENT_API_KEY in .Renviron
#   (CODEAGENT_BASE_URL unset -> ellmer::chat_anthropic(), ANTHROPIC_API_KEY)
#
# Run from the package root after installing codeagent:
#   Rscript inst/examples/demo_10_genui_canvas.R
#
# What to try (the Canvas tab is in the right-hand Output workspace):
#   1. "Build a sales overview: a row of value boxes for total revenue, total
#       units and mean margin, then revenue by month as a line chart."
#   2. "Compare revenue across regions with a box plot, and show the top rows
#       of sales sorted by revenue in a table."
#   3. "Scatter plot of weight against mpg in cars, and a histogram of hp."
#   4. "Change the histogram to 20 bins" / "Remove the table"
#        -> canvas_update / canvas_remove on the existing components
#   5. "Using R, add a region_summary data frame with revenue per region, then
#       draw it as a table."  RunR asks for approval (permission_mode =
#       "default"); after it changes data a component shows, that component
#       gets a "Data changed" badge -- click "Refresh data" on the Canvas tab.
#   6. New / load a saved session in the sidebar: the canvas is restored with
#      the conversation.

required <- c("codeagent", "ellmer", "shiny", "shinygenui", "ggplot2", "DT")
missing <- required[!vapply(required, requireNamespace, logical(1L), quietly = TRUE)]
if (length(missing))
  stop("Missing packages: ", paste(missing, collapse = ", "),
       ". Install with pak::pak(c(\"nanxstats/shinygenui\", \"ggplot2\", \"DT\")).",
       call. = FALSE)

if (file.exists(".Renviron")) readRenviron(".Renviron")
library(codeagent)

# ---------------------------------------------------------------------------
# Step 1: data the canvas can draw from
# ---------------------------------------------------------------------------
# Canvas tools take a `dataset` argument naming a data frame in `data_env`
# (globalenv() by default -- the same place RunR creates objects, so frames the
# model builds with R are drawable too).
set.seed(2026)
sales <- expand.grid(
  month   = 1:12,
  region  = c("North", "South", "East", "West"),
  product = c("Basic", "Plus", "Pro"),
  stringsAsFactors = FALSE)
price <- c(Basic = 20, Plus = 45, Pro = 90)[sales$product]
sales$units   <- as.integer(round(stats::rpois(nrow(sales), 120) *
  (1 + 0.04 * sales$month) * c(North = 1.2, South = 0.8, East = 1, West = 1.1)[sales$region]))
sales$revenue <- round(sales$units * price * stats::runif(nrow(sales), 0.9, 1.1), 2)
sales$margin  <- round(stats::runif(nrow(sales), 0.15, 0.45), 3)
rm(price)

cars <- data.frame(model = rownames(mtcars), mtcars, row.names = NULL)
flowers <- iris

# ---------------------------------------------------------------------------
# Step 2: host components (trusted code, registered as read-only canvas tools)
# ---------------------------------------------------------------------------
has_cols <- function(data, cols) {
  bad <- setdiff(cols, names(data))
  if (length(bad))
    paste0("Unknown column(s): ", paste(bad, collapse = ", "),
           ". Available: ", paste(names(data), collapse = ", "), ".")
}

boxplot_card <- canvas_component_output(
  "boxplot", "Box plot of a numeric column split by a grouping column.",
  args = list(
    y     = ellmer::type_string("Numeric column."),
    by    = ellmer::type_string("Grouping column."),
    title = ellmer::type_string("Heading.", required = FALSE)),
  output = shiny::plotOutput,
  render = function(args, data) shiny::renderPlot(
    graphics::boxplot(stats::reformulate(args$by, args$y), data = data(),
                      main = args$title %||% "", col = "#cfe2ff",
                      xlab = args$by, ylab = args$y)),
  check = function(args, data) {
    msg <- has_cols(data, c(args$y, args$by))
    if (is.null(msg) && !is.numeric(data[[args$y]]))
      msg <- paste0("`", args$y, "` is not numeric.")
    msg
  },
  code = function(args, dataset) sprintf(
    "boxplot(%s ~ %s, data = %s)", args$y, args$by, dataset))

components <- list(boxplot_card)

if (requireNamespace("plotly", quietly = TRUE)) {
  line_chart <- canvas_component_widget(
    "line_chart",
    paste("Interactive line chart. Rows are summed per x value and, when",
          "`color` is given, per group (one line each)."),
    args = list(
      x     = ellmer::type_string("Column on the x axis, e.g. month."),
      y     = ellmer::type_string("Numeric column to sum on the y axis."),
      color = ellmer::type_string("Optional grouping column.", required = FALSE)),
    widget = function(args, data) {
      groups <- c(args$x, args$color)
      agg <- stats::aggregate(data[args$y], by = data[groups], FUN = sum)
      agg <- agg[order(agg[[args$x]]), , drop = FALSE]
      p <- if (is.null(args$color))
        plotly::plot_ly(agg, x = agg[[args$x]], y = agg[[args$y]],
                        type = "scatter", mode = "lines+markers")
      else
        plotly::plot_ly(agg, x = agg[[args$x]], y = agg[[args$y]],
                        color = agg[[args$color]],
                        type = "scatter", mode = "lines+markers")
      plotly::layout(p, xaxis = list(title = args$x),
                     yaxis = list(title = args$y))
    },
    check = function(args, data) {
      msg <- has_cols(data, c(args$x, args$y, args$color))
      if (is.null(msg) && !is.numeric(data[[args$y]]))
        msg <- paste0("`", args$y, "` is not numeric.")
      msg
    })
  components <- c(components, list(line_chart))
}

canvas <- canvas_options(
  components = components,
  starter    = TRUE,          # every shinygenui component, incl. card_row
  data_env   = globalenv())

# ---------------------------------------------------------------------------
# Step 3: tell the model which data exists (CLAUDE.md in the project dir)
# ---------------------------------------------------------------------------
describe <- function(name) {
  df <- get(name, envir = globalenv())
  cols <- vapply(names(df), function(col)
    sprintf("%s (%s)", col, class(df[[col]])[[1L]]), "")
  sprintf("- `%s`: %d rows; columns %s", name, nrow(df), paste(cols, collapse = ", "))
}
project_dir <- file.path(tempdir(), "genui-demo")
dir.create(project_dir, showWarnings = FALSE)
writeLines(c(
  "# GenUI canvas demo",
  "",
  "Answer questions about the data below by drawing on the canvas rather than",
  "printing tables in the chat. Group related components with canvas_card_row",
  "(children pass its id as parent_id). Keep chat replies to one or two",
  "sentences describing what you drew. Modify existing components with",
  "canvas_update instead of drawing duplicates.",
  "",
  "Data frames in the R session:",
  vapply(c("sales", "cars", "flowers"), describe, "")
), file.path(project_dir, "CLAUDE.md"))

# ---------------------------------------------------------------------------
# Step 4: launch
# ---------------------------------------------------------------------------
make_chat <- function() {
  if (nzchar(Sys.getenv("CODEAGENT_BASE_URL"))) {
    ellmer::chat_openai_compatible(
      base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
      model       = Sys.getenv("CODEAGENT_MODEL", "gpt-4.1"),
      credentials = function() Sys.getenv("CODEAGENT_API_KEY"))
  } else {
    ellmer::chat_anthropic()
  }
}

cat("Canvas components:",
    paste(c("value_box", "data_table", "scatter_plot", "histogram",
            "markdown_card", "card_row", vapply(components, `[[`, "", "name")),
          collapse = ", "), "\n")
cat("Project dir:", project_dir, "\nPress Ctrl-C to stop.\n\n")

app <- codeagent_app(
  # A fresh client per browser session: each tab gets its own canvas.
  client_factory = function(session) {
    codeagent_client(
      make_chat(),
      permission_mode = "default",      # RunR asks; canvas tools are read-only
      cwd             = project_dir,
      tools           = c("genui", "run"),
      register_tools  = FALSE)          # registered lazily under the init overlay
  },
  canvas    = canvas,
  ui_layout = Sys.getenv("CODEAGENT_UI_LAYOUT", "classic"),
  greeting  = paste(
    "Build a sales overview: a row of value boxes for total revenue, total",
    "units and mean margin, then revenue by month per region as a line chart.")
)

# codeagent_app() returns a shinyApp; run it explicitly so source() works too.
shiny::runApp(app)
