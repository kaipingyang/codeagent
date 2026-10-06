# Shared fixtures for the GenUI tests.

skip_if_no_genui <- function() {
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
}

# Recording stand-in for the Shiny side of the executor. Every DOM/session
# effect lands in `log`; `fail_server` makes the next matching server start
# throw, so transactional paths can be exercised without a browser.
fake_genui_ops <- function() {
  env <- new.env(parent = emptyenv())
  env$log <- list()
  env$dom <- character()          # shell ids currently in the canvas
  env$nulled <- character()
  env$scopes <- character()        # module scopes destroyed
  env$can_destroy <- TRUE          # FALSE mimics a Shiny without session$destroy()
  env$destroyed <- 0L
  env$fail_server <- NULL         # function(module_id, args) -> TRUE to fail
  env$inputs <- list()
  record <- function(...) env$log[[length(env$log) + 1L]] <- list(...)
  env$ops <- list(
    insert = function(selector, ui, where = "beforeEnd") {
      record(op = "insert", selector = selector)
      id <- tryCatch(ui$attribs$id, error = function(e) NULL)
      if (is.character(id) && startsWith(id, "ca_genui_shell_"))
        env$dom <- union(env$dom, id)
      invisible(NULL)
    },
    remove = function(selector, multiple = FALSE) {
      record(op = "remove", selector = selector)
      id <- sub("^#", "", selector)
      if (!grepl(" ", selector, fixed = TRUE)) env$dom <- setdiff(env$dom, id)
      invisible(NULL)
    },
    null_output = function(output_id) {
      env$nulled <- c(env$nulled, output_id)
      invisible(NULL)
    },
    run_server = function(component, module_id, args, data) {
      record(op = "server", module_id = module_id)
      if (is.function(env$fail_server) && isTRUE(env$fail_server(module_id, args)))
        stop("synthetic server failure")
      list(destroy = function() env$destroyed <- env$destroyed + 1L)
    },
    destroy_scope = function(module_id) {
      if (!isTRUE(env$can_destroy)) return(FALSE)
      env$scopes <- c(env$scopes, module_id)
      TRUE
    },
    input_values = function(module_id) env$inputs[[module_id]]
  )
  env
}

genui_test_env <- function() {
  env <- new.env(parent = emptyenv())
  env$cars <- mtcars
  env$flowers <- iris
  env$not_a_frame <- 1:3
  env
}

# A prepared, bound adapter over fake ops and an isolated data environment.
genui_test_adapter <- function(ops = fake_genui_ops(), env = genui_test_env()) {
  a <- GenUIAdapter$new(data_env = env)
  a$bind(session = NULL, ops = ops$ops)
  a$begin_turn()
  list(adapter = a, ops = ops, env = env)
}

genui_ok <- function(result) {
  is.null(tryCatch(result@error, error = function(e) NULL))
}
