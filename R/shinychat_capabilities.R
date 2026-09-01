# Feature detection for optional shinychat development APIs.

.shinychat_export <- function(name) {
  tryCatch(getExportedValue("shinychat", name), error = function(e) NULL)
}

.shinychat_page_chat_available <- function() {
  all(vapply(
    c(
      "page_chat", "chat_drawer", "chat_drawer_show",
      "chat_drawer_update", "chat_drawer_hide", "chat_drawer_toggle"
    ),
    function(name) is.function(.shinychat_export(name)),
    logical(1L)
  ))
}

.shinychat_drawer_action <- function(
  id,
  action = c("show", "update", "hide", "toggle"),
  content = NULL,
  title = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  action <- match.arg(action)
  fn <- .shinychat_export(paste0("chat_drawer_", action))
  if (!is.function(fn))
    stop("The installed shinychat does not provide `chat_drawer_", action, "()`.",
         call. = FALSE)
  args <- list(id = id, session = session)
  if (action %in% c("show", "update")) {
    args$content <- content
    args$title <- title
  }
  invisible(do.call(fn, args))
}

.shinychat_framed_tool_results_available <- function() {
  constructor <- .shinychat_export("tool_result_display")
  is.function(constructor) &&
    "open_style" %in% names(formals(constructor))
}
