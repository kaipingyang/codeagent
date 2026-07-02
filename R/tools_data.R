#' @title Data Exploration Tool
#' @description An ellmer tool that lets the agent answer natural-language
#'   questions about data.frames in the user's R session. The agent generates
#'   dplyr/base R code to answer the question, executes it in a sandboxed
#'   sub-environment, and returns the result as a formatted table.
#'
#'   Unlike the general RunR tool (which runs arbitrary code), `explore_data`
#'   is scoped to read-only queries on a named data.frame. It never modifies
#'   the source data.
#' @name tools_data
#' @keywords internal
NULL

#' Create the ExploreData tool
#'
#' @param envir Environment from which to read data.frames.
#'   Defaults to `.GlobalEnv`.
#' @return An `ellmer::tool()` object.
#' @export
explore_data_tool <- function(envir = .GlobalEnv) {
  force(envir)
  ellmer::tool(
    fun = function(data_name, question, code = NULL) {
      # Resolve the data.frame
      df <- tryCatch(get(data_name, envir = envir, inherits = TRUE),
                     error = function(e) NULL)
      if (is.null(df))
        return(.tool_result2(
          sprintf("[Error] Object '%s' not found in the R session.", data_name),
          kind = "error", icon = "table",
          title = sprintf("ExploreData -- '%s' not found", data_name),
          payload = list(message = sprintf("'%s' not found.", data_name))))

      if (!is.data.frame(df))
        return(.tool_result2(
          sprintf("[Error] '%s' is not a data.frame (%s).", data_name, class(df)[1L]),
          kind = "error", icon = "table",
          title = sprintf("ExploreData -- '%s' is not a data.frame", data_name),
          payload = list(message = sprintf("'%s' is %s, not a data.frame.", data_name, class(df)[1L]))))

      # If the agent provided code, run it; otherwise return a schema summary
      # so the agent can generate code on the next turn.
      if (!is.null(code) && nzchar(code)) {
        result <- tryCatch({
          exec_env <- new.env(parent = envir)
          assign(data_name, df, envir = exec_env)
          val <- eval(parse(text = code), envir = exec_env)
          val
        }, error = function(e) {
          structure(conditionMessage(e), class = "explore_error")
        })

        if (inherits(result, "explore_error")) {
          return(.tool_result2(
            paste0("[Error] ", as.character(result)),
            kind = "error", icon = "table",
            title = sprintf("ExploreData '%s' -- error", data_name),
            payload = list(message = as.character(result))))
        }

        # Render result: data.frame -> table, scalar -> text
        if (is.data.frame(result)) {
          value <- sprintf("[%d x %d result]", nrow(result), ncol(result))
          .tool_result2(value, kind = "table", icon = "table",
                        title = sprintf("ExploreData: %s", question %||% data_name),
                        payload = list(df = result))
        } else {
          txt <- tryCatch(paste(utils::capture.output(print(result)), collapse = "\n"),
                          error = function(e) as.character(result))
          .tool_result2(txt, kind = "text", icon = "table",
                        title = sprintf("ExploreData: %s", question %||% data_name),
                        payload = list(text = txt))
        }
      } else {
        # No code yet: return schema so the agent can plan the query
        schema <- .df_schema(df, data_name)
        .tool_result2(schema, kind = "text", icon = "table",
                      title = sprintf("ExploreData: schema for '%s'", data_name),
                      payload = list(text = schema))
      }
    },
    name = "ExploreData",
    description = paste0(
      "Answer natural-language questions about a data.frame in the R session. ",
      "First call with only data_name to get the schema, then call again with ",
      "dplyr/base R code to execute the query. Never modifies the source data. ",
      "Use for: filtering, aggregating, summarising, counting, finding patterns."
    ),
    arguments = list(
      data_name = ellmer::type_string(
        "Name of the data.frame in the R session.", required = TRUE),
      question  = ellmer::type_string(
        "The natural-language question to answer.", required = FALSE),
      code      = ellmer::type_string(
        paste0("dplyr/base R code to evaluate. The data.frame is available as ",
               "`data_name`. Return a data.frame or scalar. If NULL, returns schema."),
        required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "ExploreData",
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint  = FALSE
    )
  )
}

#' Register the ExploreData tool on a Chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param envir Environment from which to read data.frames.
#' @return Invisibly `chat`.
#' @export
register_explore_data_tool <- function(chat, envir = .GlobalEnv) {
  chat$register_tool(explore_data_tool(envir))
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Helper: compact data.frame schema string
# ---------------------------------------------------------------------------

.df_schema <- function(df, name = deparse(substitute(df)),
                       max_cols = 30L, sample_vals = 3L) {
  nrow_v <- nrow(df); ncol_v <- ncol(df)
  cols   <- utils::head(names(df), max_cols)
  col_lines <- vapply(cols, function(cn) {
    v   <- df[[cn]]
    cls <- class(v)[1L]
    # Show a few sample values for categorical/character columns
    samples <- if (cls %in% c("character", "factor") && length(v) > 0) {
      uniq <- utils::head(as.character(unique(v[!is.na(v)])), sample_vals)
      paste0(" (e.g. ", paste0('"', uniq, '"', collapse=", "), ")")
    } else ""
    n_na <- sum(is.na(v))
    na_note <- if (n_na > 0) sprintf(" [%d NA]", n_na) else ""
    sprintf("  %-20s %s%s%s", cn, cls, samples, na_note)
  }, character(1))

  extra <- if (ncol_v > max_cols) sprintf("\n  ... and %d more columns", ncol_v - max_cols) else ""
  paste0(
    sprintf("data.frame '%s' -- %d rows x %d columns:\n", name, nrow_v, ncol_v),
    paste(col_lines, collapse = "\n"),
    extra
  )
}
