#' @title Shiny UI — codeagent_app()
#' @description Three-panel layout: left sidebar (Sessions/Skills/Settings) +
#'   chat sidebar + main output panel (files/tool results/interactive content).
#'   Left and chat sidebars are bslib-native resizable.
#' @name ui
#' @keywords internal
NULL

#' Launch the codeagent Shiny application
#'
#' Two calling conventions:
#'
#' **New (recommended):** pass a [codeagent_client()] as first argument.
#' ```r
#' client <- codeagent_client(
#'   chat_openai_compatible(...),
#'   permission_mode = "bypass"
#' )
#' codeagent_app(client, pinned_skills = c("plan"), theme = "default")
#' ```
#'
#' **Legacy:** pass model/permission_mode/etc. directly or supply `chat=`.
#'
#' @param client A `CodagentClient` from [codeagent_client()], an
#'   `ellmer::Chat`, or NULL (legacy mode).
#' @param pinned_skills Character vector. Skill names pinned at top of Skills panel.
#' @param theme Character. `"default"` (bslib-native), `"flatly"`,
#'   `"darkly"`, or `"glass"`.
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
  theme           = c("default", "flatly", "darkly", "glass"),
  port            = NULL,
  launch.browser  = TRUE,
  # Legacy params
  model           = NULL,
  permission_mode = "default",
  cwd             = getwd(),
  btw_groups      = NULL,
  chat            = NULL
) {
  theme <- match.arg(theme)

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
  .bs_theme <- if (identical(theme, "default")) {
    bslib::bs_theme()
  } else if (identical(theme, "flatly")) {
    bslib::bs_theme(bootswatch = "flatly")
  } else if (identical(theme, "darkly")) {
    bslib::bs_theme(bootswatch = "darkly")
  } else {
    bslib::bs_theme(
      bootswatch    = "darkly",
      bg            = "#0f0c29",
      fg            = "rgba(255,255,255,0.92)",
      "body-bg"     = "#0f0c29",
      "body-color"  = "rgba(255,255,255,0.92)",
      "border-color"    = "rgba(255,255,255,0.10)",
      "secondary-color" = "rgba(255,255,255,0.45)",
      "tertiary-bg"     = "rgba(255,255,255,0.07)",
      "secondary-bg"    = "rgba(255,255,255,0.12)",
      primary   = "#a855f7",
      secondary = "#06b6d4",
      base_font = bslib::font_google("Inter")
    )
  }

  ui <- bslib::page_fillable(
    theme   = .bs_theme,
    padding = 8,
    head_assets(theme),
    bslib::layout_columns(
      col_widths = c(2, 10),
      fill       = TRUE,
      bslib::card(
        id   = "ca_left_card",
        fill = TRUE,
        left_sidebar_ui(
          permission_mode      = permission_mode,
          btw_available_groups = btw_available_groups,
          btw_groups_selected  = btw_groups
        )
      ),
      bslib::layout_sidebar(
        border   = FALSE,
        fillable = TRUE,
        sidebar  = bslib::sidebar(
          id        = "ca_chat_sidebar",
          position  = "left",
          width     = "50%",
          resizable = TRUE,
          padding   = 0,
          fillable  = TRUE,
          chat_sidebar_ui(skill_meta)
        ),
        main_output_ui()
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
