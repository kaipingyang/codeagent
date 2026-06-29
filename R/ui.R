#' @title Shiny UI — codeagent_app()
#' @description Three-panel layout: left sidebar (Sessions/Customizations/Settings) +
#'   chat panel + main output panel.
#' @name ui
#' @keywords internal
NULL

#' Launch the codeagent Shiny application
#'
#' @param client A `CodagentClient` from [codeagent_client()], an
#'   `ellmer::Chat`, or NULL (legacy mode).
#' @param pinned_skills Character vector. Skill names pinned at top of Skills panel.
#' @param port Integer or NULL. Shiny port (NULL = random).
#' @param launch.browser Logical. Open in browser (default TRUE).
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
  port            = NULL,
  launch.browser  = TRUE,
  # Legacy params
  model           = NULL,
  permission_mode = "default",
  cwd             = getwd(),
  btw_groups      = NULL,
  chat            = NULL
) {

  # Resolve to CodagentClient ------------------------------------------------
  if (inherits(client, "CodagentClient")) {
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

  # ---------------------------------------------------------------------------
  # UI
  # ---------------------------------------------------------------------------
  ui <- bslib::page_sidebar(
    fillable = TRUE,
    padding  = 8,
    header   = head_assets(),
    sidebar  = bslib::sidebar(
      id        = "ca_left_sidebar",
      width     = 240,
      resizable = TRUE,
      padding   = 8,
      left_sidebar_ui(
        permission_mode      = permission_mode,
        btw_available_groups = btw_available_groups,
        btw_groups_selected  = btw_groups
      )
    ),
    bslib::layout_sidebar(
      fill     = TRUE,
      fillable = TRUE,
      border   = FALSE,
      sidebar  = bslib::sidebar(
        id        = "ca_output_sidebar",
        position  = "right",
        width     = "45%",
        resizable = TRUE,
        fillable  = TRUE,
        padding   = 0,
        main_output_ui()
      ),
      bslib::card(
        fill = TRUE,
        chat_sidebar_ui(skill_meta)
      )
    )
  )

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------
  server <- function(input, output, session) {

    # Shared reactive state (single reactiveValues, no scattered reactiveVal)
    state <- shiny::reactiveValues(
      session_id      = NULL,
      iteration       = 0L,
      interrupt       = FALSE,
      main_output     = NULL,
      compaction_ctrl = CompactionController$new(),
      budget_tracker  = BudgetTracker$new(),
      resource_state  = ContentReplacementState$new()
    )

    # Wire server modules
    stream_task <- server_chat(input, output, session,
                               chat     = chat_obj,
                               settings = settings,
                               state    = state,
                               cwd      = cwd)

    server_sessions(input, output, session,
                    chat        = chat_obj,
                    cwd         = cwd,
                    state       = state,
                    stream_task = stream_task)

    server_settings(input, output, session,
                    chat     = chat_obj,
                    settings = settings,
                    cwd      = cwd)

    server_customizations(input, output, session,
                          chat     = chat_obj,
                          settings = settings,
                          cwd      = cwd)

    server_skills(input, output, session,
                  cwd           = cwd,
                  pinned_skills = pinned_skills)

    server_right(input, output, session,
                 cwd   = cwd,
                 state = state)

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
