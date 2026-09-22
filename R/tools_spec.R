#' @title Tool selection spec
#' @description Resolves the `tools=` argument of [codeagent_client()] into the
#'   concrete set of tools to register. One capability namespace covers
#'   codeagent-native groups (`.CODEAGENT_GROUPS`) and btw groups
#'   (`.BTW_GROUPS`); see `.tool_group()`.
#' @name tools_spec
#' @keywords internal
NULL

# Groups with two parallel implementations, selectable with an "@" suffix.
# Their defaults are the historical behaviour, and they differ on purpose:
# file tools default to codeagent's (any absolute path), while both web
# implementations have always been registered side by side.
.TOOL_BACKEND_DEFAULTS <- list(files = "core", web = "both")
.TOOL_BACKENDS <- c("core", "btw", "both")

# btw group name backing each dual-implementation capability.
.TOOL_BACKEND_BTW_GROUP <- list(files = "files", web = "web")

# Empty selection, used as the base of every resolved spec.
.empty_tool_spec <- function(all = FALSE) {
  list(all = all, native = character(0), btw_groups = character(0),
       backends = .TOOL_BACKEND_DEFAULTS)
}

# Split "files@btw" into name + backend, validating both halves.
.split_tool_token <- function(token) {
  if (!grepl("@", token, fixed = TRUE)) return(list(name = token, backend = NULL))
  parts <- strsplit(token, "@", fixed = TRUE)[[1L]]
  if (length(parts) != 2L || !all(nzchar(parts)))
    stop("[codeagent] Malformed tool selection: \"", token,
         "\". Expected \"group@backend\".", call. = FALSE)
  name <- parts[[1L]]
  backend <- parts[[2L]]
  if (!name %in% names(.TOOL_BACKEND_DEFAULTS))
    stop("[codeagent] \"", name, "\" has a single implementation, so \"",
         token, "\" is not valid. Selectable backends: ",
         paste(names(.TOOL_BACKEND_DEFAULTS), collapse = ", "), ".",
         call. = FALSE)
  if (!backend %in% .TOOL_BACKENDS)
    stop("[codeagent] Unknown backend \"", backend, "\" in \"", token,
         "\". Valid backends: ", paste(.TOOL_BACKENDS, collapse = ", "), ".",
         call. = FALSE)
  list(name = name, backend = backend)
}

# Resolve a `tools=` value.
#   NULL   -- register everything (the historical default)
#   FALSE  -- register no codeagent tool; host-registered tools are untouched
#   character -- capability group names, native tool names, or btw group names,
#                resolved in that order so an owned capability wins.
#' @keywords internal
.resolve_tool_spec <- function(spec = NULL) {
  if (is.null(spec)) return(.empty_tool_spec(all = TRUE))
  if (isFALSE(spec)) return(.empty_tool_spec(all = FALSE))
  out <- .empty_tool_spec(all = FALSE)
  unknown <- character(0)
  for (token in as.character(spec)) {
    parsed  <- .split_tool_token(token)
    name    <- parsed$name
    if (!is.null(parsed$backend)) out$backends[[name]] <- parsed$backend

    if (name %in% names(.TOOL_BACKEND_DEFAULTS)) {
      backend <- out$backends[[name]]
      if (backend %in% c("core", "both"))
        out$native <- c(out$native, .CODEAGENT_GROUPS[[name]])
      if (backend %in% c("btw", "both"))
        out$btw_groups <- c(out$btw_groups, .TOOL_BACKEND_BTW_GROUP[[name]])
    }
    else if (!is.null(.CODEAGENT_GROUPS[[name]]))
      out$native <- c(out$native, .CODEAGENT_GROUPS[[name]])
    else if (identical(.TOOL_META[[name]]$set, "A"))
      out$native <- c(out$native, name)
    else if (!is.null(.BTW_GROUPS[[name]]))
      out$btw_groups <- c(out$btw_groups, name)
    else
      unknown <- c(unknown, name)
  }
  if (length(unknown)) stop(.unknown_tool_error(unknown), call. = FALSE)
  out$native     <- unique(out$native)
  out$btw_groups <- unique(out$btw_groups)
  out
}

# Unknown names are an error, never a silent drop: a caller who asked for a
# tool must learn that it will not be registered.
.unknown_tool_error <- function(unknown) {
  groups <- sort(unique(c(names(.CODEAGENT_GROUPS), names(.BTW_GROUPS))))
  paste0(
    "[codeagent] Unknown tool selection: ",
    paste0("\"", unknown, "\"", collapse = ", "), ".\n",
    "Capability groups: ", paste(groups, collapse = ", "), ".\n",
    "Individual tool names are also accepted (for example \"Read\", \"Bash\").")
}

# Restore a spec that made the round trip through the worker security snapshot's
# JSON. fromJSON(simplifyVector = FALSE) turns every character vector into a
# list, so the fields are flattened back. NULL (a snapshot written before
# `tools=` existed, or a parent that selected nothing) returns NULL, which
# .apply_tool_spec() treats as "register everything" -- the historical
# behaviour, so an old snapshot is never misread as an empty selection.
#' @keywords internal
.rehydrate_tool_spec <- function(spec) {
  if (is.null(spec)) return(NULL)
  backends <- .TOOL_BACKEND_DEFAULTS
  for (nm in names(spec$backends %||% list()))
    backends[[nm]] <- as.character(spec$backends[[nm]])[[1L]]
  list(
    all        = isTRUE(unlist(spec$all, use.names = FALSE)),
    native     = as.character(unlist(spec$native %||% character(0),
                                     use.names = FALSE)),
    btw_groups = as.character(unlist(spec$btw_groups %||% character(0),
                                     use.names = FALSE)),
    backends   = backends
  )
}

# Restore a disallowed set from the worker snapshot's JSON. Only the removal
# list travels here: the scoped entries became ordinary deny rules back in
# codeagent_client() and ride in the snapshot's own `rules`, so rebuilding them
# here would apply them twice.
#' @keywords internal
.rehydrate_disallowed_tools <- function(disallowed) {
  if (is.null(disallowed)) return(NULL)
  list(remove = as.character(unlist(disallowed$remove %||% character(0),
                                    use.names = FALSE)),
       rules = list())
}

# Names of the tools a resolved spec selects (native + the btw groups it keeps).
.spec_selected_names <- function(spec, chat_names) {
  btw_prefixes <- unlist(.BTW_GROUPS[spec$btw_groups], use.names = FALSE)
  btw_keep <- if (length(btw_prefixes))
    chat_names[vapply(chat_names, function(n)
      any(vapply(btw_prefixes, function(p) startsWith(n, p), logical(1L))),
      logical(1L))]
    else character(0)
  unique(c(spec$native, btw_keep))
}

# A tool codeagent itself registered, and therefore one `tools=` may remove.
# Everything else -- host tools registered on the Chat before or after
# codeagent_client(), and resource-driven tools such as MCP -- is left alone.
.is_codeagent_owned_tool <- function(name) {
  identical(.TOOL_META[[name]]$set, "A") || startsWith(name, "btw_tool_")
}

# Drop the codeagent-registered tools a spec did not select. A NULL spec, or
# one with all = TRUE, is a no-op.
#' @keywords internal
.apply_tool_spec <- function(chat, spec) {
  if (is.null(spec) || isTRUE(spec$all)) return(invisible(chat))
  tools <- chat$get_tools()
  if (!length(tools)) return(invisible(chat))
  names_now <- vapply(tools, function(t)
    tryCatch(as.character(t@name), error = function(e) ""), character(1L))
  keep_names <- .spec_selected_names(spec, names_now)
  keep <- !vapply(names_now, .is_codeagent_owned_tool, logical(1L)) |
    names_now %in% keep_names
  if (all(keep)) return(invisible(chat))
  chat$set_tools(tools[keep])
  invisible(chat)
}

# Parse `disallowed_tools=`, which carries two meanings in one vector (the
# Claude Agent SDK's public contract):
#   "Bash"        -- bare name: remove the tool definition from the request
#   "Bash(rm *)"  -- scoped: keep the tool, deny matching calls in every mode
# A bare name may also be a capability group, so the same namespace as `tools=`.
#' @keywords internal
.resolve_disallowed_tools <- function(disallowed = NULL) {
  out <- list(remove = character(0), rules = list())
  if (is.null(disallowed) || !length(disallowed)) return(out)
  for (token in as.character(disallowed)) {
    m <- regmatches(token, regexec("^([^(]+)\\((.*)\\)$", token))[[1L]]
    if (length(m) == 3L) {
      out$rules <- c(out$rules,
                     list(PermissionRule(trimws(m[[2L]]), "deny",
                                         rule_content = m[[3L]])))
      next
    }
    if (!is.null(.CODEAGENT_GROUPS[[token]]))
      out$remove <- c(out$remove, .CODEAGENT_GROUPS[[token]])
    else if (!is.null(.BTW_GROUPS[[token]]))
      out$remove <- c(out$remove, paste0("^", .BTW_GROUPS[[token]]))
    else
      out$remove <- c(out$remove, token)
  }
  out$remove <- unique(out$remove)
  out
}

# Remove the tools a `disallowed_tools=` selection names. Entries starting with
# "^" are btw group prefixes; everything else is an exact tool name.
#' @keywords internal
.apply_disallowed_tools <- function(chat, remove) {
  if (!length(remove)) return(invisible(chat))
  tools <- chat$get_tools()
  if (!length(tools)) return(invisible(chat))
  names_now <- vapply(tools, function(t)
    tryCatch(as.character(t@name), error = function(e) ""), character(1L))
  exact    <- remove[!startsWith(remove, "^")]
  prefixes <- sub("^\\^", "", remove[startsWith(remove, "^")])
  drop <- names_now %in% exact
  if (length(prefixes))
    drop <- drop | vapply(names_now, function(n)
      any(vapply(prefixes, function(p) startsWith(n, p), logical(1L))),
      logical(1L))
  if (!any(drop)) return(invisible(chat))
  chat$set_tools(tools[!drop])
  invisible(chat)
}
