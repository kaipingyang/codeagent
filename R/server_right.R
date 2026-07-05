#' @title Right Panel Server Logic (File Tree + Output)
#' @name server_right
#' @keywords internal
NULL

server_right <- function(input, output, session, cwd, state,
                          show_hidden = FALSE,
                          exclude = c("renv", "node_modules", "packrat",
                                      ".git", ".Rproj.user")) {

  # File tree (jsTreeR). Uses .file_tree_server -- a thin fork of jsTreeR's
  # treeNavigatorServer that reuses its jstree widget + lazy-load JS protocol
  # but adds directory exclusion (jsTreeR has no exclude hook). all.files =
  # show_hidden hides dotfiles by default (incl. the multi-MB .codegraph).
  selected_paths <- .file_tree_server(
    "file_tree",
    rootFolder = cwd,
    all.files  = isTRUE(show_hidden),
    exclude    = exclude
  )

  # Click file -> render preview to Output tab
  shiny::observeEvent(selected_paths(), {
    paths <- selected_paths()
    if (length(paths) == 0L) return()
    path <- normalizePath(paths[[length(paths)]], winslash = "/", mustWork = FALSE)
    if (!file.exists(path) || dir.exists(path)) return()

    ext     <- tools::file_ext(path)
    fname   <- sub(paste0("^", normalizePath(cwd, winslash = "/", mustWork = FALSE), "/?"), "", path)
    preview <- tryCatch({
      switch(tolower(ext),
        r  = ,
        rmd = htmltools::tags$pre(
          htmltools::tags$code(
            class = "language-r",
            paste(readLines(path, warn = FALSE, n = 500L), collapse = "\n")
          )),
        csv = {
          if (requireNamespace("reactable", quietly = TRUE)) {
            df <- tryCatch(utils::read.csv(path, nrows = 200L),
                           error = function(e) NULL)
            if (!is.null(df)) reactable::reactable(df, compact = TRUE)
            else htmltools::tags$p("Could not read CSV.")
          } else {
            htmltools::tags$pre(paste(readLines(path, warn = FALSE, n = 20L),
                                     collapse = "\n"))
          }
        },
        png = ,
        jpg = ,
        jpeg = ,
        gif = {
          b64 <- tryCatch(
            base64enc::dataURI(file = path),
            error = function(e) NULL)
          if (!is.null(b64))
            htmltools::tags$img(src = b64,
                                style = "max-width:100%; height:auto;")
          else htmltools::tags$p("Cannot preview image.")
        },
        md = htmltools::HTML(
          tryCatch(
            commonmark::markdown_html(
              paste(readLines(path, warn = FALSE), collapse = "\n")),
            error = function(e) paste(readLines(path, warn = FALSE, n=100), collapse="\n")
          )),
        htmltools::tags$pre(
          style = "font-size:0.78rem; overflow:auto;",
          paste(readLines(path, warn = FALSE, n = 300L), collapse = "\n"))
      )
    }, error = function(e) {
      htmltools::tags$p(paste("[Error]", conditionMessage(e)))
    })

    state$main_output <- list(title = fname, content = preview)
    shiny::updateTabsetPanel(session, "main_tab", selected = "output")
  }, ignoreInit = TRUE)
}


# ---------------------------------------------------------------------------
# File tree server with directory exclusion
# ---------------------------------------------------------------------------

# A thin fork of jsTreeR::treeNavigatorServer(). It reuses jsTreeR's jstree
# widget and its lazy-load JS protocol verbatim (output id "treeNavigator___",
# inputs "path_from_js" / "treeNavigator____selected_paths", custom message
# "getChildren") -- we only reimplement the children-listing step so we can
#   (a) hide dotfiles via all.files = FALSE, and
#   (b) exclude heavy non-dot directories (renv/, node_modules/, ...),
# neither of which treeNavigatorServer exposes a hook for.
#
# COUPLING NOTE: this mirrors jsTreeR's internal widget protocol. If jsTreeR
# changes it, re-sync this function (see references/plan tracking for dev-dep
# bumps). Paired UI is still jsTreeR::treeNavigatorUI().
.file_tree_server <- function(id, rootFolder, exclude = character(0),
                              all.files = FALSE, search = TRUE,
                              wholerow = FALSE, contextMenu = FALSE,
                              theme = "proton") {
  shiny::moduleServer(id, function(input, output, session) {
    output[["treeNavigator___"]] <- jsTreeR::renderJstree({
      jsTreeR::jstree(
        nodes = list(list(
          text     = normalizePath(rootFolder, winslash = "/", mustWork = TRUE),
          type     = "folder",
          children = FALSE,
          li_attr  = list(class = "jstree-x")
        )),
        types = list(
          folder = list(icon = "fa fa-folder gold"),
          file   = list(icon = "far fa-file red")
        ),
        checkCallback = TRUE, theme = theme, checkboxes = TRUE,
        search = search, wholerow = wholerow, contextMenu = contextMenu,
        selectLeavesOnly = TRUE
      )
    })

    shiny::observeEvent(input[["path_from_js"]], {
      entries <- tryCatch(
        list.files(input[["path_from_js"]], all.files = all.files,
                   full.names = TRUE, no.. = TRUE),
        error = function(e) character(0))
      if (length(exclude)) {
        entries <- entries[!basename(entries) %in% exclude]
      }
      fi <- file.info(entries, extra_cols = FALSE)
      x  <- list(elem = as.list(basename(entries)),
                 folder = as.list(fi[["isdir"]]))
      session$sendCustomMessage("getChildren", x)
    })

    Paths <- shiny::reactiveVal()
    shiny::observeEvent(input[["treeNavigator____selected_paths"]], {
      Paths(vapply(input[["treeNavigator____selected_paths"]],
                   `[[`, character(1L), "path"))
    })
    Paths
  })
}
