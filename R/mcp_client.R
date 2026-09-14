#' @title MCP Client (connect to external MCP servers)
#' @description Registers tools exposed by external Model Context Protocol
#'   servers onto a codeagent Chat, via `mcptools::mcp_tools()`. This is the
#'   client side (consuming external tools); `codeagent_mcp_server()` is the
#'   server side (exposing codeagent's tools).
#'
#'   Transport: mcptools (>= 1.0.2.9000) launches stdio MCP servers as child
#'   processes (`command` + `args` + `env`) and connects directly to remote
#'   Streamable HTTP servers configured with `url`. Static headers and MCP OAuth
#'   discovery/PKCE/token refresh are handled upstream by `mcp_tools()`; codeagent
#'   passes the config through without persisting credentials.
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

.MCPTOOLS_MIN_VERSION <- base::package_version("1.0.2.9000")

.mcptools_supported <- function(min_version = .MCPTOOLS_MIN_VERSION) {
  requireNamespace("mcptools", quietly = TRUE) &&
    utils::packageVersion("mcptools") >= min_version
}

.mcptools_assert_server <- function() {
  if (!.mcptools_supported())
    stop("MCP server requires mcptools >= 1.0.2.9000. Install or update mcptools, ",
         "then restart all MCP and R sessions.", call. = FALSE)
  invisible(TRUE)
}

.mcp_loopback_host <- function(host) {
  host <- tolower(trimws(as.character(host %||% "")))
  host %in% c("localhost", "127.0.0.1", "::1", "[::1]")
}

#' Load tools from external MCP servers
#'
#' @param config Path to an MCP config JSON file, or an inline list with the
#'   same shape. `NULL` uses mcptools' default config location.
#' @return A list of `ellmer::tool()` objects (empty list on failure).
#' @keywords internal
mcp_client_tools <- function(config = NULL) {
  if (!.mcptools_supported()) {
    warning("[codeagent] MCP client requires mcptools >= 1.0.2.9000; tools skipped. ",
            "Update mcptools and restart the R session.", call. = FALSE)
    return(list())
  }
  if (is.list(config)) {
    if (!"mcpServers" %in% names(config))
      stop("Inline MCP config must have a top-level 'mcpServers' entry.",
           call. = FALSE)
    config_path <- tempfile("codeagent-mcp-", fileext = ".json")
    jsonlite::write_json(config, config_path, auto_unbox = TRUE, pretty = FALSE)
    on.exit(unlink(config_path), add = TRUE)
    config <- config_path
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
  names_new <- vapply(tools, function(t)
    tryCatch(as.character(t@name), error = function(e) ""), character(1L))
  if (any(!nzchar(names_new)) || anyDuplicated(names_new))
    stop("MCP tools contain missing or duplicate names.", call. = FALSE)
  existing <- tryCatch(.tool_names(chat$get_tools()), error = function(e) character())
  conflicts <- intersect(names_new, unique(c(existing, names(.TOOL_META))))
  if (length(conflicts))
    stop("MCP tool name conflicts with a reserved or registered tool: ",
         paste(conflicts, collapse = ", "), call. = FALSE)

  n <- 0L
  for (i in seq_along(tools)) {
    t <- tools[[i]]
    register_tool_meta(names_new[[i]], capability = "exec", set = "A")
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
#' NOTE: Project-level and merged settings CANNOT authorise MCP startup (V-08
#' remedy). This function only connects when the host has explicitly provided
#' `mcp_config` to `codeagent_client()`. Settings-file servers and project
#' `.mcp.json` are NOT auto-connected -- the caller must migrate to the
#' explicit `mcp_config` parameter and review the server configurations.
#'
#' @param chat An `ellmer::Chat` object.
#' @param settings List from [load_settings()].
#' @return Invisibly, the number of tools registered (always 0 -- auto-connect
#'   is disabled).
#' @keywords internal
.mcp_autoconnect <- function(chat, settings) {
  # V-08 remedy: project/merged settings can no longer authorise MCP startup.
  # Only explicit `mcp_config` in codeagent_client() is honoured. The servers
  # from settings are ignored to prevent untrusted project config from launching
  # arbitrary processes before the permission gate is active.
  #
  # If you need MCP servers, pass them explicitly:
  #   codeagent_client(mcp_config = list(mcpServers = list(...)))
  #
  # This function is kept as a no-op to avoid breaking callers that expect it
  # to exist; it no longer connects anything from settings.
  invisible(0L)
}

#' Create an R-based MCP server entry
#'
#' Builds an `mcp_servers` list entry that launches an R subprocess running
#' `mcptools::mcp_server()` over stdio.
#'
#' @param tools_script Character(1) or NULL. Path to an `.R` script that yields
#'   a `list()` of `ellmer::tool()` objects.
#' @param session_tools Logical. Whether to expose built-in mcptools session
#'   management tools. Default `FALSE`.
#' @param rscript Character(1). Path to the `Rscript` binary.
#' @return A named list with `type`, `command`, and `args`.
#' @examples
#' config <- r_mcp_server(session_tools = FALSE)
#' config$type
#' @export
r_mcp_server <- function(
    tools_script  = NULL,
    session_tools = FALSE,
    rscript       = file.path(
      R.home("bin"),
      if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
    )) {
  .mcptools_assert_server()
  if (!file.exists(rscript)) {
    fallback <- unname(Sys.which("Rscript"))
    if (!nzchar(fallback))
      cli::cli_abort("Cannot locate Rscript binary. Pass {.arg rscript} explicitly.")
    rscript <- fallback
  }
  st_str <- if (isTRUE(session_tools)) "TRUE" else "FALSE"
  guard <- paste0(
    "if (!requireNamespace('mcptools', quietly=TRUE) || ",
    "utils::packageVersion('mcptools') < package_version('1.0.2.9000')) ",
    "stop('MCP server requires mcptools >= 1.0.2.9000'); ")
  server_call <- if (is.null(tools_script)) {
    sprintf("mcptools::mcp_server(session_tools = %s)", st_str)
  } else {
    ts <- normalizePath(tools_script, mustWork = FALSE)
    ts <- gsub("'", "\\'", ts, fixed = TRUE)
    sprintf("mcptools::mcp_server(tools = '%s', session_tools = %s)", ts, st_str)
  }
  list(type = "stdio", command = rscript,
       args = c("-e", paste0(guard, server_call)))
}
