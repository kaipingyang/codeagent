#' @title Shiny interaction pause mechanism (Phase 3)
#' @description Shared "pause -> wait for user -> resume" machinery for three
#'   features that ride the same promise-as-pause-signal design:
#'
#'   * **ask_fn** -- harness permission approval (Allow/Deny a risky tool).
#'   * **ask_question_fn** -- `AskUserQuestion` clarifying-question input.
#'   * **egress_ask_fn** -- Data Shield result choice (redact/block/raw-once).
#'
#'   All store a single `state$pending_interaction` slot and expose an
#'   interaction bar in the chat footer. The promise returned by the ask
#'   functions is awaited by the (async) tool inside the streaming task; it is
#'   resolved by the Allow/Deny/Submit observers here.
#'
#'   Hard-won constraints (see `inst/examples/test_shiny_ask_fn.R`):
#'   * The promise is ONLY a container for `resolve`; never use `then()` to do
#'     UI side effects (then() runs with a NULL reactive domain).
#'   * All UI side effects happen inside the Allow/Deny/Submit observers, which
#'     run in the correct reactive domain.
#' @name server_interaction
#' @keywords internal
NULL

# Build the promise-returning ask_fn (permission approval). Called from inside
# an async tool; returns promise<logical>. resolve(TRUE/FALSE) is called by the
# Allow/Deny observers.
.shiny_ask_fn <- function(session, state) {
  function(tool_name, tool_input) {
    promises::promise(function(resolve, reject) {
      shiny::isolate({
        state$pending_interaction <- list(
          type    = "approval",
          payload = list(tool_name = tool_name, tool_input = tool_input),
          resolve = resolve
        )
      })
    })
  }
}

# Build the promise-returning ask_question_fn (AskUserQuestion). Returns
# promise<character>. resolve(answer) is called by the Submit observer.
.shiny_ask_question_fn <- function(session, state) {
  function(question, choices = NULL) {
    promises::promise(function(resolve, reject) {
      shiny::isolate({
        state$pending_interaction <- list(
          type    = "question",
          payload = list(question = question,
                         choices  = as.character(choices %||% character(0))),
          resolve = resolve
        )
      })
    })

  }
}

# Build the promise-returning ask_form_fn (AskUserForm). Returns
# promise<list(submitted=, values=)>; resolved by the form Submit / Cancel
# observers (or ESC).
.shiny_ask_form_fn <- function(session, state) {
  function(title, fields, submit_label = "Submit") {
    promises::promise(function(resolve, reject) {
      shiny::isolate({
        state$pending_interaction <- list(
          type    = "form",
          payload = list(title = title, fields = fields,
                         submit_label = submit_label %||% "Submit"),
          resolve = resolve
        )
      })
    })
  }
}

# Input id of a form field: positional, so ids stay valid Shiny ids whatever
# the model named the field. Only one form is pending at a time.
.form_input_id <- function(i) paste0("ca_form_", i)

# One Shiny input for a validated form field (see .form_validate_fields). PURE.
.form_field_input <- function(field, i) {
  id <- .form_input_id(i)
  label <- if (isTRUE(field$required)) paste0(field$label, " *") else field$label
  def <- field$default
  input <- switch(field$type,
    text     = shiny::textInput(id, label, value = def, width = "100%"),
    textarea = shiny::textAreaInput(id, label, value = def, width = "100%", rows = 3),
    number   = shiny::numericInput(id, label,
                                   value = suppressWarnings(as.numeric(def)), width = "100%"),
    select   = shiny::selectInput(id, label, choices = field$choices,
                                  selected = if (nzchar(def)) def else field$choices[1],
                                  width = "100%"),
    multiselect = shiny::selectInput(
      id, label, choices = field$choices, multiple = TRUE, width = "100%",
      selected = if (nzchar(def)) trimws(strsplit(def, ",", fixed = TRUE)[[1]]) else NULL),
    checkbox = shiny::checkboxInput(id, label, value = isTRUE(as.logical(def))),
    date     = shiny::dateInput(id, label, value = if (nzchar(def)) def else NULL,
                                width = "100%")
  )
  htmltools::tagList(
    input,
    if (nzchar(field$help))
      htmltools::tags$small(class = "form-text text-muted d-block mb-2", field$help)
  )
}

# Build the promise-returning Data Shield egress approval callback. Payload is
# non-sensitive metadata only; raw result stays inside the tool wrapper.
.shiny_egress_ask_fn <- function(session, state) {
  function(event) {
    promises::promise(function(resolve, reject) {
      token <- tryCatch(.generate_uuid_v4(),error=function(e)paste0("egress-",Sys.time()))
      shiny::isolate({
        state$pending_interaction <- list(
          type="egress", token=token, payload=event, resolve=resolve)
      })
      timeout <- max(0,as.numeric(event$timeout %||% 60))
      later::later(function() {
        if (isTRUE(tryCatch(session$isClosed(),error=function(e) TRUE)))
          return(invisible(NULL))
        pending <- shiny::isolate(state$pending_interaction)
        if (!is.null(pending) && identical(pending$type,"egress") &&
            identical(pending$token,token))
          .resolve_pending(state,"redact")
      },delay=timeout)
    })
  }
}

# Resolve + clear the pending interaction safely (idempotent).
.resolve_pending <- function(state, value) {
  pending <- shiny::isolate(state$pending_interaction)
  if (is.null(pending)) return(invisible(FALSE))
  state$pending_interaction <- NULL
  tryCatch(pending$resolve(value), error = function(e) NULL)
  invisible(TRUE)
}

# Build the in-chat interaction bar for a pending approval / question. PURE:
# takes the `pending` list (or NULL) and returns an htmltools tag (or NULL); no
# Shiny input/output/session, so the bar's layout is unit-testable. The
# observers below own all side effects (append messages, resolve the promise).
.interaction_bar_ui <- function(pending) {
  if (is.null(pending)) return(NULL)

  if (identical(pending$type, "approval")) {
    p    <- pending$payload
    tin  <- p$tool_input %||% list()
    desc <- as.character(tin$command %||% tin$file_path %||% "")
    htmltools::tags$div(
      style = paste(
        "border-top:2px solid var(--bs-warning,#f0ad4e);",
        "background:var(--bs-body-bg,#fff);",
        "padding:8px 16px; display:flex; align-items:center; gap:12px;",
        "text-align:left;",   # footer sets text-align:center; override it
        "box-shadow:0 -2px 8px rgba(0,0,0,.08);"
      ),
      htmltools::tags$span(
        style = "font-weight:600; flex:1; font-size:0.9em;",
        "\u26a0\ufe0f Allow tool: ", htmltools::tags$code(p$tool_name %||% "?"),
        htmltools::tags$small(
          style = "color:#666; font-weight:400;",
          if (nzchar(desc)) paste0(" \u2014 ", substr(desc, 1L, 80L)) else ""
        )
      ),
      shiny::actionButton("ca_tool_allow", "\u2714 Allow",
                          class = "btn-success btn-sm"),
      shiny::actionButton("ca_tool_deny", "\u2716 Deny",
                          class = "btn-danger btn-sm")
    )
  } else if (identical(pending$type, "question")) {
    p       <- pending$payload
    choices <- p$choices
    htmltools::tags$div(
      style = paste(
        "border-top:2px solid var(--bs-info,#0dcaf0);",
        "background:var(--bs-body-bg,#fff);",
        "padding:8px 16px; text-align:left;",   # override footer centering
        "box-shadow:0 -2px 8px rgba(0,0,0,.08);"
      ),
      htmltools::tags$p(style = "font-weight:600; margin-bottom:6px;",
                        "\u2753 ", p$question %||% ""),
      if (length(choices) > 0L)
        shiny::radioButtons("ca_q_choice", NULL, choices = choices,
                            inline = FALSE)
      else
        shiny::textInput("ca_q_text", NULL,
                         placeholder = "Type your answer..."),
      shiny::actionButton("ca_q_submit", "Submit", class = "btn-primary btn-sm")
    )
  } else if (identical(pending$type, "form")) {
    p <- pending$payload
    htmltools::tags$div(
      class = "ca-form-bar",
      style = paste(
        "border-top:2px solid var(--bs-primary,#0d6efd);",
        "background:var(--bs-body-bg,#fff);",
        "padding:8px 16px; text-align:left;",   # override footer centering
        "box-shadow:0 -2px 8px rgba(0,0,0,.08);",
        "max-height:60vh; overflow-y:auto;"
      ),
      htmltools::tags$p(style = "font-weight:600; margin-bottom:6px;",
                        "\U0001f4dd ", p$title %||% ""),
      htmltools::tagList(lapply(seq_along(p$fields), function(i)
        .form_field_input(p$fields[[i]], i))),
      htmltools::tags$div(
        style = "display:flex; gap:8px; margin-top:4px;",
        shiny::actionButton("ca_form_submit", p$submit_label %||% "Submit",
                            class = "btn-primary btn-sm"),
        shiny::actionButton("ca_form_cancel", "Cancel",
                            class = "btn-outline-secondary btn-sm"))
    )
  } else if (identical(pending$type, "egress")) {
    p <- pending$payload
    htmltools::tags$div(
      style = paste(
        "border-top:2px solid var(--bs-danger,#dc3545);",
        "background:var(--bs-body-bg,#fff);",
        "padding:8px 16px; display:flex; align-items:center; gap:10px;",
        "text-align:left; box-shadow:0 -2px 8px rgba(0,0,0,.08);"),
      htmltools::tags$span(
        style="font-weight:600; flex:1; font-size:0.9em;",
        "Data Shield blocked a tool result: ",
        htmltools::tags$code(p$tool_name %||% "?"),
        htmltools::tags$small(
          style="display:block;color:#666;font-weight:400;",
          paste0(p$strategy %||% "policy", " \u2014 ", p$reason %||% "policy match",
                 " (matches: ", as.integer(p$match_count %||% 0L), ")"))),
      shiny::actionButton("ca_egress_redact","Redact and continue",
                          class="btn-warning btn-sm"),
      shiny::actionButton("ca_egress_block","Block result",
                          class="btn-secondary btn-sm"),
      if (isTRUE(p$allow_raw_approval))
        shiny::actionButton("ca_egress_raw","ALLOW RAW ONCE",
                            class="btn-danger btn-sm")
    )
  } else {
    NULL
  }
}

# Value to resolve a pending interaction with when the user hits ESC: deny
# (FALSE) an approval, or an empty answer ("") a question. PURE.
.interaction_cancel_value <- function(pending) {
  if (is.null(pending)) return(NULL)
  if (identical(pending$type, "approval")) return(FALSE)
  if (identical(pending$type, "egress")) return("redact")
  if (identical(pending$type, "form")) return(list(submitted = FALSE))
  ""
}

#' Wire the interaction bar UI + observers into a Shiny session
#'
#' @param input,output,session Standard Shiny server args.
#' @param state The shared `reactiveValues` (must contain `pending_interaction`).
#' @return A list with `ask_fn`, `ask_question_fn`, `ask_form_fn` and
#'   `egress_ask_fn` (promise-returning).
#' @keywords internal
server_interaction <- function(input, output, session, state) {

  # ---- Interaction bar (approval OR question) ----
  # The bar's layout is built by the pure .interaction_bar_ui(); this observer
  # just re-renders it whenever the pending slot changes.
  output$ca_interaction_ui <- shiny::renderUI({
    .interaction_bar_ui(state$pending_interaction)
  })

  # ---- Allow / Deny (permission approval) ----
  shiny::observeEvent(input$ca_tool_allow, ignoreInit = TRUE, {
    if (.resolve_pending(state, TRUE))
      shinychat::chat_append_message(
        "chat", list(role = "assistant", content = "\u2705 Tool allowed."),
        session = session)
  })
  shiny::observeEvent(input$ca_tool_deny, ignoreInit = TRUE, {
    if (.resolve_pending(state, FALSE))
      shinychat::chat_append_message(
        "chat", list(role = "assistant", content = "\u274c Tool denied."),
        session = session)
  })

  # ---- Data Shield egress approval (result already executed, not yet in LLM) ----
  shiny::observeEvent(input$ca_egress_redact, ignoreInit=TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type,"egress")) return()
    .resolve_pending(state,"redact")
  })
  shiny::observeEvent(input$ca_egress_block, ignoreInit=TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type,"egress")) return()
    .resolve_pending(state,"block")
  })
  shiny::observeEvent(input$ca_egress_raw, ignoreInit=TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type,"egress")) return()
    choice <- if (isTRUE(pending$payload$allow_raw_approval)) "raw_once" else "redact"
    .resolve_pending(state,choice)
  })

  # ---- Submit (question answer) ----
  shiny::observeEvent(input$ca_q_submit, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type, "question")) return()
    answer <- input$ca_q_choice %||% input$ca_q_text %||% ""
    .resolve_pending(state, answer)
  })

  # ---- Form submit / cancel (AskUserForm) ----
  # A required field left empty keeps the form open (a re-render would wipe
  # what the user typed), so it is reported with a toast instead.
  shiny::observeEvent(input$ca_form_submit, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type, "form")) return()
    spec <- pending$payload$fields
    raw <- stats::setNames(lapply(seq_along(spec), function(i) input[[.form_input_id(i)]]),
                           vapply(spec, `[[`, character(1L), "name"))
    # dateInput gives a Date; keep the ISO text the model was told about.
    raw <- lapply(raw, function(v) if (inherits(v, "Date")) format(v) else v)
    collected <- .form_collect(spec, raw)
    if (length(collected$missing)) {
      .ui_toast(paste0("Please fill in: ", paste(collected$missing, collapse = ", ")),
                "warning")
      return()
    }
    .resolve_pending(state, list(submitted = TRUE, values = collected$values))
  })
  shiny::observeEvent(input$ca_form_cancel, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type, "form")) return()
    .resolve_pending(state, list(submitted = FALSE))
  })

  # ---- ESC: cancel a pending interaction without deadlocking the loop ----
  # Deny an approval (FALSE) or return an empty answer ("") for a question.
  shiny::observeEvent(input$esc, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending)) return()
    .resolve_pending(state, .interaction_cancel_value(pending))
  })

  list(
    ask_fn          = .shiny_ask_fn(session, state),
    ask_question_fn = .shiny_ask_question_fn(session, state),
    ask_form_fn     = .shiny_ask_form_fn(session, state),
    egress_ask_fn   = .shiny_egress_ask_fn(session, state)
  )
}
