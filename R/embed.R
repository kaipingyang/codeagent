# Embedding codeagent in a host Shiny app.
#
# codeagent_app() is a complete app. A host that already has its own page --
# its own panels, its own tools -- needs the same chat engine without the
# rest: streaming with compaction and interrupt, the approval / question bar,
# the generative UI canvas, Data Shield, and per-turn session saving. The
# pieces below expose exactly that engine; codeagent_app() is built on the
# same session core (.codeagent_session_server()).
#
# The chat input id is fixed to "chat" and the interaction bar renders into
# output "ca_interaction_ui": the server modules address both by name.

#' Chat UI for a host app that embeds codeagent
#'
#' A `shinychat::chat_ui()` configured the way [codeagent_server()] expects:
#' the input id is `"chat"`, the approval / question bar sits above the input
#' (it renders into output `ca_interaction_ui`), cancel is enabled, and tool
#' calls are grouped per tool. Place it anywhere in the host page, together
#' with [codeagent_head_assets()].
#'
#' @param ... Further arguments passed to [shinychat::chat_ui()]; they override
#'   the defaults described above (except `id`).
#' @param greeting Optional greeting (markdown or HTML string, or a
#'   [shinychat::chat_greeting()]). A string is shown as a persistent greeting.
#' @param footer Optional extra UI placed under the interaction bar.
#' @return A Shiny tag.
#' @seealso [codeagent_server()], [codeagent_canvas_ui()]
#' @export
codeagent_chat_ui <- function(..., greeting = NULL, footer = NULL) {
  args <- list(
    id            = "chat",
    fill          = TRUE,
    drawer        = FALSE,
    show_history  = FALSE,
    enable_cancel = TRUE,
    tool_grouping = "tool",
    `aside-favicon` = "false",
    footer = htmltools::tagList(shiny::uiOutput("ca_interaction_ui"), footer)
  )
  if (!is.null(greeting)) {
    args$greeting <- if (is.character(greeting))
      shinychat::chat_greeting(greeting, persistent = TRUE) else greeting
  }
  extra <- list(...)
  extra$id <- NULL
  do.call(shinychat::chat_ui, utils::modifyList(args, extra))
}

#' Generative UI canvas for a host app
#'
#' The container [codeagent_server()] mounts canvas components into, with its
#' "Refresh data" toolbar. Put it wherever the host wants the canvas (a card, a
#' tab, a sidebar) and pass the same `canvas` options to [codeagent_server()].
#' Only one canvas per page. The canvas's Content Security Policy (`csp`) applies
#' to the whole host page: if the host itself shows external images, media or
#' frames, pass `canvas_options(csp = FALSE)` or a policy string that allows them.
#'
#' @param canvas Options from [canvas_options()].
#' @return A Shiny tag.
#' @export
codeagent_canvas_ui <- function(canvas = canvas_options()) {
  if (!inherits(canvas, "codeagent_canvas_options"))
    stop("`canvas` must come from canvas_options().", call. = FALSE)
  csp <- if (isTRUE(canvas$csp)) .GENUI_CSP else
    if (is.character(canvas$csp)) canvas$csp else NULL
  htmltools::tagList(
    if (!is.null(csp)) htmltools::tags$head(htmltools::tags$meta(
      `http-equiv` = "Content-Security-Policy", content = csp)),
    # One fill column: the toolbar keeps its height and the canvas pane takes
    # the rest and scrolls, so the host never grows a second scrollbar.
    htmltools::div(
      class = "html-fill-container html-fill-item",
      style = "height:100%;min-height:0;display:flex;flex-direction:column;",
      htmltools::div(
        class = "ca-genui-toolbar",
        bslib::toolbar(
          bslib::toolbar_input_button(
            "ca_genui_refresh", "Refresh data", icon = shiny::icon("rotate"),
            show_label = TRUE,
            tooltip = "Redraw every component from the current data frames"),
          align = "right")
      ),
      htmltools::div(
        class = "html-fill-item ca-genui-pane",
        style = "flex:1 1 auto;min-height:0;overflow:auto;",
        htmltools::div(
          id = .GENUI_CANVAS_ID, class = "genui-canvas",
          `data-placeholder` = "Canvas components will appear here.")
      )
    )
  )
}

#' Browser assets for a host app that embeds codeagent
#'
#' Registers codeagent's static resource path and returns its `<head>` assets
#' (input busy state, tool-card styles, syntax highlighting). Include once in
#' the host UI.
#'
#' @return A `tags$head()` tag.
#' @export
codeagent_head_assets <- function() {
  www <- system.file("www", package = "codeagent")
  if (nzchar(www)) shiny::addResourcePath("codeagent-www", www)
  head_assets()
}

#' Run codeagent's chat engine inside a host Shiny app
#'
#' Wires the same server side that [codeagent_app()] uses -- streaming with
#' per-turn compaction, stop / ESC interrupt, `/skill` commands, hooks, token
#' budget and per-turn session saving; the approval and question bar
#' (`AskUserQuestion`); the generative UI canvas; and Data Shield -- to a
#' client the host built for this Shiny session. Pair it with
#' [codeagent_chat_ui()] and [codeagent_head_assets()], and with
#' [codeagent_canvas_ui()] when `canvas` is given.
#'
#' Build the client per session with `codeagent_client(..., register_tools =
#' FALSE)`; tools are registered once the UI has flushed, after the Shiny
#' approval / question callbacks exist, so the interactive tools are created
#' in their UI-gated form. Select built-in tools with the client's `tools=`.
#'
#' @param input,output,session The Shiny server arguments.
#' @param client A [codeagent_client()] built for this session.
#' @param tools Host tools (a list of `ellmer::tool()` definitions). Each must
#'   have a capability in `tool_meta`. They are registered after the built-in
#'   tools, with codeagent's result normalization, behind the permission gate
#'   and Data Shield.
#' @param tool_meta Named list or character vector: host tool name ->
#'   capability (`"read"`, `"write"`, `"exec"` or `"net"`).
#' @param canvas `NULL` (no canvas) or [canvas_options()] to enable the
#'   generative UI canvas; place [codeagent_canvas_ui()] in the page. With a
#'   `tools=` selection on the client, include `"genui"` in it.
#' @return Invisibly, a list with `state` (the session `reactiveValues`),
#'   `stream_task` (the `ExtendedTask`), `chat` and `settings`.
#' @seealso [codeagent_chat_ui()], [codeagent_canvas_ui()], [codeagent_app()]
#' @export
codeagent_server <- function(input, output, session, client, tools = list(),
                             tool_meta = list(), canvas = NULL) {
  if (!inherits(client, "CodeagentClient"))
    stop("`client` must be a CodeagentClient (see codeagent_client()).", call. = FALSE)
  if (!is.null(canvas) && !inherits(canvas, "codeagent_canvas_options"))
    stop("`canvas` must be NULL or come from canvas_options().", call. = FALSE)
  .check_host_tools(tools, tool_meta)
  # One live browser session per client: a second session on the same Chat
  # would rebind the approval / question / form callbacks and the canvas to
  # itself, so prompts meant for one user would show in another's page. A
  # reload (the previous session closed) may take the client over.
  prev <- attr(client$chat, "codeagent_server_session")
  if (!is.null(prev) && !identical(prev, session) &&
      !isTRUE(tryCatch(prev$isClosed(), error = function(e) TRUE)))
    stop("This client is already serving another open Shiny session. Build one ",
         "client per session (inside the server function).", call. = FALSE)
  attr(client$chat, "codeagent_server_session") <- session
  if (!is.null(canvas) && !.tool_spec_allows_genui(client$settings$tools_spec))
    warning("[codeagent] `canvas` was given but the client's `tools=` selection ",
            "leaves out the canvas tools, so the model cannot draw. Add \"genui\" ",
            "to `tools=`.", call. = FALSE)
  core <- .codeagent_session_server(
    input, output, session, client,
    canvas = canvas, canvas_explicit = !is.null(canvas), per_session = TRUE,
    tools_ready = FALSE, host_tools = tools, tool_meta = tool_meta)
  # shinychat slash-command typeahead for skills and local commands ("/").
  server_slash(input, session, cwd = core$settings$cwd %||% getwd(),
               stream_task = core$stream_task, chat = client$chat,
               settings = core$settings, state = core$state)
  session$onFlushed(function() core$ready(), once = TRUE)
  invisible(list(state = core$state, stream_task = core$stream_task,
                 chat = client$chat, settings = core$settings))
}

.check_host_tools <- function(tools, tool_meta) {
  if (!is.list(tools) || (length(tools) &&
      !all(vapply(tools, function(t) inherits(t, "ellmer::ToolDef"), logical(1L)))))
    stop("`tools` must be a list of ellmer::tool() definitions.", call. = FALSE)
  names_ <- vapply(tools, function(t) t@name, character(1L))
  meta <- as.list(tool_meta)
  missing <- setdiff(names_, names(meta))
  if (length(missing))
    stop("Declare a capability in `tool_meta` for host tool(s): ",
         paste(missing, collapse = ", "),
         " (\"read\", \"write\", \"exec\" or \"net\").", call. = FALSE)
  caps <- c("read", "write", "exec", "net")
  bad <- names(meta)[!vapply(meta, function(m)
    is.character(m) && length(m) == 1L && !is.na(m) && m %in% caps, logical(1L))]
  if (length(bad))
    stop("`tool_meta` must map each tool to one of \"read\", \"write\", \"exec\", ",
         "\"net\"; invalid for: ", paste(bad, collapse = ", "), ".", call. = FALSE)
  builtin <- intersect(names_, names(.TOOL_META))
  if (length(builtin))
    stop("Host tool name(s) clash with codeagent built-in tools: ",
         paste(builtin, collapse = ", "), ". Rename them.", call. = FALSE)
  invisible(TRUE)
}

# Host tools: declared capability, then registration. Called from
# .register_all_tools() (settings$host_tools), so result normalization, input
# hooks, disallowed_tools, the gate and the shield cover them like built-ins.
.register_host_tools <- function(chat, tools, tool_meta) {
  if (!length(tools)) return(invisible(chat))
  meta <- as.list(tool_meta)
  for (tool in tools) {
    register_tool_meta(tool@name, meta[[tool@name]])
    chat$register_tool(tool)
  }
  invisible(chat)
}

# The per-session engine shared by codeagent_app() and codeagent_server().
# Returns the session state, the stream task, the (updated) settings, and
# ready(): the deferred initialization to run once the UI has flushed. It
# returns TRUE when this session got a live canvas.
.codeagent_session_server <- function(input, output, session, client,
                                      canvas = NULL, canvas_explicit = FALSE,
                                      per_session = TRUE, tools_ready = FALSE,
                                      host_tools = list(), tool_meta = list(),
                                      drawer_id = NULL, settings_overrides = list()) {
  chat <- client$chat
  settings <- client$settings
  for (nm in names(settings_overrides)) settings[[nm]] <- settings_overrides[[nm]]
  settings$host_tools     <- host_tools
  settings$host_tool_meta <- tool_meta
  cwd <- settings$cwd %||% getwd()

  # Generative UI canvas: an adapter per Chat, created cheaply here and
  # prepared in ready(). A shared pre-built client keeps one adapter on its
  # Chat, so a second browser session poisons it instead of silently taking
  # over the first session's canvas.
  if (!is.null(canvas) && .genui_wanted(settings, per_session = per_session,
                                        options = canvas, explicit = canvas_explicit)) {
    adapter <- attr(chat, "codeagent_genui") %||%
      GenUIAdapter$new(prepare = FALSE, options = canvas)
    attr(chat, "codeagent_genui") <- adapter
    settings$genui <- adapter
  }

  # SessionEnd hook (CC parity) and filesystem-watch hooks; release the Data
  # Shield's sensitive state at teardown (close() is idempotent).
  local({
    sess_hooks <- tryCatch(settings$hooks_registry, error = function(e) NULL)
    watch_handle <- tryCatch(.start_hook_watchers(sess_hooks, cwd = cwd),
                             error = function(e) NULL)
    session$onSessionEnded(function() {
      if (!is.null(watch_handle)) tryCatch(watch_handle$stop(), error = function(e) NULL)
      if (!is.null(sess_hooks))
        tryCatch(sess_hooks$run_session_end("other", list()),
                 error = function(e) NULL)
      sh <- tryCatch(settings$data_shield_engine, error = function(e) NULL)
      if (inherits(sh, "DataShield")) tryCatch(sh$close(), error = function(e) NULL)
    })
  })

  state <- shiny::reactiveValues(
    session_id      = tryCatch(.generate_uuid_v4(), error = function(e) "default"),
    initializing    = TRUE,       # deferred tool registration in progress -> gate input
    init_step       = "Loading tools & skills\u2026",
    iteration       = 0L,
    interrupt       = FALSE,
    main_output     = NULL,
    settings_changed = 0L,
    sessions_dirty  = 0L,
    pending_interaction = NULL,   # approval / question pause slot
    compaction_ctrl = CompactionController$new(),
    budget_tracker  = BudgetTracker$new(),
    resource_state  = ContentReplacementState$new()
  )

  # Interaction bar + promise-returning ask callbacks, stashed in settings
  # BEFORE ready() registers tools, so the interactive tools (Write/Edit/Bash/
  # RunR + AskUserQuestion) are built in their async, UI-gated form.
  interaction <- server_interaction(input, output, session, state)
  settings$shiny_ask_fn          <- interaction$ask_fn
  settings$shiny_ask_question_fn <- interaction$ask_question_fn
  settings$shiny_ask_form_fn     <- interaction$ask_form_fn
  if (inherits(client$data_shield, "DataShield"))
    client$data_shield$set_egress_ask(interaction$egress_ask_fn)

  stream_task <- server_chat(input, output, session,
                             chat = chat, settings = settings, state = state,
                             cwd = cwd, chat_server_mod = NULL,
                             drawer_id = drawer_id)
  .genui_server(input, session, settings, stream_task)

  ready <- function() {
    genui_on <- .genui_attach(settings, session)
    if (!isTRUE(tools_ready) || isTRUE(genui_on) || length(host_tools)) {
      err <- tryCatch({ .register_all_tools(chat, settings); NULL },
                      error = function(e) conditionMessage(e))
      if (!is.null(err)) {
        # Fail closed: a partial registration may hold tools built for an
        # ungated chat. Drop them all and keep the input disabled.
        tryCatch(chat$set_tools(list()), error = function(e) NULL)
        state$init_step <- paste0("Tool setup failed: ", err)
        .ui_toast(paste0("codeagent could not set up its tools: ", err), "error")
        return(FALSE)
      }
    }
    if (isTRUE(genui_on))
      tryCatch(.sync_genui_prompt(chat, settings), error = function(e) NULL)
    # Tools attach lazily; (re)install the shield so they capture this session.
    if (inherits(client$data_shield, "DataShield"))
      tryCatch(client$data_shield$install(chat), error = function(e) NULL)
    state$initializing <- FALSE
    isTRUE(genui_on)
  }

  list(state = state, stream_task = stream_task, settings = settings, ready = ready)
}

# Does a `tools=` selection keep the canvas tools? NULL / "everything" does.
.tool_spec_allows_genui <- function(spec) {
  is.null(spec) || isTRUE(spec$all) || any(.genui_tool_names() %in% spec$native)
}
