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

  # Click a file -> render its preview into the single static "File" viewer tab
  # (ca_file_view) and switch to it. Viewing another file replaces the content;
  # the "x" in the viewer header closes it and returns to the Files tree.
  # (Replaces the old per-file nav_insert() tabs, which mis-rendered outside the
  # navset and covered the tab strip.)
  current_file <- shiny::reactiveVal(NULL)

  output$ca_file_view <- shiny::renderUI({
    cf <- current_file()
    if (is.null(cf)) {
      return(htmltools::div(
        class = "text-muted",
        style = "padding:1rem;",
        "No file open. Click a file in the Files tab to view it here."
      ))
    }
    htmltools::tagList(
      # Fixed header: filename + close.
      htmltools::div(
        class = "ca-file-view-header",
        style = paste(
          "flex:0 0 auto; display:flex; align-items:center; gap:8px;",
          "padding:4px 10px; border-bottom:1px solid var(--bs-border-color);"),
        htmltools::tags$strong(cf$fname),
        htmltools::tags$span(style = "flex:1 1 auto;"),
        htmltools::tags$a(
          href    = "#",
          title   = "Close file",
          class   = "text-muted",
          style   = "text-decoration:none;",
          onclick = "event.preventDefault();Shiny.setInputValue('ca_close_file', Math.random(), {priority:'event'});",
          htmltools::HTML("&times;")
        )
      ),
      # Body: fills the remaining height and scrolls internally.
      htmltools::div(
        class = "html-fill-item ca-file-view-body",
        style = "flex:1 1 auto; min-height:0; overflow:auto;",
        cf$preview
      )
    )
  })

  shiny::observeEvent(selected_paths(), {
    paths <- selected_paths()
    if (length(paths) == 0L) return()
    path <- normalizePath(paths[[length(paths)]], winslash = "/", mustWork = FALSE)
    if (!file.exists(path) || dir.exists(path)) return()

    ext   <- tools::file_ext(path)
    fname <- sub(paste0("^", normalizePath(cwd, winslash = "/", mustWork = FALSE), "/?"), "", path)
    key   <- gsub("[^A-Za-z0-9]+", "_", path)

    preview <- tryCatch({
      switch(tolower(ext),
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
        md = htmltools::div(
          style = "padding:0 10px;",
          htmltools::HTML(
            tryCatch(
              commonmark::markdown_html(
                paste(readLines(path, warn = FALSE), collapse = "\n")),
              error = function(e) paste(readLines(path, warn = FALSE, n = 100), collapse = "\n")
            ))),
        # Default: code/text files -> syntax-highlighted read-only editor.
        .code_preview(path, ext, id = paste0("ced__", key))
      )
    }, error = function(e) {
      htmltools::tags$p(paste("[Error]", conditionMessage(e)))
    })

    current_file(list(fname = basename(fname), preview = preview))
    bslib::nav_select("main_tab", "file_view", session = session)
  }, ignoreInit = TRUE)

  # Close the open file -> clear the viewer and return to the Files tree.
  shiny::observeEvent(input$ca_close_file, {
    current_file(NULL)
    bslib::nav_select("main_tab", "files", session = session)
  }, ignoreInit = TRUE)

  # Session transition (new / delete / restore) -> clear any open file so a
  # stale preview from the previous session doesn't linger.
  shiny::observeEvent(state$session_id, {
    current_file(NULL)
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


# ---------------------------------------------------------------------------
# Code file preview (Output panel)
# ---------------------------------------------------------------------------

# Map a file extension to a prism-code-editor language id for input_code_editor.
.editor_language <- function(ext) {
  m <- c(r = "r", rmd = "markdown", rnw = "latex", py = "python", pyi = "python",
         js = "javascript", mjs = "javascript", cjs = "javascript", jsx = "jsx",
         ts = "typescript", tsx = "tsx", json = "json", jsonc = "json",
         yaml = "yaml", yml = "yaml", toml = "toml", ini = "ini",
         sh = "bash", bash = "bash", zsh = "bash", ps1 = "powershell",
         sql = "sql", css = "css", scss = "scss", sass = "sass", less = "less",
         html = "html", htm = "html", xml = "xml", svg = "xml", vue = "html",
         c = "c", h = "c", cpp = "cpp", cxx = "cpp", cc = "cpp",
         hpp = "cpp", hxx = "cpp", cs = "csharp", go = "go", rs = "rust",
         java = "java", kt = "kotlin", swift = "swift", rb = "ruby",
         php = "php", pl = "perl", lua = "lua", jl = "julia", scala = "scala",
         dart = "dart", md = "markdown", dockerfile = "docker",
         make = "makefile", cmake = "cmake", tex = "latex")
  lang <- unname(m[tolower(ext)])
  if (length(lang) != 1L || is.na(lang)) "plain" else lang
}

# Read-only, syntax-highlighted preview of a code/text file for the Output
# panel. Uses bslib::input_code_editor (bundled prism-code-editor: highlighting,
# line numbers, auto light/dark, no CDN). Replaces the old plain <pre> fallback.
.code_preview <- function(path, ext, id = "main_code_editor", max_lines = 5000L) {
  lines <- tryCatch(readLines(path, warn = FALSE, n = max_lines),
                    error = function(e) character(0))
  bslib::input_code_editor(
    id           = id,
    label        = NULL,
    value        = paste(lines, collapse = "\n"),
    language     = .editor_language(ext),
    read_only    = TRUE,
    line_numbers = TRUE,
    word_wrap    = FALSE,
    fill         = TRUE,
    # Fill the enclosing tab panel (NOT the viewport). `calc(100vh - ...)` made the
    # editor as tall as the whole window inside a 50%-width sidebar tab, so it
    # overflowed and covered the tab bar + the rest of the interface.
    height       = "100%"
  )
}
