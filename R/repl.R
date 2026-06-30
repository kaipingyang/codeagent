#' @title Interactive CLI REPL (harness, no Shiny)
#' @description A terminal read-eval-print loop for the agent. Reuses one
#'   `CodagentClient` so history accumulates in the Chat object across turns.
#'   Supports slash commands (`/exit`, `/model`, `/compact`, `/clear`, `/help`).
#'   The line parser `.repl_dispatch()` is a pure function (testable); the loop
#'   `codeagent_repl()` handles IO.
#' @name repl
#' @keywords internal
NULL

# Parse one REPL line into an action descriptor (pure, testable).
# Returns list(action, ...). Actions:
#   "exit"    -> quit the loop
#   "help"    -> print help
#   "clear"   -> clear history
#   "compact" -> force full compaction
#   "model"   -> switch model (arg = spec)
#   "noop"    -> empty line, do nothing
#   "prompt"  -> send to model (text = line)
.repl_dispatch <- function(line) {
  line <- trimws(line %||% "")
  if (!nzchar(line)) return(list(action = "noop"))
  if (!startsWith(line, "/")) return(list(action = "prompt", text = line))

  parts <- strsplit(sub("^/", "", line), "\\s+")[[1L]]
  cmd   <- tolower(parts[[1L]] %||% "")
  arg   <- if (length(parts) > 1L) paste(parts[-1L], collapse = " ") else ""

  switch(cmd,
    exit    = ,
    quit    = list(action = "exit"),
    help    = list(action = "help"),
    clear   = list(action = "clear"),
    compact = list(action = "compact"),
    model   = list(action = "model", arg = arg),
    list(action = "unknown", cmd = cmd)
  )
}

.repl_help <- paste(
  "Commands:",
  "  /model <spec>   switch model (e.g. anthropic/claude-haiku-4-5)",
  "  /compact        force context compaction",
  "  /clear          clear conversation history",
  "  /help           show this help",
  "  /exit, /quit    leave the REPL",
  sep = "\n"
)

#' Run the interactive REPL
#'
#' @param client A `CodagentClient`.
#' @param stream Logical. Stream responses token-by-token.
#' @param prompt_str Character. The input prompt shown each turn.
#' @param con Connection to read lines from (default stdin; override in tests).
#' @return Invisibly NULL. Loops until `/exit`.
#' @export
codeagent_repl <- function(client, stream = TRUE,
                           prompt_str = "› ", con = stdin()) {
  if (!inherits(client, "CodagentClient"))
    stop("codeagent_repl() expects a CodagentClient.", call. = FALSE)

  cat("codeagent REPL. Type /help for commands, /exit to quit.\n")

  repeat {
    cat(prompt_str)
    line <- tryCatch(readLines(con, n = 1L), error = function(e) character(0))
    if (length(line) == 0L) break  # EOF (Ctrl-D)

    act <- .repl_dispatch(line)
    switch(act$action,
      noop = next,
      exit = { cat("Bye.\n"); break },
      help = { cat(.repl_help, "\n"); next },
      unknown = { cat("Unknown command: /", act$cmd, " (try /help)\n", sep = ""); next },
      clear = {
        tryCatch(client$chat$set_turns(list()), error = function(e) NULL)
        cat("[history cleared]\n"); next
      },
      compact = {
        tryCatch(full_compact(client$chat), error = function(e)
          cat("[compact failed: ", conditionMessage(e), "]\n", sep = ""))
        cat("[context compacted]\n"); next
      },
      model = {
        if (!nzchar(act$arg)) { cat("Usage: /model <spec>\n"); next }
        client <- tryCatch(switch_model(client, act$arg), error = function(e) {
          cat("[model switch failed: ", conditionMessage(e), "]\n", sep = ""); client
        })
        cat("[model: ", client$settings$model %||% act$arg, "]\n", sep = "")
        next
      },
      prompt = {
        if (isTRUE(stream)) {
          out <- tryCatch({
            s <- client$chat$stream(act$text)
            for (chunk in s) cat(chunk)
            cat("\n"); TRUE
          }, error = function(e) { cat("[error: ", conditionMessage(e), "]\n", sep = ""); FALSE })
        } else {
          resp <- tryCatch(codeagent(client, act$text),
                           error = function(e) paste0("[error] ", conditionMessage(e)))
          cat(resp, "\n")
        }
        next
      }
    )
  }
  invisible(NULL)
}
