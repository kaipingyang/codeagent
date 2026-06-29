#' @title Right Panel Server Logic (File Tree + Output)
#' @name server_right
#' @keywords internal
NULL

server_right <- function(input, output, session, cwd, state) {

  # File tree (jsTreeR)
  selected_paths <- jsTreeR::treeNavigatorServer(
    "file_tree",
    rootFolder = cwd
  )

  # Click file → render preview to Output tab
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
