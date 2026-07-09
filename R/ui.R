#' @title Shiny UI -- codeagent_app()
#' @description Three-panel layout: left sidebar (Sessions/Customizations/Settings) +
#'   chat panel + main output panel.
#' @name ui
#' @keywords internal
NULL

# Map a theme name (README "default/flatly/darkly/glass" + CLI
# "light/dark/glassmorphism" vocabularies) to a bslib bs_theme. Unknown names
# fall back to the default light theme (never errors).
.resolve_app_theme <- function(theme = "default") {
  key <- switch(tolower(theme %||% "default"),
    light  = , default = "default",
    dark   = , darkly  = "darkly",
    flatly = "flatly",
    glass  = , glassmorphism = "glass",
    "default")
  switch(key,
    flatly = bslib::bs_theme(version = 5, bootswatch = "flatly"),
    darkly = bslib::bs_theme(version = 5, bootswatch = "darkly"),
    glass  = bslib::bs_add_rules(
      bslib::bs_theme(
        version = 5, bg = "#0e1230", fg = "#e9ecff",
        primary = "#8ab4ff", secondary = "#9aa0c4"
      ),
      paste(
        "body { background:",
        "radial-gradient(1200px 800px at 15% 0%, #1b2350 0%, #0e1230 55%) fixed; }",
        ".card, .accordion, .accordion-item, .bslib-sidebar-layout > .sidebar,",
        ".modal-content {",
        "background-color: rgba(255,255,255,0.06) !important;",
        "backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);",
        "border: 1px solid rgba(255,255,255,0.12) !important; }",
        sep = "\n")
    ),
    bslib::bs_theme(version = 5)
  )
}

#' Launch the codeagent Shiny application
#'
#' @param client A `CodeagentClient` from [codeagent_client()], an
#'   `ellmer::Chat`, or NULL (legacy mode).
#' @param theme UI theme. One of `"default"` (light Bootstrap 5), `"flatly"`,
#'   `"darkly"` (dark), or `"glass"` (dark glassmorphism). The CLI aliases
#'   `"light"` -> `"default"`, `"dark"` -> `"darkly"`, and `"glassmorphism"` ->
#'   `"glass"` are also accepted. Set at launch; the live dark-mode toggle in the
#'   sidebar still flips light/dark on top of the chosen theme.
#' @param pinned_skills Character vector. Retained for backward compatibility;
#'   the old Skills picker panel was replaced by the slash-command typeahead
#'   (type `/` in the chat input), so this argument is currently unused.
#' @param greeting Character or NULL. If provided, pre-fills the chat input box
#'   with this text on startup (used by the "Chat about selection" IDE addin to
#'   seed the first message with the selected code). NULL leaves the input empty.
#' @param port Integer or NULL. Shiny port (NULL = random).
#' @param chat_submit_key How the chat input submits: `"enter"` (default, Enter
#'   sends, Shift/Ctrl+Enter inserts a newline) or `"enter+modifier"`
#'   (Ctrl/Cmd+Enter sends, plain Enter inserts a newline -- friendlier for
#'   long multi-line prompts). Set at launch; not switchable live.
#' @param launch.browser Logical. Open in browser (default TRUE).
#' @param file_tree_show_hidden Logical. Show hidden dotfiles (e.g. `.git`,
#'   `.codegraph`) in the file tree. Default `FALSE` to reduce clutter/lag.
#' @param file_tree_exclude Character vector. Directory names excluded from the
#'   file tree (default `renv`, `node_modules`, `packrat`, `.git`,
#'   `.Rproj.user`). Set `character(0)` to disable exclusion.
#' @param model Character. Legacy: model name.
#' @param permission_mode Character. Legacy: permission mode.
#' @param cwd Character. Legacy: working directory.
#' @param btw_groups Character vector or NULL. Legacy: btw tool groups.
#' @param chat An `ellmer::Chat`. Legacy alias.
#' @return A `shiny.appobj`.
#' @export
codeagent_app <- function(
  client          = NULL,
  theme           = "default",
  pinned_skills   = character(0),
  greeting        = NULL,
  port            = NULL,
  launch.browser  = TRUE,
  file_tree_show_hidden = FALSE,
  file_tree_exclude = c("renv", "node_modules", "packrat", ".git", ".Rproj.user"),
  chat_submit_key = c("enter", "enter+modifier"),
  # Legacy params
  model           = NULL,
  permission_mode = "default",
  cwd             = getwd(),
  btw_groups      = NULL,
  chat            = NULL
) {

  # Resolve to CodeagentClient. When we build it ourselves, build a *shell*
  # (register_tools = FALSE) so the UI renders immediately and the expensive tool
  # registration (btw_tools, ~15-40s) is deferred to a progress-reported in-server
  # step. A pre-built client already has its tools, so it is used as-is.
  if (inherits(client, "CodeagentClient")) {
    ca_client   <- client
    tools_ready <- TRUE
  } else {
    raw_chat <- if (inherits(client, "Chat")) client else chat
    ca_client <- codeagent_client(
      chat            = raw_chat,
      permission_mode = permission_mode,
      cwd             = cwd,
      btw_groups      = btw_groups,
      register_tools  = FALSE
    )
    if (!is.null(model)) ca_client$settings$model <- model
    tools_ready <- FALSE
  }

  chat_obj <- ca_client$chat
  settings <- ca_client$settings
  cwd      <- settings$cwd %||% getwd()

  # Static assets
  www_dir <- system.file("www", package = "codeagent")
  if (nzchar(www_dir))
    shiny::addResourcePath("codeagent-www", www_dir)

  # NOTE: this value is vestigial. The skill picker footer
  # (.skill_picker_footer) no longer consumes it -- the real, FULL skill list is
  # served by shinychat's slash-command typeahead (type "/"; see
  # R/server_slash.R -> list_skills_meta), which is now backed by an on-disk
  # metadata cache so it is near-instant even on a cold app launch. Kept as an
  # empty stub for the chat_codeagent_ui() signature.
  skill_meta <- NULL

  # btw groups for Settings panel
  # Group names come from codeagent's own .BTW_GROUPS constant; we only need to
  # know btw is INSTALLED (not load it). requireNamespace("btw") here cost ~2.4s
  # of cold namespace load on the critical path to first paint -- system.file()
  # checks the installed package without loading it, so the UI shell serves
  # sooner (btw is loaded later, under the init overlay, at tool registration).
  btw_available_groups <- tryCatch({
    if (nzchar(system.file(package = "btw"))) sort(names(.BTW_GROUPS))
    else character(0)
  }, error = function(e) character(0))

  # Model choices for the Settings panel: codeagent.md aliases + current model.
  cur_model     <- settings$model %||% tryCatch(chat_obj$get_model(), error = function(e) NULL)
  model_choices <- tryCatch({
    aliases <- .read_codeagent_config(cwd)
    ch <- character(0)
    if (length(aliases)) ch <- stats::setNames(unlist(aliases), names(aliases))
    if (!is.null(cur_model) && !(cur_model %in% ch)) ch <- c(stats::setNames(cur_model, cur_model), ch)
    ch
  }, error = function(e) if (!is.null(cur_model)) stats::setNames(cur_model, cur_model) else character(0))

  # ---------------------------------------------------------------------------
  # UI
  # ---------------------------------------------------------------------------
  chat_submit_key <- match.arg(chat_submit_key)
  ca_bs_theme <- .resolve_app_theme(theme)
  ui <- bslib::page_sidebar(
    fillable = TRUE,
    theme    = ca_bs_theme,
    head_assets(),
    # Prominent full-window init overlay shown while tools/skills load in-app.
    shiny::uiOutput("ca_init_overlay"),
    sidebar  = bslib::sidebar(
      id        = "ca_left_sidebar",
      width     = 240,
      resizable = TRUE,
      padding   = 4,
      bslib::card(
        fill = TRUE,
        left_sidebar_ui(
          permission_mode      = permission_mode,
          btw_available_groups = btw_available_groups,
          btw_groups_selected  = btw_groups,
          model_choices        = model_choices,
          current_model        = cur_model
        )
      )
    ),
    bslib::layout_sidebar(
      fill     = TRUE,
      fillable = TRUE,
      border   = FALSE,
      sidebar  = bslib::sidebar(
        id        = "ca_output_sidebar",
        position  = "right",
        width     = "50%",
        resizable = TRUE,
        fillable  = TRUE,
        padding   = 4,
        bslib::card(
          fill = TRUE,
          output_panel_ui()
        )
      ),
      bslib::card(
        fill = TRUE,
        chat_codeagent_ui(skill_meta, submit_key = chat_submit_key)
      )
    )
  )

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------
  server <- function(input, output, session) {

    # Shared reactive state (single reactiveValues, no scattered reactiveVal)
    state <- shiny::reactiveValues(
      session_id      = tryCatch(.generate_uuid_v4(), error = function(e) "default"),
      initializing    = TRUE,       # deferred tool registration in progress -> gate input
      init_step       = "Loading tools & skills\u2026",
      iteration       = 0L,
      interrupt       = FALSE,
      main_output     = NULL,
      settings_changed = 0L,
      sessions_dirty  = 0L,         # bumped after a session is saved/new/deleted
                                    # -> the Sessions list re-renders (see server_sessions)
      pending_interaction = NULL,   # Phase 3: approval / question pause slot
      compaction_ctrl = CompactionController$new(),
      budget_tracker  = BudgetTracker$new(),
      resource_state  = ContentReplacementState$new()
    )

    # Pre-fill the input with an initial greeting (e.g. the IDE "Chat about
    # selection" addin seeds the selected code). Guarded: default NULL leaves the
    # normal app path untouched. onFlushed ensures the chat UI exists first.
    if (!is.null(greeting) && nzchar(greeting)) {
      session$onFlushed(function() {
        tryCatch(
          shinychat::update_chat_user_input("chat", value = greeting,
                                             focus = TRUE, session = session),
          error = function(e) NULL)
      }, once = TRUE)
    }

    # Wire server modules
    # NOTE: We do NOT call shinychat::chat_server() here. In shinychat >= 0.4 it
    # unconditionally registers its own observeEvent(input$chat_user_input) that
    # auto-streams the response via client$stream_async(). That conflicts with
    # codeagent's harness stream_task (server_chat) -- both would fire on every
    # submit, producing duplicate/broken streams. codeagent owns streaming so it
    # can wrap it with skill preprocessing, compaction, hooks and session save.
    # Typed slash commands still work: server_chat's observeEvent runs the input
    # through .preprocess_input()/.handle_chat_command() before the LLM.
    # Trade-off: no native shinychat slash autocomplete palette.
    chat_server_mod <- NULL

    # Phase 3: wire the interaction bar (approval / question) and build the
    # promise-returning Shiny ask callbacks. Stash them in `settings` BEFORE the
    # deferred registration below, so .register_all_tools() (in onFlushed) builds
    # the interactive tools (Write/Edit/MultiEdit/Bash/RunR + AskUserQuestion) as
    # async, UI-gated variants.
    interaction <- server_interaction(input, output, session, state)
    settings$shiny_ask_fn          <- interaction$ask_fn
    settings$shiny_ask_question_fn <- interaction$ask_question_fn
    # NB: tools are registered LAZILY in the onFlushed() init below (after the UI
    # + progress overlay render). Registering here would block the first flush and
    # defeat the instant-UI / overlay. (server_settings re-registers on mode change.)

    stream_task <- server_chat(input, output, session,
                               chat            = chat_obj,
                               settings        = settings,
                               state           = state,
                               cwd             = cwd,
                               chat_server_mod = chat_server_mod)

    server_sessions(input, output, session,
                    chat        = chat_obj,
                    cwd         = cwd,
                    state       = state,
                    stream_task = stream_task,
                    settings    = settings)

    # Prominent init overlay: a full-window splash shown while the deferred
    # initialization runs, so the user sees clear progress instead of a frozen or
    # blank UI. Hidden once state$initializing flips to FALSE.
    output$ca_init_overlay <- shiny::renderUI({
      if (!isTRUE(state$initializing)) return(NULL)
      htmltools::div(
        style = paste0(
          "position:fixed; inset:0; z-index:2000;",
          "background:var(--bs-body-bg,#fff);",
          "display:flex; flex-direction:column; align-items:center;",
          "justify-content:center; gap:18px;"),
        htmltools::tags$div(class = "spinner-border text-primary",
                            style = "width:3rem;height:3rem;", role = "status"),
        htmltools::tags$h4(style = "margin:0;", "Initializing codeagent\u2026"),
        htmltools::tags$p(style = "color:var(--bs-secondary-color,#666);margin:0;",
                          state$init_step %||% "Loading tools & skills\u2026")
      )
    })

    # Deferred initialization: register tools (btw + skills, ~15-40s) AFTER the UI
    # (incl. the overlay above) has been flushed to the client, so the overlay is
    # visible throughout. Input stays gated (state$initializing) until ready. A
    # pre-built client already has its tools (tools_ready) -> overlay clears fast.
    session$onFlushed(function() {
      if (!isTRUE(tools_ready))
        tryCatch(.register_all_tools(chat_obj, settings), error = function(e) NULL)
      state$initializing <- FALSE
    }, once = TRUE)

    # Auto-continue: restore the most recent session on startup so users
    # pick up where they left off (mirrors `codeagent chat --continue`).
    # Gated by settings$auto_continue (default TRUE); set FALSE for a fresh
    # session on every open.
    shiny::observe({
      shiny::req(TRUE)   # run once at startup
      if (!isTRUE(settings$auto_continue %||% FALSE)) return()
      sid <- tryCatch(
        restore_session_into_chat(chat_obj, session_id = NULL, cwd = cwd),
        error = function(e) NULL)
      if (!is.null(sid)) {
        state$session_id <- sid
        # A restored conversation must never carry a stale live approval/question
        # pause: pending_interaction is per-session UI state, not conversation.
        state$pending_interaction <- NULL
        shinychat::chat_clear("chat", session)
        # Replay via contents_shinychat -- native tool card rendering.
        .replay_turns_to_ui(chat_obj, session)
        # Refresh the CONTEXT token meter for the auto-restored conversation.
        tryCatch({
          n_tokens <- token_count_with_estimation(chat_obj)
          session$sendCustomMessage("update_budget",
            .budget_payload(n_tokens, settings$model_limit %||% 200000L,
                            settings$model %||% ""))
        }, error = function(e) NULL)
      }
    }) |> shiny::bindEvent(session$clientData$url_hostname, once = TRUE)

    server_settings(input, output, session,
                    chat        = chat_obj,
                    settings    = settings,
                    cwd         = cwd,
                    stream_task = stream_task)

    server_customizations(input, output, session,
                          chat     = chat_obj,
                          settings = settings,
                          cwd      = cwd)

    server_skills(input, output, session,
                  cwd           = cwd,
                  pinned_skills = pinned_skills)

    # Official shinychat slash-command typeahead (task 09), driven standalone
    # (codeagent owns streaming, so no chat_server). Selection is dispatched
    # DIRECTLY here (local commands via .handle_chat_command, skills via the
    # shared stream_task) -- NOT re-submitted through the input, which shinychat
    # would re-recognise as a slash command and drop (observeEvent de-dupe).
    server_slash(input, session, cwd = cwd,
                 stream_task = stream_task,
                 chat        = chat_obj,
                 settings    = settings,
                 state       = state)

    server_right(input, output, session,
                 cwd   = cwd,
                 state = state,
                 show_hidden = isTRUE(file_tree_show_hidden),
                 exclude = file_tree_exclude)

    # Stream task result handler (no-op: updates handled inside server_chat)
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
