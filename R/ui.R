#' @title Shiny UI
#' @description Interactive Shiny application for codeagent.
#'   Uses `shinychat` for streaming output, `ExtendedTask` + `coro::async`
#'   for non-blocking streaming, and an ESC interrupt mechanism.
#' @name ui
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Main app launcher
# ---------------------------------------------------------------------------

#' Launch the codeagent Shiny application
#'
#' Two calling conventions:
#'
#' **New (recommended):** pass a [codeagent_client()] as first argument.
#' All agent configuration (model, permission_mode, btw_groups, etc.) lives
#' in the client. Only UI-specific params are needed here.
#' ```r
#' client <- codeagent_client(
#'   chat_openai_compatible(base_url=..., model=..., credentials=...),
#'   permission_mode = "bypass",
#'   btw_groups = c("docs", "git")
#' )
#' codeagent_app(client, pinned_skills = c("plan"), theme = "light")
#' ```
#'
#' **Legacy (backward-compatible):** pass model/permission_mode/etc. directly,
#' or supply a raw `ellmer::Chat` via `chat=`.
#'
#' @param client A `CodagentClient` from [codeagent_client()], an
#'   `ellmer::Chat`, or NULL (legacy mode — use `model`/`permission_mode`/etc.).
#' @param pinned_skills Character vector. Skill names pinned at top of Skills panel.
#' @param theme Character. `"light"` (default), `"glassmorphism"`, or `"dark"`.
#' @param port Integer or NULL. Shiny port (NULL = random).
#' @param launch.browser Logical. Open in browser (default TRUE).
#' @param model Character. Legacy: model name (ignored when `client` is a
#'   `CodagentClient`).
#' @param permission_mode Character. Legacy: permission mode.
#' @param cwd Character. Legacy: working directory.
#' @param btw_groups Character vector or NULL. Legacy: btw tool groups.
#' @param chat An `ellmer::Chat`. Legacy alias — prefer passing via
#'   [codeagent_client()].
#' @return A `shiny.appobj`.
#' @export
codeagent_app <- function(
  client          = NULL,
  pinned_skills   = character(0),
  theme           = c("light", "glassmorphism", "dark"),
  port            = NULL,
  launch.browser  = TRUE,
  # Legacy params (used when client is not a CodagentClient)
  model           = NULL,
  permission_mode = "default",
  cwd             = getwd(),
  btw_groups      = NULL,
  chat            = NULL
) {
  theme <- match.arg(theme)

  # Resolve to CodagentClient -------------------------------------------
  if (inherits(client, "CodagentClient")) {
    ca_client <- client
  } else {
    # Accept raw Chat via first arg or legacy chat= param
    raw_chat <- if (inherits(client, "Chat")) client else chat
    ca_client <- codeagent_client(
      chat            = raw_chat,
      permission_mode = permission_mode,
      cwd             = cwd,
      btw_groups      = btw_groups
    )
    if (!is.null(model)) ca_client$settings$model <- model
  }

  chat     <- ca_client$chat
  settings <- ca_client$settings
  cwd      <- settings$cwd %||% getwd()

  # Register static assets (inst/www/)
  www_dir <- system.file("www", package = "codeagent")
  if (nzchar(www_dir))
    shiny::addResourcePath("codeagent-www", www_dir)

  # btw tool groups available for Settings panel
  btw_available_groups <- tryCatch({
    if (requireNamespace("btw", quietly = TRUE)) {
      tools <- btw::btw_tools()
      grps  <- unique(sub("btw_tool_([a-z]+)_.*", "\\1",
                          sapply(tools, function(t) t@name)))
      sort(grps[grps != "btw_tool_skill"])
    } else character(0)
  }, error = function(e) character(0))

  # ---------------------------------------------------------------------------
  # UI
  # ---------------------------------------------------------------------------
  ui <- bslib::page_fillable(
    theme = if (identical(theme, "light")) {
      bslib::bs_theme(bootswatch = "flatly")
    } else {
      bslib::bs_theme(
        bootswatch = "darkly",
        bg         = "#0f0c29",
        fg         = "rgba(255,255,255,0.92)",
        primary    = "#a855f7",
        secondary  = "#06b6d4",
        base_font  = bslib::font_google("Inter")
      )
    },
    htmltools::tags$head(
      htmltools::tags$link(rel = "stylesheet", type = "text/css",
                           href = "codeagent-www/styles.css"),
      htmltools::tags$script(src = "codeagent-www/agent.js"),
      # Apply initial theme to <html> (light = no override, CSS vars take bslib defaults)
      htmltools::tags$script(htmltools::HTML(sprintf(
        'document.documentElement.setAttribute("data-theme", "%s");', theme
      )))
    ),

    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 290,
        open  = TRUE,
        # Token budget
        htmltools::tags$div(
          class = "ca-budget-wrap",
          htmltools::tags$div(
            class = "ca-budget-label",
            htmltools::tags$span("Context"),
            htmltools::tags$span(id = "token-budget-text", "0 tokens")
          ),
          htmltools::tags$div(
            class = "token-budget-bar",
            htmltools::tags$div(class = "token-budget-bar-fill", style = "width:0%")
          )
        ),

        # 3-panel accordion
        bslib::accordion(
          id       = "ca_sidebar_accordion",
          class    = "ca-sidebar-accordion",
          multiple = TRUE,
          open     = "Sessions",

          # ── Panel 1: Sessions ──────────────────────────────────────────
          bslib::accordion_panel(
            title = "Sessions",
            value = "Sessions",
            htmltools::tags$div(
              class = "d-flex gap-1 mb-2",
              shiny::actionButton(
                "new_session", "New",
                class = "ca-session-action-btn primary flex-fill btn-sm"
              ),
              shiny::actionButton(
                "save_session_btn", "Save",
                class = "ca-session-action-btn flex-fill btn-sm"
              )
            ),
            shiny::uiOutput("session_list_ui")
          ),

          # ── Panel 2: Skills ────────────────────────────────────────────
          bslib::accordion_panel(
            title = "⚡ Skills",
            value = "Skills",
            shiny::textInput(
              "skill_search", NULL,
              placeholder = "Search skills…",
              width       = "100%"
            ) |> htmltools::tagAppendAttributes(class = "ca-skill-search"),
            htmltools::tags$div(
              class = "ca-skill-scroll",
              shiny::uiOutput("skill_list_ui")
            ),
            htmltools::tags$hr(style = "border-color:var(--ca-border); margin:10px 0 6px;"),
            shiny::actionButton(
              "install_skill_btn", "+ Install skill",
              class = "ca-session-action-btn w-100 btn-sm"
            )
          ),

          # ── Panel 3: Settings ─────────────────────────────────────────
          bslib::accordion_panel(
            title = "⚙️ Settings",
            value = "Settings",
            htmltools::tags$div(
              class = "ca-settings",
              htmltools::tags$span("Permission mode", class = "ca-settings-label"),
              shiny::selectInput(
                "perm_mode", NULL,
                choices  = unlist(PermissionMode),
                selected = permission_mode,
                width    = "100%"
              ),
              if (length(btw_available_groups) > 0L) {
                htmltools::tagList(
                  htmltools::tags$span("btw tools", class = "ca-settings-label"),
                  shiny::checkboxGroupInput(
                    "btw_groups_input", NULL,
                    choices  = btw_available_groups,
                    selected = if (!is.null(btw_groups)) btw_groups
                               else btw_available_groups,
                    inline   = FALSE
                  )
                )
              },
              htmltools::tags$span("Theme", class = "ca-settings-label"),
              shiny::selectInput(
                "theme_select", NULL,
                choices  = c("Light" = "light",
                             "Glassmorphism" = "glassmorphism",
                             "Dark" = "dark"),
                selected = theme,
                width    = "100%"
              )
            )
          )
        ),

        # Footer
        htmltools::tags$div(
          class = "ca-footer",
          "codeagent v0.1.0 · ESC to interrupt"
        )
      ),

      shinychat::chat_ui(
        "chat",
        fill        = TRUE,
        placeholder = "Ask codeagent… (/ for skills, ESC to interrupt)"
      )
    )
  )

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------
  server <- function(input, output, session) {
    interrupt_flag  <- shiny::reactiveVal(FALSE)
    session_id_rv   <- shiny::reactiveVal(NULL)
    compaction_ctrl <- CompactionController$new()
    budget_tracker  <- BudgetTracker$new()
    resource_state  <- ContentReplacementState$new()
    denial_tracker  <- DenialTracker$new()
    iteration_rv    <- shiny::reactiveVal(0L)

    # ------------------------------------------------------------------
    # Streaming task (ExtendedTask + coro::async)
    # ------------------------------------------------------------------
    stream_task <- shiny::ExtendedTask$new(function(user_input) {
      parsed <- .preprocess_input(user_input, cwd)
      actual_input <- if (identical(parsed$type, "skill"))
        tryCatch(load_skill_prompt(parsed$name, parsed$args, cwd),
                 error = function(e) user_input)
      else user_input

      compaction_ctrl$maybe_compact(chat, settings$model_limit %||% 200000L)
      resource_state$maybe_replace(chat)

      coro::async(function() {
        stream <- chat$stream_async(actual_input, stream = "content")
        await(shinychat::chat_append("chat", stream, session = session))

        n_tokens <- estimate_tokens(chat)
        model_limit <- settings$model_limit %||% 200000L
        pct <- round(n_tokens / model_limit * 100)
        session$sendCustomMessage("update_budget", list(
          text = format(n_tokens, big.mark = ","),
          pct  = pct
        ))

        shiny::isolate(iteration_rv(iteration_rv() + 1L))
        sid <- shiny::isolate(session_id_rv())
        if (!is.null(sid))
          tryCatch(save_session(chat, cwd, sid), error = function(e) NULL)
        "done"
      })()
    })

    # ------------------------------------------------------------------
    # User sends a message
    # ------------------------------------------------------------------
    shiny::observeEvent(input$chat_user_input, {
      if (stream_task$status() == "running") return()
      interrupt_flag(FALSE)
      stream_task$invoke(input$chat_user_input)
    })

    # ------------------------------------------------------------------
    # ESC interrupt
    # ------------------------------------------------------------------
    shiny::observeEvent(input$esc, {
      if (stream_task$status() == "running") interrupt_flag(TRUE)
    })

    # ------------------------------------------------------------------
    # Permission mode change
    # ------------------------------------------------------------------
    shiny::observeEvent(input$perm_mode, {
      settings$permission_mode <<- input$perm_mode
      tryCatch(.register_all_tools(chat, settings), error = function(e) NULL)
    }, ignoreInit = TRUE)

    # ------------------------------------------------------------------
    # btw tool groups change
    # ------------------------------------------------------------------
    shiny::observeEvent(input$btw_groups_input, {
      tryCatch(
        register_r_tools(chat, groups = input$btw_groups_input),
        error = function(e) NULL
      )
    }, ignoreInit = TRUE)

    # ------------------------------------------------------------------
    # Theme change
    # ------------------------------------------------------------------
    shiny::observeEvent(input$theme_select, {
      session$sendCustomMessage("set_theme", list(theme = input$theme_select))
    }, ignoreInit = TRUE)

    # ------------------------------------------------------------------
    # New session
    # ------------------------------------------------------------------
    shiny::observeEvent(input$new_session, {
      if (stream_task$status() == "running") return()
      tryCatch(chat$set_turns(list()), error = function(e) NULL)
      session_id_rv(NULL)
      iteration_rv(0L)
      budget_tracker$reset()
      resource_state$reset()
      compaction_ctrl$reset_failures()
      shinychat::chat_clear("chat", session)
    })

    # ------------------------------------------------------------------
    # Save session
    # ------------------------------------------------------------------
    shiny::observeEvent(input$save_session_btn, {
      sid <- session_id_rv()
      if (is.null(sid)) sid <- .generate_uuid_v4()
      tryCatch({
        save_session(chat, cwd, sid)
        session_id_rv(sid)
        shiny::showNotification(
          paste0("Session saved: ", substr(sid, 1L, 8L), "…"),
          type = "message", duration = 3
        )
      }, error = function(e) {
        shiny::showNotification(
          paste0("Save failed: ", conditionMessage(e)),
          type = "error", duration = 5
        )
      })
    })

    # ------------------------------------------------------------------
    # Skill list (searchable, scrollable, pinned at top)
    # ------------------------------------------------------------------
    output$skill_list_ui <- shiny::renderUI({
      metas <- tryCatch(list_skills_meta(cwd), error = function(e) list())
      if (length(metas) == 0L)
        return(htmltools::tags$p(
          style = "color:var(--ca-text-muted); font-size:0.75rem;",
          "No skills found"
        ))

      query <- tolower(trimws(input$skill_search %||% ""))
      if (nzchar(query)) {
        metas <- Filter(function(m)
          grepl(query, tolower(m$name), fixed = TRUE) ||
          grepl(query, tolower(m$description %||% ""), fixed = TRUE),
          metas)
      }

      if (length(metas) == 0L)
        return(htmltools::tags$p(
          style = "color:var(--ca-text-muted); font-size:0.75rem;",
          "No matching skills"
        ))

      # Pinned first, then rest
      pinned  <- Filter(function(m) m$name %in% pinned_skills, metas)
      rest    <- Filter(function(m) !m$name %in% pinned_skills, metas)
      ordered <- c(pinned, rest)

      .make_skill_btn <- function(m) {
        is_pinned <- m$name %in% pinned_skills
        hint_tag  <- if (nzchar(m$argument_hint %||% ""))
          htmltools::tags$span(
            class = "ca-skill-desc",
            m$argument_hint
          ) else NULL
        shiny::actionButton(
          inputId = paste0("skill_btn_", m$name),
          label   = htmltools::tagList(
            htmltools::tags$span(class = "ca-skill-name",
                                 paste0("/", m$name)),
            htmltools::tags$span(class = "ca-skill-desc",
                                 m$description %||% ""),
            hint_tag
          ),
          class = paste(
            "ca-skill-btn w-100 mb-1",
            if (is_pinned) "pinned" else ""
          )
        )
      }

      htmltools::tagList(lapply(ordered, .make_skill_btn))
    })

    # Bind skill button clicks → fill chat input
    shiny::observe({
      metas <- tryCatch(list_skills_meta(cwd), error = function(e) list())
      lapply(metas, function(m) {
        btn_id <- paste0("skill_btn_", m$name)
        local({
          skill_name <- m$name
          shiny::observeEvent(input[[btn_id]], {
            session$sendCustomMessage("fill_skill",
                                      list(text = paste0("/", skill_name, " ")))
          }, ignoreNULL = TRUE, ignoreInit = TRUE)
        })
      })
    })

    # ------------------------------------------------------------------
    # Install skill modal
    # ------------------------------------------------------------------
    shiny::observeEvent(input$install_skill_btn, {
      shiny::showModal(shiny::modalDialog(
        title  = "Install Skill",
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton("install_skill_confirm", "Install",
                              class = "btn-primary")
        ),
        shiny::p("Install a skill from an R package:"),
        shiny::textInput("install_skill_pkg", "Package name",
                         placeholder = "e.g. btw"),
        shiny::textInput("install_skill_name", "Skill name (optional)",
                         placeholder = "leave empty to pick interactively"),
        shiny::selectInput("install_skill_scope", "Scope",
                           choices = c("project", "user"), selected = "project")
      ))
    })

    shiny::observeEvent(input$install_skill_confirm, {
      pkg   <- trimws(input$install_skill_pkg %||% "")
      name  <- trimws(input$install_skill_name %||% "")
      scope <- input$install_skill_scope %||% "project"
      shiny::removeModal()
      if (!nzchar(pkg)) {
        shiny::showNotification("Package name is required.", type = "warning")
        return()
      }
      if (!requireNamespace("btw", quietly = TRUE)) {
        shiny::showNotification("btw package required for skill installation.",
                                type = "error")
        return()
      }
      tryCatch({
        btw::btw_skill_install_package(
          pkg,
          skill = if (nzchar(name)) name else NULL,
          scope = scope
        )
        shiny::showNotification(
          sprintf("Skill installed from '%s'.", pkg),
          type = "message", duration = 4
        )
      }, error = function(e) {
        shiny::showNotification(conditionMessage(e), type = "error", duration = 6)
      })
    })

    # ------------------------------------------------------------------
    # Session list
    # ------------------------------------------------------------------
    output$session_list_ui <- shiny::renderUI({
      sessions <- tryCatch(list_sessions(cwd, limit = 10L),
                           error = function(e) list())
      if (length(sessions) == 0L)
        return(htmltools::tags$p(
          style = "color:var(--ca-text-muted); font-size:0.75rem;",
          "No saved sessions"
        ))

      buttons <- lapply(sessions, function(s) {
        label <- substr(s$summary %||% s$session_id, 1L, 32L)
        shiny::actionButton(
          inputId = paste0("load_sess_", s$session_id),
          label   = label,
          class   = "ca-session-btn w-100 mb-1 btn-sm"
        )
      })
      htmltools::tagList(buttons)
    })

    # Session load buttons
    shiny::observe({
      sessions <- tryCatch(list_sessions(cwd, limit = 10L),
                           error = function(e) list())
      lapply(sessions, function(s) {
        btn_id <- paste0("load_sess_", s$session_id)
        local({
          sid <- s$session_id
          shiny::observeEvent(input[[btn_id]], {
            if (stream_task$status() == "running") return()
            msgs <- tryCatch(get_session_messages(sid, cwd),
                             error = function(e) list())
            if (length(msgs) == 0L) {
              shiny::showNotification("Session is empty or could not be loaded.",
                                      type = "warning", duration = 3)
              return()
            }
            turns <- lapply(msgs, function(m) {
              tryCatch(
                ellmer::Turn(m$type, list(ellmer::ContentText(m$text))),
                error = function(e) NULL
              )
            })
            turns <- Filter(Negate(is.null), turns)
            tryCatch(chat$set_turns(turns), error = function(e) NULL)
            session_id_rv(sid)
            shinychat::chat_clear("chat", session)
            lapply(msgs, function(m) {
              shinychat::chat_append_message(
                "chat",
                list(role = m$type, content = m$text),
                chunk   = FALSE,
                session = session
              )
            })
            shiny::showNotification(
              paste0("Session loaded: ", substr(sid, 1L, 8L), "…"),
              type = "message", duration = 3
            )
          }, ignoreNULL = TRUE, ignoreInit = TRUE)
        })
      })
    })

    # ------------------------------------------------------------------
    # Stream task result handler
    # ------------------------------------------------------------------
    shiny::observe({
      result <- stream_task$result()
      if (!is.null(result) && identical(result, "done")) invisible(NULL)
    })
  }

  shiny::shinyApp(
    ui,
    server,
    options = list(port = port, launch.browser = launch.browser)
  )
}
