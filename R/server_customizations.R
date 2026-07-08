#' @title Customizations Server Logic
#' @description Handles Customizations panel row clicks -> show modal.
#'   Each category is independent: data loading + modal dispatch are isolated.
#' @name server_customizations
#' @keywords internal
NULL

server_customizations <- function(input, output, session, chat, settings, cwd, hooks = NULL) {


  # -- Count badges ----------------------------------------------------------

  n_skills <- shiny::reactive({
    tryCatch(length(list_skills_meta(cwd)), error = function(e) 0L)
  })

  n_agents <- shiny::reactive({
    tryCatch(length(.load_agents(cwd)), error = function(e) 0L)
  })

  n_hooks <- shiny::reactive({
    if (!is.null(hooks)) tryCatch(hooks$count(), error = function(e) 0L) else 0L
  })

  n_mcp <- shiny::reactive({
    tryCatch(length(.load_mcp_servers(cwd)), error = function(e) 0L)
  })

  output$ca_open_agents_badge    <- shiny::renderUI(.count_badge(n_agents()))
  output$ca_open_skills_badge    <- shiny::renderUI(.count_badge(n_skills()))
  output$ca_open_hooks_badge     <- shiny::renderUI(.count_badge(n_hooks()))
  output$ca_open_mcp_badge       <- shiny::renderUI(.count_badge(n_mcp()))

  # -- Agents modal ----------------------------------------------------------

  shiny::observeEvent(input$ca_open_agents, {
    shiny::showModal(modal_agents_ui(.load_agents(cwd)))
  })

  # -- Skills modal ----------------------------------------------------------

  shiny::observeEvent(input$ca_open_skills, {
    skill_list <- tryCatch(list_skills_meta(cwd), error = function(e) list())
    shiny::showModal(modal_skills_ui(skill_list))
  })

  # Install skill (triggered from Skills modal footer button)
  shiny::observeEvent(input$install_skill_btn, {
    shiny::removeModal()
    shiny::showModal(shiny::modalDialog(
      title  = "Install Skill",
      footer = shiny::tagList(
        shiny::modalButton("Cancel"),
        shiny::actionButton("install_skill_confirm", "Install", class = "btn-primary")
      ),
      shiny::textInput("install_skill_pkg",  "Package name",      placeholder = "e.g. btw"),
      shiny::textInput("install_skill_name", "Skill name (optional)",
                       placeholder = "leave empty to pick interactively"),
      shiny::selectInput("install_skill_scope", "Scope",
                         choices = c("project", "user"), selected = "project")
    ))
  })

  shiny::observeEvent(input$install_skill_confirm, {
    pkg   <- trimws(input$install_skill_pkg  %||% "")
    name  <- trimws(input$install_skill_name %||% "")
    scope <- input$install_skill_scope       %||% "project"
    shiny::removeModal()
    if (!nzchar(pkg)) {
      shiny::showNotification("Package name is required.", type = "warning"); return()
    }
    if (!requireNamespace("btw", quietly = TRUE)) {
      shiny::showNotification("btw required for skill installation.", type = "error"); return()
    }
    tryCatch({
      btw::btw_skill_install_package(pkg,
        skill = if (nzchar(name)) name else NULL,
        scope = scope)
      shiny::showNotification(sprintf("Skill installed from '%s'.", pkg),
                              type = "message", duration = 4)
    }, error = function(e) {
      shiny::showNotification(conditionMessage(e), type = "error", duration = 6)
    })
  })

  # -- Instructions modal ----------------------------------------------------

  shiny::observeEvent(input$ca_open_instructions, {
    shiny::showModal(modal_instructions_ui(.load_instructions(cwd)))
  })

  # -- Hooks modal -----------------------------------------------------------

  shiny::observeEvent(input$ca_open_hooks, {
    hook_list <- tryCatch({
      if (!is.null(hooks) && is.function(hooks$list)) {
        hooks$list()
      } else {
        list()
      }
    }, error = function(e) list())
    shiny::showModal(modal_hooks_ui(hook_list))
  })

  # -- MCP modal -------------------------------------------------------------

  shiny::observeEvent(input$ca_open_mcp, {
    shiny::showModal(modal_mcp_ui(.load_mcp_servers(cwd)))
  })

  # -- Plugins modal ---------------------------------------------------------

  shiny::observeEvent(input$ca_open_plugins, {
    shiny::showModal(modal_plugins_ui(list()))
  })
}

# ---------------------------------------------------------------------------
# Internal helpers: data loading for the Customizations panel (PURE)
# ---------------------------------------------------------------------------
# These read the filesystem only (no Shiny). Each is used by BOTH the count
# badge reactive and the modal observer, so extracting them removes the former
# duplication and makes the scanning logic unit-testable with a temp dir.

.extract_yaml_field <- function(lines, field) {
  pat <- paste0("^", field, ":\\s*['\"]?(.+?)['\"]?\\s*$")
  m   <- regmatches(lines, regexpr(pat, lines, perl = TRUE))
  if (length(m) == 0L) return(NULL)
  sub(pat, "\\1", m[[1]])
}

# Discover agent definitions (`*.md`) under the standard project + user dirs.
# Returns a list of list(name, description, model).
.load_agents <- function(cwd = getwd()) {
  paths <- c(
    file.path(cwd, ".claude/agents"),
    file.path(cwd, ".btw"),
    path.expand("~/.claude/agents")
  )
  mds <- unlist(lapply(paths, function(p) {
    if (dir.exists(p)) list.files(p, pattern = "\\.md$", full.names = TRUE)
    else character(0)
  }))
  lapply(mds, function(f) {
    lines <- tryCatch(readLines(f, n = 20L, warn = FALSE),
                      error = function(e) character(0))
    list(
      name        = sub("\\.md$", "", basename(f)),
      description = .extract_yaml_field(lines, "description"),
      model       = .extract_yaml_field(lines, "model")
    )
  })
}

# Read MCP server definitions from `<cwd>/mcp.json`. Returns a list of
# list(name, command, url, status); empty list when the file is missing/invalid.
.load_mcp_servers <- function(cwd = getwd()) {
  cfg <- file.path(cwd, "mcp.json")
  if (!file.exists(cfg)) return(list())
  servers <- tryCatch(jsonlite::read_json(cfg)$mcpServers,
                      error = function(e) NULL) %||% list()
  lapply(names(servers), function(nm) {
    s <- servers[[nm]]
    list(
      name    = nm,
      command = if (!is.null(s$command)) paste(c(s$command, s$args), collapse = " ") else NULL,
      url     = s$url,
      status  = "unknown"
    )
  })
}

# Locate active instruction files (CLAUDE.md etc.). Returns list(list(path, active)).
.load_instructions <- function(cwd = getwd()) {
  candidates <- c(
    file.path(cwd, "CLAUDE.md"),
    file.path(cwd, ".claude/instructions.md"),
    path.expand("~/.claude/CLAUDE.md")
  )
  lapply(candidates[file.exists(candidates)], function(f) list(path = f, active = TRUE))
}
