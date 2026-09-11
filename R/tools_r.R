#' @title R Environment Tools
#' @description Integration with the btw package for R-environment tools:
#'   data frame inspection, package docs, session info, git, search, web fetch,
#'   package development (pkg), CRAN search (cran), IDE integration, and
#'   sub-agent delegation (agent).
#'   All tools are `ellmer::tool()` objects sourced from `btw::btw_tools()`.
#' @name tools_r
#' @keywords internal
NULL

# Tool-name prefixes that map to logical groups (for optional filtering).
# Covers all groups available in btw 1.2.1.
.BTW_GROUPS <- list(
  agent       = "btw_tool_agent_",
  cran        = "btw_tool_cran_",
  docs        = "btw_tool_docs_",
  env         = "btw_tool_env_",
  files       = "btw_tool_files_",
  git         = "btw_tool_git_",
  github      = "btw_tool_github",
  ide         = "btw_tool_ide_",
  pkg         = "btw_tool_pkg_",
  sessioninfo = "btw_tool_sessioninfo_",
  web         = "btw_tool_web_"
  # "skill" group (btw_tool_skill) is registered separately via .make_skill_tool()
)

.btw_selected_tools <- function(groups = NULL, include_agent = TRUE) {
  all_tools <- btw::btw_tools()

  # Skills and files have dedicated owners in codeagent. Agent tools also have a
  # dedicated owner inside the full client factory, but remain available through
  # the exported register_r_tools(groups = "agent") API for compatibility.
  all_tools <- Filter(function(t) !identical(t@name, "btw_tool_skill"), all_tools)
  all_tools <- Filter(function(t) !startsWith(t@name, "btw_tool_files_"), all_tools)
  if (!isTRUE(include_agent))
    all_tools <- Filter(function(t) !startsWith(t@name, "btw_tool_agent_"), all_tools)

  if (is.null(groups)) return(all_tools)

  valid_groups   <- names(.BTW_GROUPS)
  unknown_groups <- setdiff(groups, valid_groups)
  if (length(unknown_groups) > 0L) {
    warning(
      "[codeagent] Unknown btw tool group(s): ",
      paste(unknown_groups, collapse = ", "),
      ". Valid groups: ",
      paste(sort(valid_groups), collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  known_groups <- intersect(groups, valid_groups)
  if (length(known_groups) == 0L) return(list())
  prefixes <- unlist(.BTW_GROUPS[known_groups])
  Filter(function(t) {
    any(vapply(prefixes, function(p) startsWith(t@name, p), logical(1L)))
  }, all_tools)
}

.register_r_tools_impl <- function(chat, groups = NULL, include_agent = TRUE) {
  if (!requireNamespace("btw", quietly = TRUE)) {
    warning("[codeagent] btw package not available; R-environment tools skipped.",
            call. = FALSE)
    return(invisible(0L))
  }
  tools <- .btw_selected_tools(groups, include_agent = include_agent)
  for (tool in tools) chat$register_tool(tool)
  invisible(length(tools))
}

.tool_names <- function(tools) {
  unname(vapply(tools %||% list(), function(tool)
    tryCatch(as.character(tool@name), error = function(e) ""), character(1L)))
}

.tool_base_function <- function(tool) {
  fn <- tryCatch(S7::S7_data(tool), error = function(e) NULL)
  if (!is.function(fn)) return(NULL)
  repeat {
    env <- environment(fn)
    original <- NULL
    if (is.environment(env)) {
      for (key in c(
        ".codeagent_data_shield_original", ".codeagent_pre_hook_original",
        ".codeagent_result_original", ".codeagent_path_original"
      )) {
        candidate <- get0(key, env, inherits = FALSE, ifnotfound = NULL)
        if (is.function(candidate)) {
          original <- candidate
          break
        }
      }
    }
    if (is.null(original) || identical(original, fn)) break
    fn <- original
  }
  fn
}

.tool_signature <- function(tool) {
  fn <- .tool_base_function(tool)
  if (!is.function(fn)) return(NA_character_)
  paste(
    tryCatch(as.character(tool@name), error = function(e) ""),
    paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
    paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n"),
    paste(tryCatch(names(tool@arguments@properties),
                   error = function(e) character()), collapse = ","),
    sep = "\n---\n"
  )
}

.tool_signatures <- function(tools) {
  names <- .tool_names(tools)
  values <- vapply(tools %||% list(), .tool_signature, character(1L))
  stats::setNames(as.list(values), names)
}

.filter_verified_worker_tools <- function(tools, context) {
  names_now <- .tool_names(tools)
  allowed <- context$allowed_tools
  signatures <- context$allowed_tool_signatures %||% list()
  keep <- names_now %in% (allowed %||% character())
  if (length(signatures)) {
    keep <- keep & vapply(seq_along(tools), function(i) {
      expected <- signatures[[names_now[[i]]]]
      is.character(expected) && length(expected) == 1L &&
        identical(.tool_signature(tools[[i]]), expected)
    }, logical(1L))
  }
  tools[keep]
}

.btw_replaceable_names <- function() {
  tools <- tryCatch(.btw_selected_tools(NULL, include_agent = FALSE),
                    error = function(e) list())
  unique(.tool_names(tools))
}

.collect_dedicated_agent_tools <- function(parent_chat, settings,
                                           allowed_tools = NULL,
                                           allowed_tool_defs = NULL) {
  sink <- new.env(parent = emptyenv())
  sink$tools <- list()
  sink$register_tool <- function(tool) {
    sink$tools[[length(sink$tools) + 1L]] <- tool
    invisible(sink)
  }
  model <- tryCatch(parent_chat$get_model_object()@name,
                    error = function(e) settings$model %||% "claude-sonnet-4-6")
  security_context <- .worker_security_context_from_settings(
    settings, parent_chat)
  if (!is.null(allowed_tools)) {
    security_context$allowed_tools <- unique(as.character(allowed_tools))
    parent_tools <- allowed_tool_defs %||%
      tryCatch(parent_chat$get_tools(), error = function(e) list())
    parent_names <- .tool_names(parent_tools)
    security_context$allowed_tool_signatures <-
      .tool_signatures(parent_tools[parent_names %in% allowed_tools])
  }
  gate_ask_fn <- tryCatch(.gate_ctx_for(parent_chat)$ask_fn,
                          error = function(e) NULL)
  register_agent_tool(
    sink, model = model,
    mode = "bypass", rules = settings$rules %||% list(),
    worktree_isolation = isTRUE(settings$worktree_isolation),
    ask_fn = gate_ask_fn, async = isTRUE(settings$async_subagents),
    data_shield = settings$data_shield_engine,
    cwd = settings$cwd %||% getwd(), parent_chat = parent_chat,
    hooks = settings$hooks_registry,
    security_context = security_context)
  sink$tools
}

.collect_process_delegation_tools <- function(parent_chat, settings,
                                              allowed_tools,
                                              allowed_tool_defs) {
  if (isFALSE(settings$delegation_tools) ||
      is.null(settings$worker_backend) ||
      inherits(settings$data_shield_engine, "DataShield"))
    return(list())
  sink <- new.env(parent = emptyenv())
  sink$tools <- list()
  sink$register_tool <- function(tool) {
    sink$tools[[length(sink$tools) + 1L]] <- tool
    invisible(sink)
  }
  security_context <- .worker_security_context_from_settings(
    settings, parent_chat)
  security_context$allowed_tools <- unique(as.character(allowed_tools))
  parent_names <- .tool_names(allowed_tool_defs)
  security_context$allowed_tool_signatures <- .tool_signatures(
    allowed_tool_defs[parent_names %in% allowed_tools])
  model <- tryCatch(parent_chat$get_model_object()@name,
                    error = function(e) settings$model %||% NULL)
  register_team_tool(
    sink, model, settings$cwd %||% getwd(),
    security_context = security_context)
  if (isTRUE(settings$background_agents))
    register_background_agent_tool(
      sink, settings$data_shield_engine,
      security_context = security_context)
  sink$tools
}

.prepare_refreshed_tools <- function(tools, chat, settings) {
  tools <- lapply(tools, .normalize_tool_def_result)
  hooks <- settings$hooks_registry %||% NULL
  if (!is.null(hooks)) {
    recheck_fn <- function(name, input) {
      ctx <- tryCatch(.gate_ctx_for(chat), error = function(e) NULL)
      if (is.null(ctx)) return(list(action = "allow", input = input))
      .gate_recheck(ctx, name, input)
    }
    tools <- lapply(tools, function(tool)
      .wrap_tool_pre_hook(tool, hooks, recheck_fn))
  }
  shield <- settings$data_shield_engine %||%
    tryCatch(attr(chat, "codeagent_data_shield"), error = function(e) NULL)
  if (inherits(shield, "DataShield"))
    tools <- lapply(tools, function(tool) .data_shield_wrap_tool(tool, shield))
  tools
}

# Atomically replace UI-owned btw groups and rebuild delegation tools from the
# new parent snapshot. Core, MCP, skill, and file-owner tools remain unchanged.
# The `agent` checkbox controls the dedicated foreground Agent owner.
.replace_btw_tool_groups <- function(chat, groups, settings) {
  old_tools <- tryCatch(chat$get_tools(), error = function(e) NULL)
  if (is.null(old_tools))
    return(list(ok = FALSE, restored = FALSE, fatal = TRUE,
                message = "Could not read the current tool snapshot."))

  groups <- if (is.null(groups)) names(.BTW_GROUPS) else unique(as.character(groups))
  groups <- intersect(groups, names(.BTW_GROUPS))
  agent_enabled <- "agent" %in% groups &&
    !isFALSE(settings$delegation_tools)
  ordinary_groups <- setdiff(groups, c("agent", "files"))
  old_names <- .tool_names(old_tools)
  replaceable <- unique(c(.btw_replaceable_names(),
                          old_names[old_names %in% c(
                            "Agent", "TeamRun", "TeamCoordinate",
                            "BackgroundAgent") |
                                    startsWith(old_names, "btw_tool_agent_")]))
  preserved <- old_tools[!old_names %in% replaceable]

  prepared <- tryCatch({
    ordinary <- .btw_selected_tools(ordinary_groups, include_agent = FALSE)
    target_settings <- settings
    target_settings$btw_groups <- groups
    prospective_names <- unique(c(
      .tool_names(preserved), .tool_names(ordinary),
      if (agent_enabled) "Agent" else character()))
    agent <- if (agent_enabled)
      .collect_dedicated_agent_tools(
        chat, target_settings, allowed_tools = prospective_names,
        allowed_tool_defs = c(preserved, ordinary)) else list()
    parent_defs <- c(preserved, ordinary, agent)
    process_agents <- .collect_process_delegation_tools(
      chat, target_settings,
      allowed_tools = .tool_names(parent_defs),
      allowed_tool_defs = parent_defs)
    additions <- c(ordinary, agent, process_agents)
    add_names <- .tool_names(additions)
    if (any(!nzchar(add_names)) || anyDuplicated(add_names))
      stop("invalid or duplicate target tool names")
    .prepare_refreshed_tools(additions, chat, settings)
  }, error = function(e) e)
  if (inherits(prepared, "error"))
    return(list(ok = FALSE, restored = TRUE, fatal = FALSE,
                message = "Could not prepare the requested btw tool groups."))

  target <- c(preserved, prepared)
  target_names <- .tool_names(target)
  if (any(!nzchar(target_names)) || anyDuplicated(target_names))
    return(list(ok = FALSE, restored = TRUE, fatal = FALSE,
                message = "Requested tool groups produced duplicate names."))

  committed <- tryCatch({
    chat$set_tools(target)
    live <- chat$get_tools()
    identical(.tool_names(live), target_names)
  }, error = function(e) FALSE)
  if (isTRUE(committed))
    return(list(ok = TRUE, restored = TRUE, fatal = FALSE,
                groups = groups, count = length(prepared)))

  restored <- tryCatch({
    chat$set_tools(old_tools)
    identical(chat$get_tools(), old_tools)
  }, error = function(e) FALSE)
  list(ok = FALSE, restored = isTRUE(restored), fatal = !isTRUE(restored),
       message = if (isTRUE(restored))
         "btw tool-group update failed; the previous snapshot was restored." else
         "btw tool-group update and rollback both failed; input was disabled.")
}

#' Register btw R-environment tools to an ellmer Chat object
#'
#' Wraps [btw::btw_tools()] and registers each returned tool to `chat`.
#' If `btw` is not installed a warning is emitted and nothing is registered.
#'
#' The `files` group (`btw_tool_files_*`) is included by default and provides
#' hashline-validated precise editing -- superior to codeagent's own file tools
#' for read/write/edit operations. codeagent's built-in tools remain for
#' permission-gated Bash and legacy compatibility.
#'
#' The `skill` group is intentionally excluded here; it is registered via
#' [codeagent_client()] using `.make_skill_tool()` which merges btw skills
#' with codeagent's own skill discovery.
#'
#' @param chat An `ellmer::Chat` object.
#' @param groups Character vector of group names to include, or `NULL` for all.
#'   Valid groups: `"agent"`, `"cran"`, `"docs"`, `"env"`, `"files"`,
#'   `"git"`, `"github"`, `"ide"`, `"pkg"`, `"sessioninfo"`, `"web"`.
#'   `"files"` is included in the default `NULL` (all groups).
#' @return Invisibly returns the number of tools registered.
#' @export
register_r_tools <- function(chat, groups = NULL) {
  .register_r_tools_impl(chat, groups, include_agent = TRUE)
}

.devtools_available <- function() {
  requireNamespace("devtools", quietly = TRUE)
}

#' R package test verification function
#'
#' Runs `devtools::test()` and returns pass/fail. Use as `verify_fn` in
#' [codeagent_client()] to automatically re-prompt when tests fail.
#'
#' @return A function suitable for `verify_fn`.
#' @export
verify_r_tests <- function() {
  function(response, chat, cwd) {
    if (!.devtools_available())
      return(list(passed = TRUE))
    result <- tryCatch({
      withr::with_dir(cwd, {
        res <- devtools::test(reporter = "silent")
        failures <- sum(vapply(res, function(r) r$failed + r$error, integer(1)))
        list(
          passed  = failures == 0L,
          message = if (failures > 0L)
            sprintf("%d test(s) failed. Run devtools::test() for details.", failures)
          else ""
        )
      })
    }, error = function(e) {
      list(passed = FALSE, message = conditionMessage(e))
    })
    result
  }
}
