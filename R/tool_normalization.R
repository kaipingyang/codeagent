# Tool result normalization at the execution boundary. This runs inside the
# ToolDef before ellmer inspects the return value, avoiding complex-return
# deprecation warnings while preserving already-normalized Content objects.

.is_ellmer_content <- function(x) {
  tryCatch(S7::S7_inherits(x, ellmer::Content), error = function(e) FALSE)
}

.tool_output_json_safe <- function(value) {
  if (is.function(value) || is.environment(value) || is.language(value) ||
      typeof(value) %in% c("externalptr", "weakref")) return(FALSE)
  if (is.list(value))
    return(all(vapply(value, .tool_output_json_safe, logical(1L))))
  is.atomic(value) || is.null(value)
}

.normalize_tool_output <- function(value) {
  if (promises::is.promise(value))
    return(promises::then(value, .normalize_tool_output,
                          onRejected = function(e) {
                            paste0("[Error] Tool returned a rejected promise: ",
                                   conditionMessage(e))
                          }))
  if (.is_ellmer_content(value)) return(.encode_tool_result_value(value))
  if (is.list(value) && length(value) &&
      all(vapply(value, .is_ellmer_content, logical(1L)))) return(value)
  if (!is.list(value) && !is.data.frame(value)) return(value)

  encoded <- if (!.tool_output_json_safe(value)) NULL else tryCatch(
    jsonlite::toJSON(value, auto_unbox = TRUE, dataframe = "rows",
                     null = "null", na = "null", digits = NA, POSIXt = "ISO8601"),
    error = function(e) NULL)
  if (is.null(encoded))
    return(.artifact_tool_result(
      "[Error] Tool returned a complex value that could not be safely serialized.",
      kind = "error", status = "error", icon = "exclamation-triangle",
      title = "Tool result unavailable",
      payload = list(message = "Complex tool result could not be serialized.")))

  text <- as.character(encoded)
  if (is.data.frame(value)) {
    return(.artifact_tool_result(
      text, kind = "table", icon = "table", title = "Table result",
      payload = list(df = value), value_preview = .tool_display_preview(text)))
  }
  .artifact_tool_result(
    text, kind = "text", icon = "braces", title = "Structured result",
    payload = list(text = text), value_preview = .tool_display_preview(text))
}

# A ContentToolResult whose @value is a list / data frame / vector reaches the
# provider as-is. Some providers reject that: ellmer >= 0.5 sends it as a JSON
# *object* in an OpenAI-compatible tool message, which the API answers with
# HTTP 400 ("expected one of a string or array of objects"). Encode such a
# value to one JSON string here, keeping `extra` (display, artifact) intact.
# Strings, scalars and Content values pass through unchanged.
.encode_tool_result_value <- function(result) {
  is_result <- tryCatch(S7::S7_inherits(result, ellmer::ContentToolResult),
                        error = function(e) FALSE)
  if (!isTRUE(is_result)) return(result)
  value <- result@value
  if (is.null(value) || is.character(value) || .is_ellmer_content(value))
    return(result)
  if (!is.list(value) && !is.data.frame(value) && length(value) <= 1L)
    return(result)
  encoded <- if (!.tool_output_json_safe(value)) NULL else tryCatch(
    jsonlite::toJSON(value, auto_unbox = TRUE, dataframe = "rows",
                     null = "null", na = "null", digits = NA, POSIXt = "ISO8601"),
    error = function(e) NULL)
  # Not JSON-serializable (an R table, an S4 slot, a function...): fall back to
  # its printed form rather than passing the list through. A non-string value
  # is what the provider rejects, and Data Shield's egress scan only reads a
  # single string, so passing it through would also skip the scan.
  result@value <- if (is.null(encoded)) .tool_value_printed(value) else
    as.character(encoded)
  result
}

.tool_value_printed <- function(value, max_chars = 20000L) {
  text <- tryCatch(paste(utils::capture.output(print(value)), collapse = "\n"),
                   error = function(e) "[unprintable tool result value]")
  if (nchar(text) > max_chars)
    text <- paste0(substr(text, 1L, max_chars), "\n[... truncated]")
  text
}

.normalize_tool_def_result <- function(tool) {
  current <- tryCatch(S7::S7_data(tool), error = function(e) NULL)
  if (!is.function(current)) return(tool)
  current_env <- tryCatch(environment(current), error = function(e) NULL)
  state <- if (is.environment(current_env))
    get0(".codeagent_result_normalizer", current_env, inherits = FALSE) else NULL
  if (isTRUE(state)) return(tool)
  original <- if (is.environment(current_env))
    get0(".codeagent_result_original", current_env,
         inherits = FALSE, ifnotfound = current) else current

  wrapped <- function(...) .normalize_tool_output(do.call(original, list(...)))
  assign(".codeagent_result_normalizer", TRUE, envir = environment(wrapped))
  assign(".codeagent_result_original", original, envir = environment(wrapped))
  ok <- tryCatch({ S7::S7_data(tool) <- wrapped; TRUE }, error = function(e) FALSE)
  if (!isTRUE(ok))
    stop("tool result normalizer could not wrap a ToolDef.", call. = FALSE)
  tool
}

.install_tool_result_normalizers <- function(chat) {
  tools <- tryCatch(chat$get_tools(), error = function(e) NULL)
  if (is.null(tools))
    stop("tool result normalizer could not read the tool snapshot.", call. = FALSE)
  if (!length(tools)) return(invisible(chat))
  normalized <- lapply(tools, .normalize_tool_def_result)
  ok <- tryCatch({ chat$set_tools(normalized); TRUE }, error = function(e) FALSE)
  if (!isTRUE(ok))
    stop("tool result normalizer could not update the tool snapshot.", call. = FALSE)
  invisible(chat)
}
