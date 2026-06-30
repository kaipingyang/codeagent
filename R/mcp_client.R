#' @title MCP Client (connect to external MCP servers)
#' @description Registers tools exposed by external Model Context Protocol
#'   servers onto a codeagent Chat, via `mcptools::mcp_tools()`. This is the
#'   client side (consuming external tools); `codeagent_mcp_server()` is the
#'   server side (exposing codeagent's tools).
#'
#'   Transport: mcptools (>= 0.2.1) launches stdio MCP servers as child
#'   processes (`command` + `args` + `env` per the config) on the **client**
#'   side. Remote HTTP/SSE *client* connections are not yet supported upstream
#'   (mcptools `mcp_tools()` is stdio-only); codeagent can however *serve* over
#'   HTTP -- see [codeagent_mcp_server()] with `transport = "http"`.
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

# ---------------------------------------------------------------------------
# Auto-connect MCP servers declared in settings.json
# ---------------------------------------------------------------------------

#' Auto-connect MCP servers from settings / project config
#'
#' Connects external MCP servers without an explicit `mcp_config` argument, by
#' looking (in order) at:
#' 1. `settings$mcpServers` / `settings$mcp_servers` -- an inline server map in
#'    settings.json.
#' 2. a project-level `.mcp.json` / `.codeagent/mcp.json` file.
#'
#' `enabled_mcp_json_servers` / `disabled_mcp_json_servers` (Claude Code schema)
#' filter which named servers are connected. Servers already provided via the
#' `mcp_config` parameter to [codeagent_client()] are handled separately and not
#' duplicated here.
#'
#' @param chat An `ellmer::Chat` object.
#' @param settings List from [load_settings()].
#' @return Invisibly, the number of tools registered.
#' @keywords internal
.mcp_autoconnect <- function(chat, settings) {
  servers <- settings$mcpServers %||% settings$mcp_servers %||% NULL

  # Fall back to a project-level mcp config file.
  if (is.null(servers)) {
    cwd <- settings$cwd %||% getwd()
    for (cand in c(file.path(cwd, ".mcp.json"),
                   file.path(cwd, ".codeagent", "mcp.json"))) {
      if (file.exists(cand)) {
        cfg <- tryCatch(jsonlite::fromJSON(cand, simplifyVector = FALSE),
                        error = function(e) NULL)
        servers <- cfg$mcpServers %||% cfg
        break
      }
    }
  }
  if (!is.list(servers) || !length(servers)) return(invisible(0L))

  # allow / deny filters (Claude Code schema).
  enabled  <- settings$enabled_mcp_json_servers  %||% character(0)
  disabled <- settings$disabled_mcp_json_servers %||% character(0)
  nms <- names(servers)
  if (length(enabled))  servers <- servers[nms %in% enabled]
  if (length(disabled)) servers <- servers[!names(servers) %in% disabled]
  if (!length(servers)) return(invisible(0L))

  tryCatch(register_mcp_client(chat, list(mcpServers = servers)),
           error = function(e) invisible(0L))
}
