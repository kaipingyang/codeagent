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

.resolve_page_chat_theme <- function(theme = "default") {
  key <- switch(tolower(theme %||% "default"),
    light  = , default = "default",
    dark   = , darkly  = "darkly",
    flatly = "flatly",
    glass  = , glassmorphism = "glass",
    "default")
  page_theme <- .shinychat_export("page_chat_theme")
  if (!is.function(page_theme)) return(.resolve_app_theme(theme))
  if (!identical(key, "glass"))
    return(page_theme(preset = if (identical(key, "default")) "shiny" else key))
  bslib::bs_add_rules(
    page_theme(
      preset = "shiny", bg = "#0e1230", fg = "#e9ecff",
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
      sep = "
")
  )
}

# Build the Model-dropdown choices from a codeagent.md `client:` alias map plus
# the currently-active model. Returns a named character vector (label -> spec)
# safe for shiny::selectInput (never NA/empty names). Empty when there is nothing
# to offer. NOTE: reads only `$client_spec` -- unlisting the whole config yields
# NA names and crashes selectInput's choice processing.
.config_model_choices <- function(cwd = getwd(), cur_model = NULL) {
  spec <- tryCatch(.read_codeagent_config(cwd)$client_spec,
                   error = function(e) NULL)
  ch <- character(0)
  if (is.list(spec) && length(spec)) {
    ch <- stats::setNames(as.character(unlist(spec, use.names = FALSE)),
                          names(spec))
  } else if (is.character(spec) && length(spec) == 1L && nzchar(spec)) {
    ch <- stats::setNames(spec, spec)
  }
  # Drop any entry with a missing/empty name or value (selectInput rejects NAs).
  if (length(ch)) {
    nm   <- names(ch)
    if (is.null(nm)) nm <- rep(NA_character_, length(ch))
    keep <- !is.na(nm) & nzchar(nm) & !is.na(ch) & nzchar(ch)
    ch   <- ch[keep]
  }
  # Prepend the active model only if it isn't already represented -- either as a
  # full spec value or as the model component ("provider/MODEL") of one, so the
  # current model doesn't show up twice (raw + alias).
  spec_models <- sub("^[^/]+/", "", ch)
  if (!is.null(cur_model) && nzchar(cur_model) &&
      !(cur_model %in% ch) && !(cur_model %in% spec_models))
    ch <- c(stats::setNames(cur_model, cur_model), ch)
  ch
}

# Pick the dropdown's `selected` value for the active model. It MUST be one of
# the choice values (a "provider/model" spec), else selectInput errors with
# "`selected` value ... is not in `choices`". Matches by exact value first, then
# by the model component, and falls back to the first choice.
.config_selected_model <- function(choices, cur_model = NULL) {
  if (is.null(cur_model) || !length(choices)) return(cur_model)
  if (cur_model %in% choices) return(cur_model)
  hit <- match(cur_model, sub("^[^/]+/", "", choices))
  if (!is.na(hit)) return(unname(choices[[hit]]))
  unname(choices[[1L]])
}

# Invoke a per-session CodeagentClient factory. Factories may accept `session`
# (recommended) or no arguments. Kept separate for contract tests.
.invoke_codeagent_client_factory <- function(factory, session) {
  if (!is.function(factory)) stop("`client_factory` must be a function.", call. = FALSE)
  fmls <- names(formals(factory))
  client <- if ("session" %in% fmls || "..." %in% fmls) factory(session = session) else factory()
  if (!inherits(client, "CodeagentClient"))
    stop("`client_factory` must return a CodeagentClient.", call. = FALSE)
  client
}


# Convert a bare ellmer Chat template into the canonical per-session client
# factory. Mirrors querychat: share only the immutable template, clone mutable
# Chat state inside the Shiny session.
.codeagent_chat_template_factory <- function(chat, permission_mode, cwd, btw_groups) {
  force(chat); force(permission_mode); force(cwd); force(btw_groups)
  function(session) codeagent_client(
    chat = chat$clone(), permission_mode = permission_mode,
    cwd = cwd, btw_groups = btw_groups, register_tools = FALSE)
}
.codeagent_page_toolbar <- function() {
  bslib::toolbar(
    bslib::input_dark_mode(id = "ca_dark_mode"),
    bslib::toolbar_input_button(
      "ca_workspace_toggle", "Workspace",
      show_label = TRUE,
      tooltip = "Show or hide the workspace drawer"
    ),
    align = "right"
  )
}

# Build the opt-in full-window shinychat page while codeagent keeps server,
# session, permission, and streaming ownership.
.codeagent_page_chat_ui <- function(theme, sidebar, workspace,
                                    chat_args = list()) {
  if (!.shinychat_page_chat_available()) {
    stop(
      paste0(
        "`ui_layout = \"page_chat\"` requires shinychat APIs ",
        "`page_chat()` and the complete chat drawer control API. ",
        "Install the GitHub version pinned in DESCRIPTION."
      ),
      call. = FALSE
    )
  }
  page_chat <- .shinychat_export("page_chat")
  chat_drawer <- .shinychat_export("chat_drawer")

  drawer <- do.call(
    chat_drawer,
    c(list(workspace), list(
      title = "Workspace", width = "50%", open = TRUE, resizable = TRUE))
  )
  # page_chat owns the full-window layout; codeagent's primary chat should fill
  # the available main column instead of inheriting shinychat's prose-oriented
  # 760px default cap. The sidebar and drawer still reduce the containing width.
  chat_args$width <- "100%"
  page <- do.call(
    page_chat,
    c(list(
      title = "codeagent", id = "chat", theme = theme,
      toolbar_global = .codeagent_page_toolbar(),
      sidebar = sidebar, drawer = drawer),
      chat_args)
  )
  htmltools::tagAppendChildren(
    page,
    head_assets(),
    shiny::uiOutput("ca_init_overlay")
  )
}

#' Launch the codeagent Shiny application
#'
#' @param client A pre-built `CodeagentClient` (single-user compatibility) or,
#'   for backward compatibility, an `ellmer::Chat` template (cloned per Shiny
#'   session). Prefer `chat=` for the template form.
#' @param client_factory Optional `function(session)` (or zero-argument function)
#'   returning a fresh `CodeagentClient` for each Shiny session. This is the
#'   most flexible multi-user mode.
#' @param ui_layout UI shell. `"classic"` (default) preserves the existing
#'   three-column layout. `"page_chat"` opts into shinychat's full-window page
#'   with codeagent controls on the left and the Output/Files/File workspace in
#'   the official resizable drawer on the right.
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
#' @param chat An `ellmer::Chat` template cloned inside each Shiny session;
#'   convenient multi-user entry point.
#' @param web_citations Citation presentation mode: `"off"` (default) or
#'   `"shiny_aside"` for the deterministic current-turn
#'   `[[cite:SOURCE_ID|claim]]` bridge. Logical `TRUE`/`FALSE` remains accepted
#'   for compatibility. Enabled replies are buffered and validated before any
#'   `<shiny-aside>` markup is built server-side.
#' @param web_allow_private Logical. Reserved opt-in for local development.
#'   Private-network fetching remains disabled in this release; `TRUE` fails
#'   closed rather than weakening SSRF protection.
#' @return A `shiny.appobj`.
#' @export
codeagent_app <- function(
  client          = NULL,
  client_factory  = NULL,
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
  chat            = NULL,
  web_citations   = c("off", "shiny_aside"),
  web_allow_private = FALSE,
  ui_layout       = c("classic", "page_chat")
) {

  ui_layout <- match.arg(ui_layout)
  if (is.logical(web_citations)) {
    if (length(web_citations) != 1L || is.na(web_citations))
      stop("`web_citations` must be TRUE/FALSE, 'off', or 'shiny_aside'.", call. = FALSE)
    web_citations <- if (isTRUE(web_citations)) "shiny_aside" else "off"
  } else {
    web_citations <- match.arg(web_citations)
  }
  if (!identical(web_allow_private, FALSE))
    stop("Private-network web fetching is not enabled in this release.", call. = FALSE)

  if (!is.null(client_factory) && (!is.null(client) || !is.null(chat)))
    stop("Use only one of `client_factory`, `client`, or `chat`.", call. = FALSE)

  template_model <- NULL
  if (is.null(client_factory)) {
    template_chat <- if (inherits(client, "Chat")) client else
                     if (inherits(chat, "Chat")) chat else NULL
    if (!is.null(template_chat)) {
      # querychat-style convenience path: the supplied bare Chat is an immutable
      # template; clone it inside every Shiny server session, then wrap it in a
      # fresh CodeagentClient. A pre-built CodeagentClient is NOT cloned here.
      template_model <- tryCatch(template_chat$get_model(), error = function(e) NULL)
      client_factory <- .codeagent_chat_template_factory(
        template_chat, permission_mode = permission_mode,
        cwd = cwd, btw_groups = btw_groups)
      client <- NULL
      chat <- NULL
    }
  }

  # With no explicit client/template, default to a per-session factory.
  if (is.null(client_factory) && is.null(client) && is.null(chat)) {
    client_factory <- function(session) codeagent_client(
      permission_mode = permission_mode, cwd = cwd, btw_groups = btw_groups,
      register_tools = FALSE)
  }

  if (!is.null(client_factory)) {
    ca_client <- NULL
    chat_obj <- NULL
    tools_ready <- FALSE
    settings <- load_settings(cwd)
    settings$permission_mode <- permission_mode
    settings$cwd <- cwd
    settings$btw_groups <- btw_groups
    if (!is.null(model)) settings$model <- model
    else if (!is.null(template_model)) settings$model <- template_model
  } else if (inherits(client, "CodeagentClient")) {
    ca_client   <- client
    tools_ready <- TRUE
    chat_obj <- ca_client$chat
    settings <- ca_client$settings
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
    chat_obj <- ca_client$chat
    settings <- ca_client$settings
  }
  cwd <- settings$cwd %||% getwd()

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

  # Model choices for the sidebar dropdown: codeagent.md `client:` aliases +
  # current model (see .config_model_choices -- must read only $client_spec).
  cur_model     <- settings$model %||% tryCatch(chat_obj$get_model(), error = function(e) NULL)
  model_choices <- .config_model_choices(cwd, cur_model)
  sel_model     <- .config_selected_model(model_choices, cur_model)

  # ---------------------------------------------------------------------------
  # UI
  # ---------------------------------------------------------------------------
  chat_submit_key <- match.arg(chat_submit_key)
  ca_bs_theme <- if (identical(ui_layout, "page_chat"))
    .resolve_page_chat_theme(theme) else .resolve_app_theme(theme)
  left_sidebar <- bslib::sidebar(
    id = "ca_left_sidebar", width = 240, resizable = TRUE, padding = 4,
    bslib::card(
      fill = TRUE,
      left_sidebar_ui(
        permission_mode = permission_mode,
        btw_available_groups = btw_available_groups,
        btw_groups_selected = btw_groups,
        model_choices = model_choices,
        current_model = sel_model,
        show_dark_mode = !identical(ui_layout, "page_chat")
      )
    )
  )

  if (identical(ui_layout, "page_chat")) {
    workspace <- htmltools::div(
      id = "ca_page_chat_workspace",
      class = "html-fill-container html-fill-item",
      style = "height:100%;min-height:0;",
      bslib::card(fill = TRUE, output_panel_ui())
    )
    ui <- .codeagent_page_chat_ui(
      theme = ca_bs_theme,
      sidebar = left_sidebar,
      workspace = workspace,
      chat_args = .codeagent_chat_args(skill_meta, chat_submit_key)
    )
  } else {
    ui <- bslib::page_sidebar(
      fillable = TRUE,
      theme = ca_bs_theme,
      head_assets(),
      shiny::uiOutput("ca_init_overlay"),
      sidebar = left_sidebar,
      bslib::layout_sidebar(
        fill = TRUE,
        fillable = TRUE,
        border = FALSE,
        sidebar = bslib::sidebar(
          id = "ca_output_sidebar", position = "right", width = "50%",
          resizable = TRUE, fillable = TRUE, padding = 4,
          bslib::card(fill = TRUE, output_panel_ui())
        ),
        bslib::card(
          fill = TRUE,
          chat_codeagent_ui(skill_meta, submit_key = chat_submit_key)
        )
      )
    )
  }

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------
  server <- function(input, output, session) {

    # Multi-user mode: create all mutable backend state inside this Shiny
    # session. A pre-built client remains the explicit single-user path.
    session_client <- if (!is.null(client_factory))
      .invoke_codeagent_client_factory(client_factory, session) else ca_client
    chat_obj <- session_client$chat
    settings <- session_client$settings
    settings$web_citations <- web_citations
    settings$ui_layout <- ui_layout
    cwd <- settings$cwd %||% getwd()
    tools_ready <- if (!is.null(client_factory))
      length(tryCatch(chat_obj$get_tools(), error = function(e) list())) > 0L else
      tools_ready
    if (.web_citations_enabled(settings$web_citations)) {
      # The app-level opt-in may be applied after a factory built its client.
      # Refresh prompt and already-registered web tools before the first turn.
      tryCatch(chat_obj$set_system_prompt(.build_system_prompt(settings, cwd)),
               error = function(e) NULL)
      if (isTRUE(tools_ready))
        tryCatch(register_web_tools(chat_obj, citations = TRUE),
                 error = function(e) NULL)
    }

    # SessionEnd hook (CC parity): fire when the browser session ends, matching
    # CC's executeSessionEndHooks. hooks live on the session's settings.
    # Also start filesystem-watch hooks (FileChanged / ConfigChange) here, since
    # the Shiny reactive loop pumps `later` so watcher callbacks dispatch.
    local({
      sess_hooks <- tryCatch(settings$hooks_registry, error = function(e) NULL)
      watch_handle <- tryCatch(.start_hook_watchers(sess_hooks, cwd = cwd),
                               error = function(e) NULL)
      session$onSessionEnded(function() {
        if (!is.null(watch_handle)) tryCatch(watch_handle$stop(), error = function(e) NULL)
        if (!is.null(sess_hooks))
          tryCatch(sess_hooks$run_session_end("other", list()),
                   error = function(e) NULL)
        # Release the Data Shield's sensitive closures/state at session teardown
        # (kiro round-2 #10): a per-session shield holds datasets, a value index,
        # reviewer/ask closures and (custom) scanner closures. close() is
        # idempotent and the R6 finalizer is only a GC backstop, so close here.
        sh <- tryCatch(settings$data_shield_engine, error = function(e) NULL)
        if (inherits(sh, "DataShield")) tryCatch(sh$close(), error = function(e) NULL)
      })
    })

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
    if (inherits(session_client$data_shield,"DataShield"))
      session_client$data_shield$set_egress_ask(interaction$egress_ask_fn)
    # NB: tools are registered LAZILY in the onFlushed() init below (after the UI
    # + progress overlay render). Registering here would block the first flush and
    # defeat the instant-UI / overlay. (server_settings re-registers on mode change.)

    stream_task <- server_chat(input, output, session,
                               chat            = chat_obj,
                               settings        = settings,
                               state           = state,
                               cwd             = cwd,
                               chat_server_mod = chat_server_mod,
                               drawer_id       = if (identical(ui_layout, "page_chat"))
                                 "chat" else NULL)

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
      # Harness-only/session factories register tools lazily; install/re-install
      # the shield afterwards so newly attached tools capture this session state.
      if (inherits(session_client$data_shield, "DataShield"))
        tryCatch(session_client$data_shield$install(chat_obj), error = function(e) NULL)
      state$initializing <- FALSE
    }, once = TRUE)

    # Auto-continue: restore only after the first UI flush. The former
    # url_hostname-bound observer could run before shinychat was ready on the
    # fast tools-ready path, so replay calls were silently lost; slow deferred
    # initialization merely hid the race.
    session$onFlushed(function() {
      if (!isTRUE(settings$auto_continue %||% FALSE)) return()
      sid <- tryCatch(
        restore_session_into_chat(chat_obj, session_id = NULL, cwd = cwd),
        error = function(e) NULL)
      if (!is.null(sid)) {
        state$session_id <- sid
        # A restored conversation must never carry a stale live approval/question
        # pause: pending_interaction is per-session UI state, not conversation.
        state$pending_interaction <- NULL
        shinychat::chat_clear("chat", session = session)
        # Replay via contents_shinychat -- native tool card rendering.
        .replay_turns_to_ui(chat_obj, session, settings)
        # Refresh the CONTEXT token meter for the auto-restored conversation.
        tryCatch({
          n_tokens <- token_count_with_estimation(chat_obj, allow_network = FALSE)
          session$sendCustomMessage("update_budget",
            .budget_payload(n_tokens, settings$model_limit %||% 200000L,
                            settings$model %||% ""))
        }, error = function(e) NULL)
      }
    }, once = TRUE)

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
                 exclude = file_tree_exclude,
                 drawer_id = if (identical(ui_layout, "page_chat"))
                   "chat" else NULL)

    if (identical(ui_layout, "page_chat")) {
      shiny::observeEvent(input$ca_workspace_toggle, {
        .shinychat_drawer_action("chat", "toggle", session = session)
      }, ignoreInit = TRUE)
    }

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
