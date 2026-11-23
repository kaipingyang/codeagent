#' @title Shiny interaction pause mechanism (Phase 3)
#' @description Shared "pause -> wait for user -> resume" machinery for three
#'   features that ride the same promise-as-pause-signal design:
#'
#'   * **ask_fn** -- harness permission approval (Allow/Deny a risky tool).
#'   * **ask_question_fn** -- `AskUserQuestion` clarifying-question input.
#'   * **egress_ask_fn** -- Data Shield result choice (redact/block/raw-once).
#'
#'   One request is shown at a time in `state$pending_interaction` (the
#'   interaction bar in the chat footer); requests that arrive meanwhile wait
#'   in `state$interaction_queue` and are shown in order. The promise returned by the ask
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
    # "Always allow" for this tool in this session: no bar.
    if (tool_name %in% (shiny::isolate(state$always_allow) %||% character()))
      return(promises::promise_resolve(TRUE))
    promises::promise(function(resolve, reject) {
      .enqueue_interaction(state, list(
        type    = "approval",
        payload = list(tool_name = tool_name, tool_input = tool_input),
        resolve = resolve
      ))
    })
  }
}

# Build the promise-returning ask_question_fn (AskUserQuestion). Returns
# promise<character> for one question, promise<list> (one answer per question)
# for `questions` (normalized by .normalize_questions()). resolve(answer) is
# called by the Submit observer.
.shiny_ask_question_fn <- function(session, state) {
  function(question, choices = NULL, questions = NULL) {
    if (!is.null(questions)) return(promises::promise(function(resolve, reject) {
      .enqueue_interaction(state, list(type = "questions", payload = list(questions = questions),
                                       resolve = resolve))
    }))
    promises::promise(function(resolve, reject) {
      .enqueue_interaction(state, list(
        type    = "question",
        payload = list(question = question,
                       choices  = as.character(choices %||% character(0))),
        resolve = resolve
      ))
    })

  }
}

# Build the promise-returning ask_form_fn (AskUserForm). Returns
# promise<list(submitted=, values=)>; resolved by the form Submit / Cancel
# observers (or ESC).
.shiny_ask_form_fn <- function(session, state) {
  function(title, fields, submit_label = "Submit") {
    promises::promise(function(resolve, reject) {
      .enqueue_interaction(state, list(
        type    = "form",
        payload = list(title = title, fields = fields,
                       submit_label = submit_label %||% "Submit"),
        resolve = resolve
      ))
    })
  }
}

# Input id of a form field: positional, so ids stay valid Shiny ids whatever
# the model named the field. Only one form is pending at a time.
.form_input_id <- function(i) paste0("ca_form_", i)

# ---- Question card (DSH QuestionComposer look) -----------------------------
# One card for AskUserQuestion: one question per page, options as numbered
# rows (checkbox rows for multiSelect), a "Recommended" badge, a free-text
# row, a pager and Skip / Next|Submit. inst/www/interaction.js keeps the
# answers in the page while the card is open and sends them all at once as
# input$ca_q_answers. PURE.

# A label ending in "(Recommended)" is shown without the suffix and gets a
# badge; the full label is what is submitted.
.question_recommended <- function(label) {
  grepl("\\s*[(\uff08]\\s*(recommended|\u63a8\u8350)\\s*[)\uff09]\\s*$", label,
        ignore.case = TRUE, perl = TRUE)
}
.question_display_label <- function(label) {
  trimws(sub("\\s*[(\uff08]\\s*(recommended|\u63a8\u8350)\\s*[)\uff09]\\s*$", "", label,
             ignore.case = TRUE, perl = TRUE))
}

# The legacy single question (question + choices) in the questions shape.
.question_as_questions <- function(p) {
  list(list(question = p$question %||% "", header = "",
            options = lapply(as.character(p$choices %||% character()), function(ch)
              list(label = ch, description = "")),
            multiSelect = FALSE))
}

.question_page_ui <- function(q, i, n) {
  multi <- isTRUE(q$multiSelect)
  opts <- q$options %||% list()
  labels <- vapply(opts, function(o) as.character(o$label %||% ""), "")
  rec <- vapply(labels, .question_recommended, NA)
  preselect <- if (multi) rec else (seq_along(labels) == 1L & rec)
  marker <- function(k) if (multi)
    htmltools::tags$span(class = "ca-q-check", `aria-hidden` = "true")
  else htmltools::tags$span(class = "ca-q-num", `aria-hidden` = "true", k)
  htmltools::tags$div(
    class = "ca-q-page", `data-i` = i, `data-multi` = if (multi) "true" else "false",
    `data-header` = as.character(q$header %||% ""),
    hidden = if (i > 1L) NA,
    htmltools::tags$h2(class = "ca-q-title", id = paste0("ca_q_title_", i), q$question %||% ""),
    if (length(opts)) htmltools::tags$div(
      class = "ca-q-options", role = if (multi) "group" else "radiogroup",
      `aria-labelledby` = paste0("ca_q_title_", i),
      lapply(seq_along(opts), function(k) {
        o <- opts[[k]]
        desc <- as.character(o$description %||% "")
        htmltools::tags$button(
          type = "button", class = paste("ca-q-option", if (preselect[[k]]) "is-selected"),
          role = if (multi) "checkbox" else "radio",
          `aria-checked` = if (preselect[[k]]) "true" else "false",
          `data-label` = labels[[k]],
          marker(k),
          htmltools::tags$span(class = "ca-q-copy",
            htmltools::tags$span(class = "ca-q-line",
              htmltools::tags$span(class = "ca-q-label", .question_display_label(labels[[k]])),
              if (rec[[k]]) htmltools::tags$span(class = "ca-q-badge", "Recommended")),
            if (nzchar(desc)) htmltools::tags$span(class = "ca-q-desc", desc)))
      }),
      htmltools::tags$label(class = "ca-q-custom",
        if (multi) htmltools::tags$span(class = "ca-q-check", `aria-hidden` = "true")
        else htmltools::tags$span(class = "ca-q-num ca-q-num--pen", `aria-hidden` = "true",
                                  shiny::icon("pen")),
        htmltools::tags$textarea(class = "ca-q-text", rows = "1",
                                 placeholder = "Type your answer",
                                 `aria-label` = "Type your answer")))
    else htmltools::tags$div(class = "ca-q-block",
      htmltools::tags$textarea(class = "ca-q-text", rows = "2",
                               placeholder = "Type your answer",
                               `aria-label` = "Type your answer")))
}

# Question tabs for a set of more than one: each question's header (else
# "Question i"), the current one marked, answered ones ticked; a click goes to
# that question (inst/www/interaction.js). PURE.
.question_nav_ui <- function(qs) {
  htmltools::tags$nav(class = "ca-q-nav", role = "tablist", `aria-label` = "Questions",
    lapply(seq_along(qs), function(i) {
      h <- trimws(as.character(qs[[i]]$header %||% ""))
      htmltools::tags$button(
        type = "button", class = paste("ca-q-nav-item", if (i == 1L) "is-current"),
        role = "tab", `data-i` = i, `aria-selected` = if (i == 1L) "true" else "false",
        title = qs[[i]]$question %||% "",
        htmltools::tags$span(class = "ca-q-nav-mark", `aria-hidden` = "true"),
        htmltools::tags$span(class = "ca-q-nav-label", if (nzchar(h)) h else paste("Question", i)))
    }))
}

.question_card_ui <- function(qs) {
  n <- length(qs)
  header <- as.character(qs[[1]]$header %||% "")
  htmltools::tags$section(
    class = "ca-interaction ca-interaction--questions ca-q-card", `data-n` = n,
    `aria-label` = "Questions",
    htmltools::tags$header(class = "ca-q-header",
      htmltools::tags$div(class = "ca-q-heading",
        htmltools::tags$div(class = "ca-q-eyebrow", header),
        htmltools::tags$div(class = "ca-q-mini-title", qs[[1]]$question %||% "")),
      htmltools::tags$div(class = "ca-q-header-actions",
        htmltools::tags$button(type = "button", class = "ca-q-icon ca-q-minimise",
                               `aria-label` = "Minimize", title = "Minimize",
                               shiny::icon("chevron-down")),
        htmltools::tags$button(type = "button", class = "ca-q-icon ca-q-dismiss",
                               `aria-label` = "Dismiss all questions",
                               title = "Dismiss all questions", shiny::icon("xmark")))),
    if (n > 1L) .question_nav_ui(qs),
    htmltools::tags$div(class = "ca-q-body",
      lapply(seq_len(n), function(i) .question_page_ui(qs[[i]], i, n))),
    htmltools::tags$footer(class = "ca-q-footer",
      htmltools::tags$div(class = "ca-q-pager",
        htmltools::tags$button(type = "button", class = "ca-q-icon ca-q-prev",
                               `aria-label` = "Previous question", shiny::icon("chevron-left")),
        htmltools::tags$span(class = "ca-q-progress", sprintf("1 / %d", n)),
        htmltools::tags$button(type = "button", class = "ca-q-icon ca-q-next-page",
                               `aria-label` = "Next question", shiny::icon("chevron-right"))),
      htmltools::tags$div(class = "ca-q-feedback", role = "status"),
      htmltools::tags$div(class = "ca-q-footer-actions",
        htmltools::tags$button(type = "button", class = "btn btn-sm btn-outline-secondary ca-q-skip", "Skip"),
        htmltools::tags$button(type = "button", class = "btn btn-sm btn-primary ca-q-submit",
                               if (n > 1L) "Next" else "Submit"))))
}

# The browser's answers (input$ca_q_answers$answers) -> one answer per
# question: a skipped question is empty, typed text replaces a single choice
# and is added to multiple ones.
.question_answers <- function(qs, raw) {
  lapply(seq_along(qs), function(i) {
    a <- if (i <= length(raw)) raw[[i]] else list()
    if (isTRUE(a$skipped)) return(character())
    picked <- as.character(unlist(a$selected %||% list()))
    picked <- picked[nzchar(picked)]
    custom <- trimws(as.character(a$custom %||% ""))[1]
    if (is.na(custom) || !nzchar(custom)) return(picked)
    if (isTRUE(qs[[i]]$multiSelect)) c(picked, custom) else custom
  })
}

# Build the promise-returning Data Shield egress approval callback. Payload is
# non-sensitive metadata only; raw result stays inside the tool wrapper.
.shiny_egress_ask_fn <- function(session, state) {
  function(event) {
    promises::promise(function(resolve, reject) {
      token <- tryCatch(.generate_uuid_v4(),error=function(e)paste0("egress-",Sys.time()))
      .enqueue_interaction(state, list(
        type="egress", token=token, payload=event, resolve=resolve))
      # Timeout counts from the request, shown or still queued: unanswered
      # results are redacted (the safe default) either way.
      timeout <- max(0,as.numeric(event$timeout %||% 60))
      later::later(function() {
        if (isTRUE(tryCatch(session$isClosed(),error=function(e) TRUE)))
          return(invisible(NULL))
        .resolve_interaction_token(state, token, "redact")
      },delay=timeout)
    })
  }
}

# Interactions are shown one at a time. Tools run concurrently (several tool
# calls in one turn, a form while an approval is open), so a request that
# arrives while another is shown waits in `state$interaction_queue` instead of
# overwriting the slot -- an overwritten request's promise never resolved and
# its tool, and the turn, hung.
.enqueue_interaction <- function(state, item) {
  if (is.null(item$token))
    item$token <- tryCatch(.generate_uuid_v4(), error = function(e) paste0("ia-", as.numeric(Sys.time())))
  shiny::isolate({
    if (is.null(state$pending_interaction)) state$pending_interaction <- item
    else state$interaction_queue <- c(state$interaction_queue, list(item))
  })
  invisible(item$token)
}

# Resolve + clear the shown interaction safely (idempotent), then show the
# next queued one.
.resolve_pending <- function(state, value) {
  pending <- shiny::isolate(state$pending_interaction)
  if (is.null(pending)) return(invisible(FALSE))
  queue <- shiny::isolate(state$interaction_queue)
  state$pending_interaction <- if (length(queue)) queue[[1L]] else NULL
  state$interaction_queue <- if (length(queue) > 1L) queue[-1L] else NULL
  tryCatch(pending$resolve(value), error = function(e) NULL)
  invisible(TRUE)
}

# Resolve one interaction by token, whether shown or still queued (timeouts).
.resolve_interaction_token <- function(state, token, value) {
  pending <- shiny::isolate(state$pending_interaction)
  if (!is.null(pending) && identical(pending$token, token))
    return(.resolve_pending(state, value))
  queue <- shiny::isolate(state$interaction_queue)
  hit <- vapply(queue, function(it) identical(it$token, token), logical(1))
  if (!any(hit)) return(invisible(FALSE))
  item <- queue[[which(hit)[1L]]]
  rest <- queue[-which(hit)[1L]]
  state$interaction_queue <- if (length(rest)) rest else NULL
  tryCatch(item$resolve(value), error = function(e) NULL)
  invisible(TRUE)
}

# Drop every shown and queued interaction, resolving each with its cancel
# value so no tool is left waiting (session restore / clear).
.clear_interactions <- function(state) {
  items <- c(list(shiny::isolate(state$pending_interaction)), shiny::isolate(state$interaction_queue))
  state$pending_interaction <- NULL
  state$interaction_queue <- NULL
  for (it in Filter(Negate(is.null), items))
    tryCatch(it$resolve(.interaction_cancel_value(it)), error = function(e) NULL)
  invisible(NULL)
}

# Build the in-chat interaction bar for a pending approval / question. PURE:
# takes the `pending` list (or NULL) and returns an htmltools tag (or NULL); no
# Shiny input/output/session, so the bar's layout is unit-testable. The
# observers below own all side effects (append messages, resolve the promise).
#
# Every bar has the same shell, styled in inst/www/styles.css (and by themes):
#   div.ca-interaction.ca-interaction--<kind>
#     div.ca-interaction-strip    status line ("Waiting for approval")
#     div.ca-interaction-body     title, detail, inputs
#     div.ca-interaction-actions  buttons
.interaction_shell <- function(kind, strip, body, actions, scroll = FALSE) {
  htmltools::tags$div(
    class = paste0("ca-interaction ca-interaction--", kind,
                   if (scroll) " ca-interaction--scroll" else ""),
    htmltools::tags$div(class = "ca-interaction-strip", strip),
    htmltools::tags$div(class = "ca-interaction-body", body),
    htmltools::tags$div(class = "ca-interaction-actions", actions))
}

.interaction_bar_ui <- function(pending, widgets = NULL) {
  if (is.null(pending)) return(NULL)

  if (identical(pending$type, "approval")) {
    p    <- pending$payload
    tin  <- p$tool_input %||% list()
    desc <- as.character(tin$command %||% tin$file_path %||% "")[1]
    if (is.na(desc)) desc <- ""
    # The command is shown in full (DSH wraps it, the body scrolls); a cap
    # keeps a pathological argument from flooding the page.
    if (nchar(desc) > 4000L) desc <- paste0(substr(desc, 1L, 4000L), "\u2026")
    card <- .interaction_shell("approval", "Waiting for approval",
      htmltools::tagList(
        htmltools::tags$div(class = "ca-interaction-title",
          "Allow ", htmltools::tags$code(p$tool_name %||% "?")),
        if (nzchar(desc))
          htmltools::tags$div(class = "ca-interaction-command", desc)),
      htmltools::tagList(
        shiny::actionButton("ca_tool_deny", "Reject",
                            class = "btn-outline-secondary btn-sm ca-interaction-reject"),
        shiny::actionButton("ca_tool_allow_always", "Always allow",
                            class = "btn-outline-secondary btn-sm ca-interaction-secondary",
                            title = "Allow this tool for the rest of this session without asking again"),
        shiny::actionButton("ca_tool_allow", "Allow once",
                            class = "btn-primary btn-sm ca-interaction-primary")))
    htmltools::tagAppendAttributes(card, `data-ca-keys` = "approval")
  } else if (identical(pending$type, "question")) {
    .question_card_ui(.question_as_questions(pending$payload))
  } else if (identical(pending$type, "questions")) {
    .question_card_ui(pending$payload$questions)
  } else if (identical(pending$type, "form")) {
    p <- pending$payload
    .interaction_shell("form", "Waiting for your input",
      htmltools::tagList(
        htmltools::tags$div(class = "ca-interaction-title",
          htmltools::tags$span(class = "ca-interaction-icon", "\U0001f4dd "), p$title %||% ""),
        htmltools::tags$div(class = "ca-form-fields",
          .form_fields_ui(p$fields, widgets %||% .form_preset_native()))),
      htmltools::tagList(
        shiny::actionButton("ca_form_cancel", "Cancel",
                            class = "btn-outline-secondary btn-sm ca-interaction-reject"),
        shiny::actionButton("ca_form_submit", p$submit_label %||% "Submit",
                            class = "btn-primary btn-sm ca-interaction-primary")),
      scroll = TRUE)
  } else if (identical(pending$type, "egress")) {
    p <- pending$payload
    .interaction_shell("egress", "Data Shield",
      htmltools::tagList(
        htmltools::tags$div(class = "ca-interaction-title",
          "Data Shield blocked a tool result: ", htmltools::tags$code(p$tool_name %||% "?")),
        htmltools::tags$div(class = "ca-interaction-detail",
          paste0(p$strategy %||% "policy", " \u2014 ", p$reason %||% "policy match",
                 " (matches: ", as.integer(p$match_count %||% 0L), ")"))),
      htmltools::tagList(
        if (isTRUE(p$allow_raw_approval))
          shiny::actionButton("ca_egress_raw", "ALLOW RAW ONCE",
                              class = "btn-danger btn-sm ca-interaction-danger"),
        shiny::actionButton("ca_egress_block", "Block result",
                            class = "btn-secondary btn-sm ca-interaction-reject"),
        shiny::actionButton("ca_egress_redact", "Redact and continue",
                            class = "btn-warning btn-sm ca-interaction-primary")))
  } else {
    NULL
  }
}


# A short record of an answer, appended to the running reply like "Tool
# allowed." (a separate message would end the streaming reply). Escaped:
# the text is the user's. PURE.
.answer_record_text <- function(qs, answers) {
  esc <- function(x) htmltools::htmlEscape(gsub("[\r\n]+", " ", x))
  if (!length(answers)) return("\u2716 Questions dismissed.")
  parts <- vapply(seq_along(qs), function(i) {
    a <- as.character(unlist(answers[i])); a <- a[!is.na(a) & nzchar(a)]
    sprintf("%s \u2192 %s", esc(qs[[i]]$question %||% ""),
            if (length(a)) esc(paste(a, collapse = ", ")) else "Skipped")
  }, "")
  paste0("\U0001f4dd Answered: ", paste(parts, collapse = "; "))
}
.form_record_text <- function(title, submitted) {
  if (!isTRUE(submitted)) return("\u2716 Form cancelled.")
  t <- htmltools::htmlEscape(gsub("[\r\n]+", " ", as.character(title %||% "")))
  paste0("\U0001f4dd Submitted", if (nzchar(t)) paste0(": ", t) else "", ".")
}
.append_record <- function(session, text)
  tryCatch(shinychat::chat_append_message(
    "chat", list(role = "assistant", content = text), session = session),
    error = function(e) NULL)

# Value to resolve a pending interaction with when the user hits ESC: deny
# (FALSE) an approval, or an empty answer ("") a question. PURE.
.interaction_cancel_value <- function(pending) {
  if (is.null(pending)) return(NULL)
  if (identical(pending$type, "approval")) return(FALSE)
  if (identical(pending$type, "egress")) return("redact")
  if (identical(pending$type, "form")) return(list(submitted = FALSE))
  if (identical(pending$type, "questions")) return(list())
  ""
}

#' Wire the interaction bar UI + observers into a Shiny session
#'
#' @param input,output,session Standard Shiny server args.
#' @param state The shared `reactiveValues` (must contain `pending_interaction`).
#' @return A list with `ask_fn`, `ask_question_fn`, `ask_form_fn` and
#'   `egress_ask_fn` (promise-returning).
#' @keywords internal
server_interaction <- function(input, output, session, state, form_widgets = NULL) {
  widgets <- .form_widgets_resolve(form_widgets)

  # ---- Interaction bar (approval OR question) ----
  # The bar's layout is built by the pure .interaction_bar_ui(); this observer
  # just re-renders it whenever the pending slot changes.
  output$ca_interaction_ui <- shiny::renderUI({
    bar <- .interaction_bar_ui(state$pending_interaction, widgets)
    waiting <- length(state$interaction_queue)
    if (is.null(bar) || !waiting) return(bar)
    htmltools::tagList(htmltools::tags$div(
      class = "ca-interaction-queue small text-muted", style = "padding:2px 16px; text-align:left;",
      sprintf("%d more request%s waiting", waiting, if (waiting == 1L) "" else "s")), bar)
  })

  # ---- Allow / Deny (permission approval) ----
  shiny::observeEvent(input$ca_tool_allow, ignoreInit = TRUE, {
    if (.resolve_pending(state, TRUE))
      shinychat::chat_append_message(
        "chat", list(role = "assistant", content = "\u2705 Tool allowed."),
        session = session)
  })
  # Allow, and stop asking for this tool in this session: approvals of the
  # same tool already waiting in the queue are allowed too.
  shiny::observeEvent(input$ca_tool_allow_always, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type, "approval")) return()
    tool <- as.character(pending$payload$tool_name %||% "")
    if (!nzchar(tool)) return()
    state$always_allow <- unique(c(shiny::isolate(state$always_allow), tool))
    same <- function(it) !is.null(it) && identical(it$type, "approval") &&
      identical(as.character(it$payload$tool_name %||% ""), tool)
    .resolve_pending(state, TRUE)
    # the next shown request may be the same tool (promoted from the queue)
    while (same(shiny::isolate(state$pending_interaction))) .resolve_pending(state, TRUE)
    queued <- Filter(same, shiny::isolate(state$interaction_queue) %||% list())
    for (it in queued) .resolve_interaction_token(state, it$token, TRUE)
    shinychat::chat_append_message(
      "chat", list(role = "assistant", content = paste0("\u2705 `", tool,
        "` allowed for the rest of this session.")), session = session)
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
    if (!is.null(pending) && identical(pending$type, "questions")) {
      qs <- pending$payload$questions
      # typing in Other is choosing it: it replaces a single choice and is
      # added to multiple ones
      answers <- lapply(seq_along(qs), function(i) {
        picked <- setdiff(as.character(input[[paste0("ca_qs_", i)]] %||% character()), "__other__")
        other <- trimws(as.character(input[[paste0("ca_qs_other_", i)]] %||% ""))
        if (!nzchar(other)) return(picked)
        if (isTRUE(qs[[i]]$multiSelect)) c(picked, other) else other
      })
      .resolve_pending(state, answers)
      return()
    }
    if (is.null(pending) || !identical(pending$type, "question")) return()
    answer <- input$ca_q_choice %||% input$ca_q_text %||% ""
    .resolve_pending(state, answer)
  })

  # ---- Question card (interaction.js): all answers at once, or dismissed ----
  shiny::observeEvent(input$ca_q_answers, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !pending$type %in% c("question", "questions")) return()
    ev <- input$ca_q_answers
    if (isTRUE(ev$dismissed)) {
      if (.resolve_pending(state, .interaction_cancel_value(pending)))
        .append_record(session, .answer_record_text(list(), list()))
      return()
    }
    qs <- if (identical(pending$type, "questions")) pending$payload$questions
          else .question_as_questions(pending$payload)
    answers <- .question_answers(qs, ev$answers %||% list())
    value <- if (identical(pending$type, "questions")) answers
             else paste(answers[[1]], collapse = ", ")
    if (.resolve_pending(state, value))
      .append_record(session, .answer_record_text(qs, answers))
  })

  # ---- Form submit / cancel (AskUserForm) ----
  # A required field left empty keeps the form open (a re-render would wipe
  # what the user typed), so it is reported with a toast instead.
  shiny::observeEvent(input$ca_form_submit, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type, "form")) return()
    spec <- pending$payload$fields
    raw <- stats::setNames(lapply(seq_along(spec), function(i) {
      id <- .form_input_id(i)
      if (identical(spec[[i]]$type, "grouping"))   # one group box per choice
        return(vapply(seq_along(spec[[i]]$choices), function(j)
          as.character(input[[paste0(id, "_g", j)]] %||% "")[1], character(1L)))
      input[[id]]
    }), vapply(spec, `[[`, character(1L), "name"))
    # dateInput gives a Date; keep the ISO text the model was told about.
    raw <- lapply(raw, function(v) if (inherits(v, "Date")) format(v) else v)
    collected <- .form_collect(spec, raw)
    if (length(collected$missing) || length(collected$invalid)) {
      .ui_toast(paste(c(
        if (length(collected$missing))
          paste0("Please fill in: ", paste(collected$missing, collapse = ", ")),
        collected$invalid), collapse = ". "), "warning")
      return()
    }
    if (.resolve_pending(state, list(submitted = TRUE, values = collected$values)))
      .append_record(session, .form_record_text(pending$payload$title, TRUE))
  })
  shiny::observeEvent(input$ca_form_cancel, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type, "form")) return()
    if (.resolve_pending(state, list(submitted = FALSE)))
      .append_record(session, .form_record_text(NULL, FALSE))
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
