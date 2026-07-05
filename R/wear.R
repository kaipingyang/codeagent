#' @title WEAR Loop Data Exploration
#' @description Implements Databot's WEAR loop (Write/Execute/Analyze/Regroup)
#'   for interactive data exploration. Each cycle: the agent writes dplyr/R
#'   code, executes it via `ExploreData`, analyzes the result, then proposes
#'   3-5 next steps for the user to choose from.
#'
#'   Use `/report` in the chat to export the session to a Quarto document.
#' @name wear_loop
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# WEAR loop system prompt injection
# ---------------------------------------------------------------------------

# System prompt extension for data exploration mode.
# Injected via codeagent_client(system_prompt_extra=) or a dedicated skill.
.WEAR_SYSTEM_PROMPT <- paste0(
  "## Data Exploration Mode (WEAR loop)\n\n",
  "You are in interactive data exploration mode. For each question:\n\n",
  "1. **W - Write**: Generate dplyr/base R code to answer the question.\n",
  "2. **E - Execute**: Call `ExploreData(data_name=..., code=...)` to run it.\n",
  "3. **A - Analyze**: Interpret the output. Note unexpected findings, ",
  "outliers, or interesting patterns.\n",
  "4. **R - Regroup**: End EVERY response with exactly this section:\n\n",
  "---\n",
  "**Next steps** (pick one or describe your own):\n",
  "1. [suggested follow-up 1]\n",
  "2. [suggested follow-up 2]\n",
  "3. [suggested follow-up 3]\n\n",
  "Always use `ExploreData` rather than `RunR` for data queries -- it is ",
  "read-only and cannot modify your data.\n",
  "When the user types `/report`, call `generate_wear_report()` to export ",
  "the session to a Quarto document."
)

# ---------------------------------------------------------------------------
# WEAR loop entry point
# ---------------------------------------------------------------------------

#' Start a WEAR loop data exploration session
#'
#' Launches an **interactive** data exploration session using the
#' Write/Execute/Analyze/Regroup (WEAR) loop pattern. This is a **dedicated
#' exploration mode** -- it is separate from a normal `codeagent_app()` or
#' `codeagent_console()` session. The difference:
#'
#' | Normal session | WEAR session (`wear_explore()`) |
#' |---|---|
#' | No data registered by default | `data=` argument registers named data.frames |
#' | No `GenerateReport` tool | `/report` exports session to `.qmd` |
#' | No WEAR system prompt | Agent instructed to end each turn with **Next steps** |
#' | General-purpose tools | `ExploreData` tool added (read-only, sandboxed) |
#'
#' The `ExploreData` and `GenerateReport` tools are **not** registered in the
#' standard agent loop (`codeagent_app()`) -- use `wear_explore()` to enter
#' exploration mode explicitly.
#'
#' @param data Named list, environment, or `NULL`. Data.frames to make
#'   available for exploration. If `NULL`, uses objects in `.GlobalEnv`.
#'   A named list is converted to an environment automatically.
#' @param client A `CodagentClient` (from [codeagent_client()]). If `NULL`,
#'   one is built from `~/.codeagent/settings.json` with `permission_mode =
#'   "bypass"`.
#' @param mode Character. `"repl"` (default) starts an interactive CLI session;
#'   `"shiny"` launches the Shiny app.
#' @param ... Passed to [codeagent_console()] or [codeagent_app()].
#' @return Invisibly the `CodagentClient` (useful for post-session inspection
#'   or calling [generate_wear_report()] manually).
#' @seealso [generate_wear_report()] to export the session to a Quarto document.
#' @examples
#' \dontrun{
#' # Explore mtcars from the CLI (requires a configured LLM client)
#' wear_explore(data = list(mtcars = mtcars))
#'
#' # Shiny UI with multiple data.frames
#' wear_explore(
#'   data = list(sales = sales_df, products = products_df),
#'   mode = "shiny"
#' )
#'
#' # Capture the client to export the report afterwards
#' client <- wear_explore(data = list(mtcars = mtcars))
#' generate_wear_report(client, title = "Motor Trend Analysis")
#' }
#' @export
wear_explore <- function(data = NULL, client = NULL, mode = c("repl", "shiny"), ...) {
  mode <- match.arg(mode)

  # Build or augment the client
  if (is.null(client)) client <- codeagent_client(permission_mode = "bypass")

  # Register ExploreData with the provided data sources
  envir <- if (is.null(data)) .GlobalEnv
           else if (is.environment(data)) data
           else list2env(as.list(data), parent = .GlobalEnv)
  register_explore_data_tool(client$chat, envir = envir)

  # Register the /report command as a WEAR report generator
  register_wear_report_tool(client$chat)

  # Inject WEAR system prompt hint into the chat
  current_sp <- tryCatch(client$chat$get_system_prompt(), error = function(e) "")
  if (!grepl("WEAR loop", current_sp)) {
    new_sp <- paste0(current_sp, "\n\n", .WEAR_SYSTEM_PROMPT)
    tryCatch(client$chat$set_system_prompt(new_sp), error = function(e) NULL)
  }

  # Announce available data.frames
  df_names <- ls(envir = envir)[vapply(ls(envir = envir),
    function(x) is.data.frame(get(x, envir = envir)), logical(1))]
  if (length(df_names)) {
    cli::cli_bullets(c(
      "i" = "Data exploration mode (WEAR loop)",
      "i" = paste0("Available data: ", paste0("{.val ", df_names, "}", collapse = ", ")),
      "i" = "Type {.code /report} to export to Quarto."
    ))
  }

  switch(mode,
    repl  = codeagent_console(client, ...),
    shiny = codeagent_app(client, ...)
  )
  invisible(client)
}

# ---------------------------------------------------------------------------
# WEAR report: export session to Quarto
# ---------------------------------------------------------------------------

#' Export the current WEAR exploration session to a Quarto document
#'
#' Generates a reproducible `.qmd` file from the conversation history of a
#' [wear_explore()] session. Each user message becomes a `##` section heading;
#' assistant text is written as prose; code from `ExploreData` tool results is
#' written as `\`\`\`{r}` chunks.
#'
#' The `.qmd` has `eval: false` by default so it renders without re-running the
#' LLM queries. Set `eval: true` in the YAML front-matter to make it fully
#' reproducible.
#'
#' This function is also registered as the `GenerateReport` tool inside a
#' [wear_explore()] session, so the agent can call it when the user types
#' `/report`.
#'
#' @param client A `CodagentClient` whose `chat` has been used in a
#'   [wear_explore()] session.
#' @param path Character. Output file path (default: `exploration-YYYYMMDD.qmd`
#'   in the current directory).
#' @param title Character. Quarto document title.
#' @return Invisibly the path to the generated `.qmd` file.
#' @seealso [wear_explore()] to start a WEAR exploration session.
#' @examples
#' \dontrun{
#' # After a wear_explore() session:
#' client <- wear_explore(data = list(mtcars = mtcars))
#'
#' # Export to a named file
#' path <- generate_wear_report(client,
#'   path  = "mtcars-analysis.qmd",
#'   title = "Motor Trend Analysis")
#'
#' # Render with quarto CLI
#' system(paste("quarto render", path))
#' # Or: quarto::quarto_render(path)  # if quarto R package is installed
#' }
#' @export
generate_wear_report <- function(client,
                                  path  = paste0("exploration-",
                                                  format(Sys.Date(), "%Y%m%d"), ".qmd"),
                                  title = "Data Exploration Report") {
  turns <- tryCatch(client$chat$get_turns(), error = function(e) list())
  if (!length(turns)) cli::cli_abort("No conversation history to export.")

  # Build QMD content
  lines <- c(
    "---",
    paste0('title: "', title, '"'),
    paste0('date: "', format(Sys.Date(), "%Y-%m-%d"), '"'),
    "format:",
    "  html:",
    "    code-fold: true",
    "    toc: true",
    "execute:",
    "  echo: true",
    "  eval: false",
    "---",
    "",
    paste0("> Generated by codeagent WEAR loop on ", format(Sys.time()), "\n"),
    ""
  )

  for (turn in turns) {
    role     <- tryCatch(turn@role, error = function(e) "unknown")
    contents <- tryCatch(turn@contents, error = function(e) list())
    for (ct in contents) {
      cls <- class(ct)[1L]
      if (grepl("ContentText", cls)) {
        txt <- tryCatch(ct@text, error = function(e) "")
        if (nzchar(txt)) {
          if (identical(role, "user")) {
            lines <- c(lines, paste0("## ", txt), "")
          } else {
            lines <- c(lines, txt, "")
          }
        }
      } else if (grepl("ContentToolResult", cls)) {
        # Extract code from tool result if available
        code <- tryCatch(ct@extra$code, error = function(e) NULL)
        val  <- tryCatch(as.character(ct@value), error = function(e) "")
        if (!is.null(code) && nzchar(code)) {
          lines <- c(lines, "```{r}", code, "```", "")
        }
        if (nzchar(val) && !grepl("^\\[", val)) {
          lines <- c(lines, paste0("> ", gsub("\n", "\n> ", val)), "")
        }
      }
    }
  }

  writeLines(lines, path)
  cli::cli_alert_success("Report written to {.file {path}}")
  cli::cli_text("Render with: {.code quarto::quarto_render('{path}')}")
  invisible(path)
}

# ---------------------------------------------------------------------------
# WEAR report tool (registers /report as an agent-callable tool)
# ---------------------------------------------------------------------------

#' Register the WEAR report generation tool on a Chat
#' @param chat An `ellmer::Chat` object.
#' @return Invisibly `chat`.
#' @keywords internal
register_wear_report_tool <- function(chat) {
  # The tool captures the chat by reference so it can read turns at call time
  force(chat)
  t <- ellmer::tool(
    fun = function(title = NULL, path = NULL) {
      out_path <- path %||%
        paste0("exploration-", format(Sys.Date(), "%Y%m%d"), ".qmd")
      # Build a mock client-like object the report generator can use
      fake_client <- list(chat = chat)
      class(fake_client) <- "CodagentClient"
      tryCatch(
        generate_wear_report(fake_client, path = out_path,
                             title = title %||% "Data Exploration Report"),
        error = function(e) paste0("[Error] Report failed: ", conditionMessage(e)))
    },
    description = paste0(
      "Export the current data exploration session to a reproducible Quarto ",
      "document. Call this when the user types /report or asks to save/export ",
      "the analysis."
    ),
    arguments = list(
      title = ellmer::type_string("Document title.", required = FALSE),
      path  = ellmer::type_string("Output file path (.qmd).", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title = "GenerateReport", read_only_hint = FALSE)
  )
  chat$register_tool(t)
  invisible(chat)
}
