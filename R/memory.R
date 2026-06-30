#' @title Auto-Memory (persistent agent memory)
#' @description File-based persistent memory under `~/.codeagent/memory/`. The
#'   agent writes durable facts via the `remember` tool; relevant memories are
#'   injected back into each turn's `<system-reminder>` so they survive across
#'   sessions. Mirrors Claude Code's auto-memory layer.
#'
#'   Layout:
#'   * `~/.codeagent/memory/<slug>.md` -- one fact per file, optional YAML
#'     front-matter (`name`, `description`).
#'   * `~/.codeagent/memory/MEMORY.md` -- a one-line-per-memory index loaded
#'     into context each session.
#' @name memory
#' @keywords internal
NULL

.memory_dir <- function() {
  file.path(.get_codeagent_dir(), "memory")
}

.ensure_memory_dir <- function() {
  d <- .memory_dir()
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# Slugify a title into a safe filename stem.
.memory_slug <- function(title) {
  s <- tolower(trimws(title %||% "memory"))
  s <- gsub("[^a-z0-9]+", "-", s)
  s <- gsub("^-+|-+$", "", s)
  if (!nzchar(s)) s <- paste0("memory-", substr(.generate_uuid_v4(), 1L, 8L))
  substr(s, 1L, 60L)
}

#' Write a memory to disk
#'
#' @param title Character. Short human title (also the filename slug).
#' @param content Character. The fact to remember.
#' @param description Character. One-line summary for the index/recall.
#' @return Invisibly, the file path written.
#' @keywords internal
write_memory <- function(title, content, description = "") {
  dir  <- .ensure_memory_dir()
  slug <- .memory_slug(title)
  path <- file.path(dir, paste0(slug, ".md"))

  body <- paste0(
    "---\n",
    "name: ", slug, "\n",
    "description: ", gsub("\n", " ", description %||% ""), "\n",
    "---\n\n",
    content, "\n"
  )
  writeLines(body, path)

  # Update MEMORY.md index (one line per memory, replace existing slug line).
  idx_path <- file.path(dir, "MEMORY.md")
  hook     <- if (nzchar(description)) description else title
  new_line <- sprintf("- [%s](%s.md) - %s", title, slug, gsub("\n", " ", hook))
  lines    <- if (file.exists(idx_path))
    tryCatch(readLines(idx_path, warn = FALSE), error = function(e) character(0))
  else character(0)
  lines <- lines[!grepl(sprintf("\\(%s\\.md\\)", slug), lines)]  # drop old entry
  lines <- c(lines, new_line)
  writeLines(lines, idx_path)

  invisible(path)
}

#' List stored memories (parsed front-matter + body)
#'
#' @return A list of `list(slug, description, content)`.
#' @keywords internal
list_memories <- function() {
  dir <- .memory_dir()
  if (!dir.exists(dir)) return(list())
  files <- list.files(dir, pattern = "\\.md$", full.names = TRUE)
  files <- files[basename(files) != "MEMORY.md"]
  lapply(files, function(f) {
    lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
    desc  <- ""
    body_start <- 1L
    if (length(lines) >= 1L && identical(trimws(lines[[1]]), "---")) {
      close_idx <- which(trimws(lines[-1]) == "---")[1L]
      if (!is.na(close_idx)) {
        fm <- lines[2:(close_idx)]
        d  <- grep("^description:", fm, value = TRUE)
        if (length(d)) desc <- trimws(sub("^description:", "", d[[1]]))
        body_start <- close_idx + 2L
      }
    }
    body <- paste(lines[body_start:length(lines)], collapse = "\n")
    list(slug = sub("\\.md$", "", basename(f)),
         description = desc,
         content = trimws(body))
  })
}

#' Recall memories as a compact block for system-reminder injection
#'
#' @param max_chars Integer. Cap total injected text.
#' @return Character(1). Empty string if no memories.
#' @keywords internal
recall_memories <- function(max_chars = 2000L) {
  mems <- list_memories()
  if (length(mems) == 0L) return("")
  parts <- vapply(mems, function(m) {
    head <- if (nzchar(m$description)) m$description else m$slug
    sprintf("- %s: %s", head, substr(m$content, 1L, 200L))
  }, character(1))
  block <- paste(parts, collapse = "\n")
  if (nchar(block) > max_chars) block <- paste0(substr(block, 1L, max_chars), "...")
  paste0("Persistent memory (recall from prior sessions):\n", block)
}

#' Delete a memory by slug
#' @keywords internal
delete_memory <- function(slug) {
  path <- file.path(.memory_dir(), paste0(slug, ".md"))
  if (file.exists(path)) unlink(path)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# remember tool — LLM-invoked memory write
# ---------------------------------------------------------------------------

#' Create the `remember` tool
#'
#' Lets the agent persist a durable fact to auto-memory. Read-only-ish (writes
#' only to the memory dir), so it is not permission-gated.
#'
#' @return An `ellmer::tool()` object.
#' @keywords internal
remember_tool <- function() {
  ellmer::tool(
    fun = function(title, content, description = "", `_intent` = NULL) {
      path <- tryCatch(write_memory(title, content, description),
                       error = function(e) NULL)
      if (is.null(path))
        return(.tool_result2("[Error] could not write memory.",
                             kind = "error", icon = "exclamation-triangle",
                             title = "Remember - error",
                             payload = list(message = "write failed")))
      .tool_result2(
        sprintf("Saved memory: %s", title),
        kind    = "text",
        icon    = "bookmark",
        title   = sprintf("Remembered <code>%s</code>", htmltools::htmlEscape(title)),
        payload = list(text = content)
      )
    },
    name = "remember",
    description = paste0(
      "Persist a durable fact to memory so it survives across sessions. Use for ",
      "user preferences, project conventions, decisions, or anything worth ",
      "recalling later. Memories are injected into future sessions automatically."
    ),
    arguments = list(
      title       = ellmer::type_string("Short title / filename slug.", required = TRUE),
      content     = ellmer::type_string("The fact to remember.", required = TRUE),
      description = ellmer::type_string("One-line summary for recall.", required = FALSE),
      `_intent`   = ellmer::type_string("Why this is being remembered.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "Remember",
      read_only_hint = FALSE
    )
  )
}

#' Register the remember tool to a Chat
#' @keywords internal
register_memory_tool <- function(chat) {
  tryCatch(chat$register_tool(remember_tool()), error = function(e) NULL)
  invisible(chat)
}
