#' @title MCP Client (connect to external MCP servers)
#' @description Registers tools exposed by external Model Context Protocol
#'   servers onto a codeagent Chat, via `mcptools::mcp_tools()`. This is the
#'   client side (consuming external tools); `codeagent_mcp_server()` is the
#'   server side (exposing codeagent's tools).
#'
#'   Transport: mcptools launches stdio MCP servers as child processes
#'   (`command` + `args` + `env` per the config). HTTP/SSE servers depend on
#'   mcptools support.
#'
#'   Config format (JSON file or inline list), e.g.:
#'   ```json
#'   {
#'     "mcpServers": {
#'       "filesystem": {
#'         "command": "npx",
#'         "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
#'       }
#'     }
#'   }
#'   ```
#' @name mcp_client
#' @keywords internal
NULL

#' Load tools from external MCP servers
#'
#' @param config Path to an MCP config JSON file, or an inline list with the
#'   same shape. `NULL` uses mcptools' default config location.
#' @return A list of `ellmer::tool()` objects (empty list on failure).
#' @keywords internal
mcp_client_tools <- function(config = NULL) {
  if (!requireNamespace("mcptools", quietly = TRUE)) {
    warning("[codeagent] mcptools not available; MCP client tools skipped.",
            call. = FALSE)
    return(list())
  }
  tryCatch(
    mcptools::mcp_tools(config),
    error = function(e) {
      warning("[codeagent] MCP client failed: ", conditionMessage(e),
              call. = FALSE)
      list()
    }
  )
}

#' Register external MCP server tools onto a Chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param config MCP config (path or inline list). See [mcp_client_tools()].
#' @return Invisibly, the number of tools registered.
#' @export
register_mcp_client <- function(chat, config = NULL) {
  if (is.null(config)) return(invisible(0L))
  tools <- mcp_client_tools(config)
  n <- 0L
  for (t in tools) {
    ok <- tryCatch({ chat$register_tool(t); TRUE }, error = function(e) FALSE)
    if (isTRUE(ok)) n <- n + 1L
  }
  invisible(n)
}
