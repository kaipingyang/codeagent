#!/usr/bin/env Rscript
# inst/examples/test_chat_toolbar_app.R
#
# Test app: chat footer toolbar
#   1. Local file upload (icon-only button -> hidden fileInput)
#   2. Server file (shinyFiles)
#   3. Voice input (Web Speech API)
#   4. Skill picker (full-width row, subtext in dropdown only, fills textarea on select)
#   5. enable_cancel = TRUE (built-in cancel during streaming)
#
# Run with:  shiny::runApp("inst/examples/test_chat_toolbar_app.R")

library(shiny)
library(bslib)
library(shinychat)
library(shinyWidgets)
library(shinyFiles)

if (file.exists(".Renviron")) readRenviron(".Renviron")
devtools::load_all(quiet = TRUE)

`%||%` <- function(x, y) if (is.null(x) || !nzchar(x)) y else x

# ---------------------------------------------------------------------------
# Skill meta
# ---------------------------------------------------------------------------
load_skill_meta <- function() {
  metas <- tryCatch(codeagent:::list_skills_meta(), error = function(e) NULL)
  if (is.null(metas) || !length(metas)) {
    return(data.frame(
      key   = c("plan", "compact", "verify", "simplify"),
      label = c("/plan", "/compact", "/verify", "/simplify"),
      desc  = c(
        "Break work into clear, ordered steps",
        "Make replies shorter and denser",
        "Verify correctness of the last action",
        "Simplify the last piece of code"
      ),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    key   = vapply(metas, `[[`, character(1), "name"),
    label = paste0("/", vapply(metas, `[[`, character(1), "name")),
    desc  = vapply(metas, function(m) m$description %||% "", character(1)),
    stringsAsFactors = FALSE
  )
}

skill_meta    <- load_skill_meta()
skill_choices <- list(
  "Slash Commands" = stats::setNames(skill_meta$key, skill_meta$label)
)

# ---------------------------------------------------------------------------
# JS: voice + file trigger
# ---------------------------------------------------------------------------
toolbar_js <- tags$script(HTML("
(function() {

  // ── Local file: icon button -> hidden <input type=file> ──────────────────
  $(document).on('click', '#ca_upload_local_btn', function() {
    document.getElementById('ca_file_hidden').click();
  });

  $(document).ready(function() {
    var fInput = document.getElementById('ca_file_hidden');
    if (fInput) {
      fInput.addEventListener('change', function(e) {
        if (!e.target.files.length) return;
        var names = Array.from(e.target.files).map(function(f) { return f.name; }).join(', ');
        Shiny.setInputValue('ca_uploaded_files', { names: names, ts: Date.now() }, { priority: 'event' });
        e.target.value = '';
      });
    }
  });

  // ── Voice: Web Speech API ─────────────────────────────────────────────────
  var recognition = null;
  var isRecording  = false;

  function stopRecognition() {
    isRecording = false;
    if (recognition) { try { recognition.stop(); } catch(e) {} recognition = null; }
    var btn = document.getElementById('ca_voice_btn');
    if (btn) { btn.classList.remove('recording'); btn.title = 'Voice input'; }
  }

  function startRecognition() {
    var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) {
      alert('Web Speech API requires Chrome or Edge on HTTPS/localhost.');
      return;
    }
    recognition = new SR();
    recognition.lang           = navigator.language || 'en-US';
    recognition.interimResults = false;
    recognition.onstart  = function() {
      isRecording = true;
      var btn = document.getElementById('ca_voice_btn');
      if (btn) { btn.classList.add('recording'); btn.title = 'Click to stop'; }
    };
    recognition.onresult = function(e) {
      var text = e.results[0][0].transcript;
      Shiny.setInputValue('ca_voice_text', { text: text, ts: Date.now() }, { priority: 'event' });
    };
    recognition.onerror = function() { stopRecognition(); };
    recognition.onend   = function() { stopRecognition(); };
    recognition.start();
  }

  $(document).on('click', '#ca_voice_btn', function() {
    if (isRecording) stopRecognition(); else startRecognition();
  });

})();
"))

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
ui <- page_fillable(
  tags$head(
    tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css"
    ),
    toolbar_js
  ),

  card(
    height = "100%",
    card_body(
      tags$input(
        type   = "file",
        id     = "ca_file_hidden",
        style  = "display:none;",
        accept = ".pdf,.txt,.csv,.R,.Rmd,.md,.docx,.xlsx,.png,.jpg"
      ),

      shinychat::chat_ui(
        "chat",
        fill          = TRUE,
        enable_cancel = TRUE,
        placeholder   = "Ask codeagent... (/ for skills)",
        footer = tags$div(
          class = "d-flex flex-column gap-1",

          # Row 1: icon-only buttons
          tags$div(
            class = "d-flex align-items-center gap-1",
            actionButton("ca_upload_local_btn", NULL,
              icon  = icon("paperclip"),
              class = "btn-outline-secondary btn-sm",
              title = "Upload local file"),
            shinyFiles::shinyFilesButton(
              "ca_server_btn",
              label    = NULL,
              title    = "Browse server files",
              icon     = icon("server"),
              class    = "btn-outline-secondary btn-sm",
              multiple = FALSE),
            actionButton("ca_voice_btn", NULL,
              icon  = icon("microphone"),
              class = "btn-outline-secondary btn-sm",
              title = "Voice input"),
            shiny::uiOutput("attach_badge", inline = TRUE)
          ),

          # Row 2: skill picker, full width, subtext only in dropdown
          shinyWidgets::pickerInput(
            inputId    = "skill_picker",
            label      = NULL,
            choices    = skill_choices,
            selected   = character(0),
            multiple   = FALSE,
            width      = "100%",
            choicesOpt = list(
              subtext = skill_meta$desc,
              tokens  = paste(skill_meta$key, skill_meta$desc)
            ),
            options = shinyWidgets::pickerOptions(
              liveSearch            = TRUE,
              noneSelectedText      = "Select a skill...",
              liveSearchPlaceholder = "Search skills...",
              showSubtext           = FALSE,
              size                  = 8,
              container             = "body",
              width                 = "100%"
            )
          )
        )
      )
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
server <- function(input, output, session) {

  attached <- shiny::reactiveVal(NULL)

  session$onFlushed(function() {
    shinyWidgets::updatePickerInput(session, "skill_picker", selected = character(0))
  }, once = TRUE)

  roots <- c(home = path.expand("~"), cwd = getwd())
  shinyFiles::shinyFileChoose(input, "ca_server_btn", roots = roots, session = session)

  # Skill picker -> fill textarea with /skillname
  shiny::observeEvent(input$skill_picker, ignoreInit = TRUE, {
    req(nzchar(input$skill_picker))
    shinychat::update_chat_user_input("chat",
      value   = paste0("/", input$skill_picker, " "),
      focus   = TRUE,
      submit  = FALSE,
      session = session
    )
  })

  # Voice -> append to textarea
  shiny::observeEvent(input$ca_voice_text, {
    req(nzchar(input$ca_voice_text$text))
    current <- isolate(input$chat_user_input) %||% ""
    shinychat::update_chat_user_input("chat",
      value   = trimws(paste(trimws(current), input$ca_voice_text$text)),
      focus   = TRUE,
      submit  = FALSE,
      session = session
    )
  })

  # Local file upload
  shiny::observeEvent(input$ca_uploaded_files, {
    attached(input$ca_uploaded_files$names)
  })

  # Server file selection
  shiny::observe({
    req(input$ca_server_btn)
    fi <- shinyFiles::parseFilePaths(roots, input$ca_server_btn)
    req(nrow(fi) > 0)
    attached(fi$name[[1]])
  })

  # Attachment badge
  output$attach_badge <- shiny::renderUI({
    f <- attached()
    if (is.null(f)) return(NULL)
    tags$span(
      style = "font-size:0.75rem; color:#0d6efd; display:flex; align-items:center; gap:3px;",
      tags$i(class = "fa fa-paperclip"),
      f,
      tags$button(
        style   = "background:none;border:none;padding:0;color:#6c757d;cursor:pointer;font-size:0.7rem;",
        onclick = "Shiny.setInputValue('ca_clear_attach', Date.now(), {priority:'event'});",
        tags$i(class = "fa fa-xmark")
      )
    )
  })
  shiny::observeEvent(input$ca_clear_attach, { attached(NULL) })

  # Echo chat
  shiny::observeEvent(input$chat_user_input, {
    req(nzchar(trimws(input$chat_user_input)))
    shinychat::chat_append("chat",
      paste0("Echo: ", input$chat_user_input), session = session)
  })
}

shinyApp(ui, server)
