#' @title Shiny UI -- codeagent_app()
#' @description Three-panel layout: left sidebar (Sessions/Customizations/Settings) +
#'   chat panel + main output panel.
#' @name ui
#' @keywords internal
NULL

#' Launch the codeagent Shiny application
#'
#' @param client A `CodeagentClient` from [codeagent_client()], an
#'   `ellmer::Chat`, or NULL (legacy mode).
#' @param pinned_skills Character vector. Skill names pinned at top of Skills panel.
#' @param greeting Character or NULL. If provided, pre-fills the chat input box
#'   with this text on startup (used by the "Chat about selection" IDE addin to
#'   seed the first message with the selected code). NULL leaves the input empty.
#' @param port Integer or NULL. Shiny port (NULL = random).
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
  pinned_skills   = character(0),
  greeting        = NULL,
  port            = NULL,
  launch.browser  = TRUE,
  file_tree_show_hidden = FALSE,
  file_tree_exclude = c("renv", "node_modules", "packrat", ".git", ".Rproj.user"),
  # Legacy params
  model           = NULL,
  permission_mode = "default",
  cwd             = getwd(),
  btw_groups      = NULL,
  chat            = NULL
) {

  # Resolve to CodeagentClient ------------------------------------------------
  if (inherits(client, "CodeagentClient")) {
    ca_client <- client
  } else {
    raw_chat <- if (inherits(client, "Chat")) client else chat
    ca_client <- codeagent_client(
      chat            = raw_chat,
      permission_mode = permission_mode,
      cwd             = cwd,
      btw_groups      = btw_groups
    )
    if (!is.null(model)) ca_client$settings$model <- model
  }

  chat_obj <- ca_client$chat
  settings <- ca_client$settings
  cwd      <- settings$cwd %||% getwd()

  # Static assets
  www_dir <- system.file("www", package = "codeagent")
  if (nzchar(www_dir))
    shiny::addResourcePath("codeagent-www", www_dir)

  # Skill meta for footer picker
  skill_meta <- tryCatch({
    metas <- list_skills_meta(cwd)
    data.frame(
      key   = vapply(metas, `[[`, character(1), "name"),
      label = paste0("/", vapply(metas, `[[`, character(1), "name")),
      desc  = vapply(metas, function(m) m$description %||% "", character(1)),
      stringsAsFactors = FALSE
    )
  }, error = function(e) {
    data.frame(
      key   = c("plan", "compact", "verify"),
      label = c("/plan", "/compact", "/verify"),
      desc  = c("Break work into steps", "Make replies shorter", "Verify last action"),
      stringsAsFactors = FALSE
    )
  })

  # btw groups for Settings panel
  btw_available_groups <- tryCatch({
    if (requireNamespace("btw", quietly = TRUE)) sort(names(.BTW_GROUPS))
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
  ui <- bslib::page_sidebar(
    fillable = TRUE,
    head_assets(),
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
        chat_codeagent_ui(skill_meta)
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
      iteration       = 0L,
      interrupt       = FALSE,
      main_output     = NULL,
      settings_changed = 0L,
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
    # promise-returning Shiny ask callbacks. Stash them in `settings` so that
    # .register_all_tools() (here AND on later permission-mode changes in
    # server_settings) rebuilds the interactive tools (Write/Edit/MultiEdit/
    # Bash/RunR + AskUserQuestion) as async, UI-gated variants.
    interaction <- server_interaction(input, output, session, state)
    settings$shiny_ask_fn          <- interaction$ask_fn
    settings$shiny_ask_question_fn <- interaction$ask_question_fn
    tryCatch(.register_all_tools(chat_obj, settings), error = function(e) NULL)

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

    # Auto-continue: restore the most recent session on startup so users
    # pick up where they left off (mirrors `codeagent chat --continue`).
    shiny::observe({
      shiny::req(TRUE)   # run once at startup
      sid <- tryCatch(
        restore_session_into_chat(chat_obj, session_id = NULL, cwd = cwd),
        error = function(e) NULL)
      if (!is.null(sid)) {
        state$session_id <- sid
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
