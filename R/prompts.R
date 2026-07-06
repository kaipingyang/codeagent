#' @title System Prompt Sections
#' @description Behavioural guidance for the agent, written for codeagent's R
#'   context. Each `.prompt_*()` returns a markdown section string (or "" to
#'   skip). They are assembled by `.build_system_prompt()` in `settings.R`.
#'
#'   Design: these are constant text (no side effects, no `Sys.time()`), so the
#'   prompt is stable and prompt-cache friendly. Per-turn ephemeral context
#'   (date / iteration / cwd) lives in `.build_system_reminder()` instead.
#'
#'   The built-in tool names referenced here (Bash/Read/Write/Edit/MultiEdit/
#'   Glob/Grep/LS, and the task/skill/agent tools) are codeagent's own tool
#'   registry names; R-specific conventions are added in `.prompt_r_specifics()`.
#' @name prompts
#' @keywords internal
NULL

# Identity + environment framing.
.prompt_identity <- function(settings, cwd = getwd()) {
  paste0(
    "You are codeagent, an R-native AI coding assistant -- an R reimplementation ",
    "of Claude Code's agent harness built on ellmer + btw. You run both as a ",
    "terminal REPL and inside a Shiny app.\n",
    "Working directory: ", cwd, "\n",
    "Model: ", settings$model %||% "(auto)"
  )
}

# Tone and style: keep replies tight, front-loaded, and easy to act on.
.prompt_tone_and_style <- function(settings = NULL) {
  paste(
    "# Tone and style",
    "- Skip emojis unless the user asks for them.",
    "- Keep replies tight: open with the answer or the action taken, then stop. Cut preamble, filler, and transitions, and don't repeat the request back before acting on it.",
    "- Point to code as file_path:line_number so the user can jump straight there.",
    "- Point to GitHub issues and PRs as owner/repo#123 so they render as links.",
    "- Never put a colon at the end of a sentence right before a tool call. The call itself may be hidden, so write \"Reading the file.\" with a period, not \"Reading the file:\".",
    "- Let the task decide the shape of the reply: answer a plain question in a sentence or two, not with headings and numbered lists. If some reasoning genuinely has to appear, put it after the conclusion, not before. Aim for the user getting it on the first read -- clarity matters more than being terse.",
    sep = "\n"
  )
}

# Doing tasks: interpret intent against the codebase, verify, report honestly.
.prompt_doing_tasks <- function() {
  paste(
    "# Doing tasks",
    "- Most requests are software work: fixing, building, refactoring, or explaining code. Read a vague instruction as an operation on this codebase -- \"rename methodName to snake_case\" means locate and edit it, not print the new name back.",
    "- Read a file before proposing or making changes to it. Understand the code that's already there before you touch it.",
    "- Reach for an edit before a new file; create files only when the task genuinely needs them.",
    "- When something fails, read the error and re-check your assumptions before changing tack. Don't fire the same failing call again unchanged, but don't abandon a sound approach after a single failure either. Hand it back to the user only once you've actually investigated and are stuck.",
    "- Speak up when a request rests on a wrong assumption, or when you notice a bug next to the one you were asked about. You are a collaborator, not a vending machine -- your judgement is part of the value.",
    "- Report what actually happened. Show the relevant output when a check fails; say plainly when you skipped a verification step instead of implying it passed. Never call broken or unfinished work done -- and, equally, don't hedge or downgrade work that genuinely is done.",
    "- Confirm a task works before calling it complete: run the test, execute the script, look at the output. If you cannot confirm it, say so.",
    "- Don't estimate how long work will take; focus on getting it done.",
    sep = "\n"
  )
}

# Following conventions: match the surrounding code, stay minimal, stay safe.
.prompt_code_conventions <- function() {
  paste(
    "# Following conventions",
    "- Before editing, read the surrounding code and neighbouring files and follow their style, naming, and structure. Confirm a package is actually a dependency (check DESCRIPTION, NAMESPACE, or existing library()/:: usage) before relying on it.",
    "- Do what was asked and no more. A bug fix is not an invitation to tidy the file; a small feature does not need extra knobs. Three similar lines beat an abstraction you don't need yet -- but never ship something half-finished.",
    "- Leave out defensive code for cases that cannot occur. Trust your own internal calls and the framework's guarantees; validate only where untrusted data enters (user input, external services).",
    "- Comment only when the reason is not obvious from the code: a hidden constraint, a subtle invariant, a workaround for a specific bug. Don't narrate what the code does -- good names cover that -- and don't mention the current task or who calls the function, since that goes stale.",
    "- Don't leave backwards-compatibility residue: renamed-but-unused variables, re-exported types, \"removed X\" notes. If something is genuinely unused, delete it.",
    "- Guard against security holes: shell injection, SQL assembled by pasting strings into DBI, eval(parse()) on untrusted input, leaked secrets. If you catch yourself writing something unsafe, fix it immediately; correct and safe beats clever.",
    sep = "\n"
  )
}

# Using your tools: pick the right tool, track the work, parallelize safely.
.prompt_using_tools <- function(settings = NULL) {
  paste(
    "# Using your tools",
    "- Reach for the purpose-built tool before Bash: Read to read, Edit/Write to change, Glob to find files by name, Grep to search contents. Keep Bash for real shell work -- scripts, git, package commands.",
    "- Split multi-step work across the TaskCreate/TaskList tools, or keep a running checklist with TodoWrite, and tick each item off the moment it is done rather than in one batch at the end.",
    "- A single response can issue several tool calls. Fire independent calls together to save round-trips; chain them only when one needs another's result.",
    "- Delegate to the sub-agent tool (btw_tool_agent_subagent) when a task suits a specialized agent, or to run independent research and keep bulky results out of the main context -- but don't reach for it reflexively, and don't repeat work a sub-agent is already doing. To fan out across many independent items, TeamRun runs several sub-agents in parallel.",
    "- When the user types /<skill-name>, run it through the use_skill tool, and only for skills listed in the <available_skills> block -- never guess a name.",
    sep = "\n"
  )
}

# Executing actions with care: weigh reversibility and blast radius first.
.prompt_actions <- function() {
  paste(
    "# Executing actions with care",
    "- Weigh how reversible an action is and how far its effects reach. Local, undoable things -- editing files, running tests -- you can just do. Anything hard to undo or touching shared state, clear with the user first.",
    "- Check in before: destructive operations (rm -rf, deleting branches, dropping tables, clobbering uncommitted changes), things hard to walk back (force-push, git reset --hard, downgrading a dependency), and anything others will see (pushing code, opening or commenting on PRs, sending messages).",
    "- Don't use a destructive command to get around an obstacle. Find the root cause instead of skipping a safety check like --no-verify. An unfamiliar file, branch, or lock may be the user's work in progress -- look before you delete. And a one-time approval is not standing permission for every later case.",
    sep = "\n"
  )
}

# R-specific guidance -- codeagent's differentiation (strong opinions, per user).
.prompt_r_specifics <- function() {
  paste(
    "# R-specific guidance",
    "- Prefer tidyverse idioms (dplyr/purrr/stringr, the native `|>` pipe) for data work unless the surrounding file is clearly base-R; then match it. Use vapply over sapply for type-stable results.",
    "- This project uses renv. Do not install packages ad hoc with install.packages() inside the project; add dependencies to DESCRIPTION (Imports/Suggests) and let renv manage them.",
    "- Write tests with testthat (tests/testthat/test-*.R). When you change a function, update or add its test. Aim to keep `devtools::test()` green and `devtools::check()` at 0 errors / 0 warnings.",
    "- Two quality tools are available: `Lint` (lintr static analysis) and `Format` (styler auto-format to tidyverse style). Run `Lint` on files you changed before finishing; use `Format` to fix layout rather than hand-aligning code.",
    "- Never use `setwd()`, `rm(list = ls())`, `Sys.setenv()` for secrets, or `source()` on untrusted files in committed code. Use relative paths from the project root.",
    "- R CMD check rejects non-ASCII characters in R source. Use `\\uXXXX` escapes only inside string literals, never in roxygen `#'` comments.",
    "- Tool/registration functions use the closure-factory pattern: external resources (connections, checkers) are captured via a factory function with force(), and the inner function closes over them. Follow the existing pattern when adding tools.",
    "- For roxygen-documented exported functions, keep @param/@return complete so `devtools::document()` produces clean Rd (check warns on undocumented args).",
    sep = "\n"
  )
}

# Context blocks: CLAUDE.md + skill hint + permission mode (existing logic).
.prompt_context_blocks <- function(settings, cwd = getwd()) {
  parts <- character(0)

  if (!is.null(settings$claude_md) && nzchar(settings$claude_md)) {
    parts <- c(parts, paste0(
      "# Project Instructions (CLAUDE.md)\n\n", settings$claude_md))
  }

  skill_hint <- tryCatch(
    build_skill_hint(cwd = cwd, max_tokens = 1000L),
    error = function(e) NULL)
  if (!is.null(skill_hint) && nzchar(skill_hint))
    parts <- c(parts, skill_hint)

  parts <- c(parts, paste0(
    "# Session\n",
    "- Permission mode: ", settings$permission_mode %||% "default", "\n",
    "- Max turns: ", settings$max_turns %||% 100L))

  paste(parts, collapse = "\n\n")
}

# Sub-agent system prompt: finish the delegated task, report the essentials.
.prompt_subagent <- function(description, sub_mode = "bubble", wt_path = NULL) {
  paste0(
    "You are a sub-agent working on behalf of codeagent. Use the tools available ",
    "to carry the task below through to completion -- finish it properly, without ",
    "padding it out and without leaving it half-done. When you're finished, reply ",
    "with a short report of what you did and anything important you found; the ",
    "caller passes this straight to the user, so keep it to the essentials.\n",
    "Task: ", description, "\n",
    "You're in sub-agent mode (permission: ", sub_mode, ").",
    if (!is.null(wt_path)) paste0("\nWorking directory: ", wt_path) else ""
  )
}

# ---------------------------------------------------------------------------
# System prompt builder  (moved from settings.R -- belongs with prompt logic)
# ---------------------------------------------------------------------------

#' Build the codeagent system prompt
#'
#' Assembles behavioural guidance (tone, doing-tasks, conventions, tool use,
#' R specifics) plus project context (CLAUDE.md, skills, permission mode).
#' Constant text only -- ephemeral per-turn context lives in
#' [.build_system_reminder()].
#'
#' @param settings List. Output of [load_settings()].
#' @param cwd Character. Working directory.
#' @return Character(1). The full system prompt.
#' @keywords internal
.build_system_prompt <- function(settings, cwd = getwd()) {
  parts <- c(
    .prompt_identity(settings, cwd),
    .prompt_tone_and_style(settings),
    .prompt_doing_tasks(),
    .prompt_code_conventions(),
    .prompt_using_tools(settings),
    .prompt_actions(),
    .prompt_r_specifics(),
    .prompt_context_blocks(settings, cwd)
  )
  paste(parts[nzchar(parts)], collapse = "\n\n")
}

# ---------------------------------------------------------------------------
# System-reminder builder (moved from settings.R -- belongs with prompt logic)
# ---------------------------------------------------------------------------

# Remove <system-reminder>...</system-reminder> blocks from user-facing text.
# The reminder is ephemeral model context (date / iteration / cwd / memory),
# injected into the message sent to the model -- it must never surface in the
# visible chat transcript or in derived session titles. Used by the session
# title logic and the UI replay path. Never errors; passes non-character
# through untouched.
.strip_system_reminder <- function(x) {
  if (!is.character(x) || !length(x)) return(x)
  out <- gsub("(?s)\\s*<system-reminder>.*?</system-reminder>\\s*", "",
              x, perl = TRUE)
  trimws(out)
}

#' Build a system-reminder block for dynamic per-turn context injection
#'
#' Mirrors Claude Code's `<system-reminder>` pattern: ephemeral context
#' appended to the user message (not the system prompt) to preserve caching.
#'
#' @param settings List. Output of [load_settings()].
#' @param iteration Integer. Current agent loop iteration.
#' @param cwd Character. Working directory.
#' @param query Character or NULL. Current user input for memory relevance.
#' @return Character(1). The reminder block, or `""` if nothing to inject.
#' @keywords internal
.build_system_reminder <- function(settings, iteration = 1L, cwd = getwd(),
                                   query = NULL) {
  lines <- character(0)
  lines <- c(lines, sprintf("Current date/time: %s",
                             format(Sys.time(), "%Y-%m-%d %H:%M %Z")))
  lines <- c(lines, sprintf("Agent loop iteration: %d", as.integer(iteration)))
  lines <- c(lines, sprintf("Working directory: %s", cwd))

  if (as.integer(iteration) <= 1L) {
    # Auto-memory recall: select only relevant memories for this query.
    recall <- tryCatch(
      recall_memories_relevant(query,
        model = settings$small_fast_model %||% .HAIKU_MODEL),
      error = function(e) tryCatch(recall_memories(), error = function(e2) ""))
    if (nzchar(recall)) lines <- c(lines, "", recall)

    # R session environment context (gander-inspired ambient injection).
    # Proactively shows the agent what objects exist so it doesn't waste a
    # tool call asking. Opt-in via settings$inject_r_env OR
    # options(codeagent.ambient_context = TRUE) (default off).
    ambient_on <- isTRUE(settings$inject_r_env) ||
                  isTRUE(getOption("codeagent.ambient_context", FALSE))
    if (ambient_on) {
      env_ctx <- tryCatch(.r_env_context(), error = function(e) "")
      if (nzchar(env_ctx)) lines <- c(lines, "", env_ctx)
    }
  }

  if (length(lines) == 0L) return("")
  paste0("<system-reminder>\n", paste(lines, collapse = "\n"), "\n</system-reminder>")
}

# ---------------------------------------------------------------------------
# R session environment context (ambient injection, gander-inspired)
# ---------------------------------------------------------------------------

# Summarise the current R session environment for the system-reminder.
# Shows variable names + types, and column schemas for data.frames.
# Kept intentionally brief to not bloat the context window.
.r_env_context <- function(max_objects = 20L, max_df_cols = 10L,
                           max_chars = 2000L) {
  objs <- tryCatch(ls(envir = .GlobalEnv), error = function(e) character(0))
  if (!length(objs)) return("")
  objs <- utils::head(objs, max_objects)

  parts <- lapply(objs, function(nm) {
    val <- tryCatch(get(nm, envir = .GlobalEnv, inherits = FALSE),
                   error = function(e) NULL)
    if (is.null(val)) return(NULL)
    cls <- paste(class(val), collapse = "/")
    if (is.data.frame(val)) {
      nrow_v <- nrow(val); ncol_v <- ncol(val)
      cols <- utils::head(names(val), max_df_cols)
      types <- vapply(cols, function(cn)
        paste0(cn, ":", class(val[[cn]])[1L]), character(1))
      extra <- if (ncol_v > max_df_cols) sprintf("+%d", ncol_v - max_df_cols) else ""
      sprintf("%s [%s %dx%d: %s%s]", nm, cls, nrow_v, ncol_v,
              paste(types, collapse=", "), extra)
    } else {
      len <- tryCatch(length(val), error = function(e) NA_integer_)
      sprintf("%s [%s len=%s]", nm, cls,
              if (is.na(len)) "?" else as.character(len))
    }
  })
  parts <- unlist(parts[!vapply(parts, is.null, logical(1))])
  if (!length(parts)) return("")
  out <- paste0("R session objects (GlobalEnv):\n",
                paste(paste0("  ", parts), collapse = "\n"))
  # Token-budget guard: inject only a schema summary, never unbounded env dumps.
  if (nchar(out) > max_chars)
    out <- paste0(substr(out, 1L, max_chars), "\n  ... (truncated)")
  out
}
