#' @title Skills Server Logic
#' @name server_skills
#' @keywords internal
NULL

server_skills <- function(input, output, session, cwd, pinned_skills) {

  output$skill_list_ui <- shiny::renderUI({
    metas <- tryCatch(list_skills_meta(cwd), error = function(e) list())
    if (length(metas) == 0L)
      return(htmltools::tags$p(
        style = "color:var(--ca-text-muted); font-size:0.75rem;",
        "No skills found"))

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
        "No matching skills"))

    pinned  <- Filter(function(m) m$name %in% pinned_skills, metas)
    rest    <- Filter(function(m) !m$name %in% pinned_skills, metas)
    ordered <- c(pinned, rest)

    make_btn <- function(m) {
      is_pinned <- m$name %in% pinned_skills
      hint_tag  <- if (nzchar(m$argument_hint %||% ""))
        htmltools::tags$span(class = "ca-skill-desc", m$argument_hint)
      else NULL
      shiny::actionButton(
        inputId = paste0("skill_btn_", m$name),
        label   = htmltools::tagList(
          htmltools::tags$span(class = "ca-skill-name", paste0("/", m$name)),
          htmltools::tags$span(class = "ca-skill-desc", m$description %||% ""),
          hint_tag
        ),
        class = paste("ca-skill-btn w-100 mb-1",
                      if (is_pinned) "pinned" else "")
      )
    }
    htmltools::tagList(lapply(ordered, make_btn))
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

  # Install skill modal
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
      shiny::showNotification("Package name is required.", type = "warning"); return()
    }
    if (!requireNamespace("btw", quietly = TRUE)) {
      shiny::showNotification("btw required for skill installation.", type = "error"); return()
    }
    tryCatch({
      btw::btw_skill_install_package(
        pkg,
        skill = if (nzchar(name)) name else NULL,
        scope = scope)
      shiny::showNotification(
        sprintf("Skill installed from '%s'.", pkg),
        type = "message", duration = 4)
    }, error = function(e) {
      shiny::showNotification(conditionMessage(e), type = "error", duration = 6)
    })
  })
}
