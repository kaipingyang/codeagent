#' @title Skill System
#' @description Progressive skill loading for codeagent.
#'   Uses btw as the discovery and loading backend.
#'   Skill format: `<name>/SKILL.md` directories (btw-compatible).
#'
#'   Discovery order (later overrides earlier):
#'   1. codeagent built-ins (inst/skills/)
#'   2. Other attached R packages with inst/skills/
#'   3. btw built-in skills
#'   4. btw user dirs (~/.config/btw/skills/, ~/.btw/skills/)
#'   5. ~/.codeagent/skills/  (codeagent user global)
#'   6. .btw/skills/, .agents/skills/ (btw project dirs)
#'   7. .codeagent/skills/  (codeagent project local)
#'   8. .claude/skills/     (Claude Code compat)
#'   9. .codex/skills/      (Codex compat)
#'
#' @name skills
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Extra skill directories (beyond what btw scans)
# ---------------------------------------------------------------------------

.CODEAGENT_SKILL_SUBDIRS <- c(
  ".codeagent/skills",
  ".claude/skills",
  ".codex/skills"
)

.CODEAGENT_USER_SKILL_DIR <- file.path("~", ".codeagent", "skills")

# Build the full list of skill directories to scan, merging btw + codeagent paths
.skill_dirs <- function(cwd = getwd()) {
  dirs <- character(0)

  # 1. codeagent built-ins
  pkg_skills <- system.file("skills", package = "codeagent")
  if (nzchar(pkg_skills) && dir.exists(pkg_skills))
    dirs <- c(dirs, pkg_skills)

  # 2+3. btw built-ins + other attached packages (via btw if available)
  if (requireNamespace("btw", quietly = TRUE)) {
    tryCatch({
      dirs <- c(dirs, btw:::btw_skills_directories())
    }, error = function(e) NULL)
  }

  # 5. codeagent user global
  user_dir <- path.expand(.CODEAGENT_USER_SKILL_DIR)
  if (dir.exists(user_dir) && !user_dir %in% dirs)
    dirs <- c(dirs, user_dir)

  # 7-9. project local: .codeagent/, .claude/, .codex/
  for (sub in .CODEAGENT_SKILL_SUBDIRS) {
    d <- file.path(cwd, sub)
    if (dir.exists(d) && !d %in% dirs)
      dirs <- c(dirs, d)
  }

  unique(dirs)
}

# ---------------------------------------------------------------------------
# Skill discovery — list all skills (Level 1: metadata only)
# ---------------------------------------------------------------------------

# In-memory cache: key = cwd, value = list(sig, metas)
.skill_cache <- new.env(parent = emptyenv())

# mtime signature across all SKILL.md files
.skill_dirs_mtime_sig <- function(dirs) {
  sigs <- vapply(dirs, function(d) {
    if (!dir.exists(d)) return(0)
    files <- list.files(d, pattern = "^SKILL\\.md$",
                        recursive = TRUE, full.names = TRUE)
    if (length(files) == 0L) return(0)
    sum(as.numeric(file.mtime(files)))
  }, numeric(1))
  sum(sigs)
}

#' List skill metadata from all skill directories
#'
#' Scans all configured directories for `<name>/SKILL.md` files.
#' btw is used as the primary backend when available; codeagent-specific
#' paths (.claude/, .codex/) are merged in.
#' Results are cached per cwd; invalidated when any SKILL.md mtime changes.
#'
#' @param cwd Character. Project working directory.
#' @return Named list of `SkillMeta` objects (keyed by skill name).
#' @export
list_skills_meta <- function(cwd = getwd()) {
  dirs      <- .skill_dirs(cwd)
  cache_key <- .sanitize_path(.canonicalize_path(cwd))
  sig       <- .skill_dirs_mtime_sig(dirs)

  cached <- .skill_cache[[cache_key]]
  if (!is.null(cached) && isTRUE(cached$sig == sig))
    return(cached$metas)

  metas <- list()

  # Primary: btw backend covers — btw built-ins, attached packages (incl.
  # codeagent when installed), btw user dirs, btw project dirs.
  btw_covered <- character(0)
  if (requireNamespace("btw", quietly = TRUE)) {
    tryCatch({
      btw_skills <- btw:::btw_skills_list()
      btw_covered <- vapply(btw_skills, function(s) s$path, character(1))
      for (s in btw_skills) {
        metas[[s$name]] <- SkillMeta(
          name          = s$name,
          description   = s$description %||% "",
          argument_hint = s$argument_hint %||% "",
          auto_trigger  = TRUE,
          allowed_tools = s$allowed_tools %||% NULL,
          base_dir      = dirname(s$path),
          path          = s$path
        )
      }
    }, error = function(e) NULL)
  }

  # Supplement: codeagent-only paths not covered by btw.
  # Include codeagent inst/skills/ only when NOT already found by btw
  # (btw picks it up via attached_package_skill_dirs() when installed).
  extra_dirs <- c(
    system.file("skills", package = "codeagent"),
    path.expand(.CODEAGENT_USER_SKILL_DIR),
    vapply(.CODEAGENT_SKILL_SUBDIRS, function(s) file.path(cwd, s), character(1))
  )
  extra_dirs <- unique(extra_dirs[nzchar(extra_dirs) & dir.exists(extra_dirs)])

  for (d in extra_dirs) {
    subdirs <- list.dirs(d, full.names = TRUE, recursive = FALSE)
    for (subdir in subdirs) {
      skill_md <- file.path(subdir, "SKILL.md")
      if (!file.exists(skill_md)) next
      if (skill_md %in% btw_covered) next  # already loaded by btw — skip
      meta <- .parse_skill_md(skill_md)
      if (!is.null(meta)) metas[[meta$name]] <- meta
    }
  }

  .skill_cache[[cache_key]] <- list(sig = sig, metas = metas)
  metas
}

# ---------------------------------------------------------------------------
# Skill loading — full content on demand (Level 2)
# ---------------------------------------------------------------------------

#' Load a skill's full prompt
#'
#' Reads `SKILL.md` body and substitutes `$ARGUMENTS` / `$ARG1` etc.
#' Uses btw's `find_skill()` when available, falls back to direct file read.
#'
#' @param name Character. Skill name.
#' @param args Character. Arguments passed after the skill name.
#' @param cwd Character. Project working directory.
#' @return Character(1). The fully resolved prompt string.
#' @export
load_skill_prompt <- function(name, args = "", cwd = getwd()) {
  metas <- list_skills_meta(cwd)
  meta  <- metas[[name]]
  if (is.null(meta))
    stop("Skill not found: '", name, "'. Available: ",
         paste(names(metas), collapse = ", "), call. = FALSE)

  # Use btw's find_skill if available (handles resources listing too)
  if (requireNamespace("btw", quietly = TRUE)) {
    skill_info <- tryCatch(btw:::find_skill(name), error = function(e) NULL)
    if (!is.null(skill_info) && skill_info$validation$valid) {
      fm   <- tryCatch(
        frontmatter::read_front_matter(skill_info$path),
        error = function(e) list(body = NULL)
      )
      body <- fm$body %||% ""
      return(.substitute_args(body, args))
    }
  }

  # Fallback: direct file read
  lines <- readLines(meta$path, warn = FALSE)
  body  <- .strip_frontmatter(lines)
  .substitute_args(paste(body, collapse = "\n"), args)
}

# ---------------------------------------------------------------------------
# Skill tool — LLM semantic auto-trigger
# ---------------------------------------------------------------------------

#' Create the skill tool for LLM auto-triggering
#'
#' Registers an ellmer tool that allows the LLM to semantically match user
#' intent to skills and load them automatically — even without explicit
#' `/name` syntax from the user.
#'
#' @param cwd Character. Project working directory.
#' @return An `ellmer::tool()` object, or `NULL` if no skills exist.
#' @keywords internal
.make_skill_tool <- function(cwd = getwd()) {
  metas       <- list_skills_meta(cwd)
  auto_skills <- Filter(function(m) isTRUE(m$auto_trigger), metas)
  if (length(auto_skills) == 0L) return(NULL)

  skill_list <- paste(vapply(auto_skills, function(m) {
    hint <- if (nzchar(m$argument_hint %||% ""))
      sprintf(" [args: %s]", m$argument_hint) else ""
    sprintf("- %s: %s%s", m$name, m$description, hint)
  }, character(1)), collapse = "\n")

  ellmer::tool(
    fun = function(name, args = "", `_intent` = NULL) {
      result <- tryCatch(
        load_skill_prompt(name, args, cwd),
        error = function(e) paste0("[Skill error] ", conditionMessage(e))
      )
      intent_val <- `_intent`
      ellmer::ContentToolResult(
        value = result,
        extra = list(
          display = list(
            title    = htmltools::HTML(sprintf(
              "Skill: <code>/%s</code>%s",
              htmltools::htmlEscape(name),
              if (!is.null(intent_val) && nzchar(intent_val))
                sprintf(" <em style='color:#888;font-size:0.85em;'>%s</em>",
                        htmltools::htmlEscape(intent_val))
              else ""
            )),
            markdown = sprintf("**Skill `/%s` loaded**\n\n%s",
                               name, substr(result, 1L, 200L))
          )
        )
      )
    },
    description = paste0(
      "Load specialized skill instructions. ",
      "Call this tool when the user's request SEMANTICALLY matches a skill — ",
      "even if they did not use /name syntax. ",
      "Match by intent, not just keywords.\n\n",
      "Available skills:\n", skill_list, "\n\n",
      "After loading, follow the skill's instructions exactly."
    ),
    arguments = c(
      list(
        name = ellmer::type_enum(
          values      = names(auto_skills),
          description = "Skill name to load.",
          required    = TRUE
        ),
        args = ellmer::type_string(
          description = "Arguments to pass (e.g. task description for /plan).",
          required    = FALSE
        )
      ),
      `_intent` = list(ellmer::type_string(
        description = "Brief description of why this skill was selected.",
        required    = FALSE
      ))
    ),
    annotations = ellmer::tool_annotations(
      title          = "Load Skill",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# System prompt helper (progressive disclosure)
# ---------------------------------------------------------------------------

#' Build skill hint for system prompt
#'
#' Returns skill listing for the system prompt.
#' Uses btw's system prompt format when available; falls back to simple list.
#'
#' @param cwd Character. Project working directory.
#' @param max_tokens Integer. Approximate token budget.
#' @return Character(1). The skill hint block, or `""` if no skills found.
#' @export
build_skill_hint <- function(cwd = getwd(), max_tokens = 1000L) {
  metas <- list_skills_meta(cwd)
  if (length(metas) == 0L) return("")

  # Build unified XML-style listing (mirrors btw format) covering all skills
  skill_xml <- paste(vapply(metas, function(m) {
    hint <- if (nzchar(m$argument_hint %||% ""))
      sprintf('\n  <argument-hint>%s</argument-hint>', m$argument_hint) else ""
    sprintf(
      '<skill>\n  <name>%s</name>\n  <description>%s</description>%s\n</skill>',
      m$name, m$description, hint
    )
  }, character(1)), collapse = "\n")

  hint <- paste0(
    "## Skills\n\n",
    "You have access to specialized skills. ",
    "Call the `use_skill` tool when a user request semantically matches a skill — ",
    "even without explicit /name syntax. Users may also type /name to invoke directly.\n\n",
    "<available_skills>\n", skill_xml, "\n</available_skills>"
  )

  budget_chars <- max_tokens * 4L
  if (nchar(hint) > budget_chars) hint <- substr(hint, 1L, budget_chars)
  hint
}

# ---------------------------------------------------------------------------
# Input pre-processing (detect /skillname invocations)
# ---------------------------------------------------------------------------

#' Pre-process user input for skill invocation
#'
#' Detects `/skillname [args]` patterns.
#'
#' @param input Character(1). Raw user input.
#' @param cwd Character. Working directory.
#' @return Named list with `type` (`"skill"` or `"normal"`).
#' @keywords internal
.preprocess_input <- function(input, cwd = getwd()) {
  trimmed  <- trimws(input)
  m        <- regexec("^/(\\w+)\\s*(.*)", trimmed, perl = TRUE)
  captures <- regmatches(trimmed, m)[[1L]]
  if (length(captures) < 3L)
    return(list(type = "normal", input = input))
  list(type = "skill", name = captures[2L], args = trimws(captures[3L]))
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Parse SKILL.md frontmatter for a skill directory
.parse_skill_md <- function(path) {
  lines <- tryCatch(readLines(path, n = 40L, warn = FALSE),
                    error = function(e) NULL)
  if (is.null(lines) || length(lines) < 2L) return(NULL)
  if (!identical(trimws(lines[1L]), "---")) return(NULL)

  end_idx <- which(trimws(lines[-1L]) == "---")[1L] + 1L
  if (is.na(end_idx)) return(NULL)
  fm_lines <- lines[2L:(end_idx - 1L)]

  parsed <- list()
  i <- 1L
  while (i <= length(fm_lines)) {
    ln <- fm_lines[[i]]
    # list values (allowed-tools: [A, B] or multiline)
    m_key <- regexec("^([a-zA-Z_-]+):\\s*(.*)", ln)
    caps  <- regmatches(ln, m_key)[[1L]]
    if (length(caps) == 3L) {
      key <- caps[2L]; val <- trimws(caps[3L])
      if (grepl("^\\[", val)) {
        # inline list: [A, B, C]
        items <- trimws(strsplit(gsub("^\\[|\\]$", "", val), ",")[[1L]])
        parsed[[key]] <- items
      } else {
        parsed[[key]] <- val
      }
    }
    i <- i + 1L
  }

  name <- parsed[["name"]] %||% basename(dirname(path))
  if (!nzchar(name)) return(NULL)

  auto_trigger <- if (!is.null(parsed[["auto-trigger"]]))
    !identical(tolower(parsed[["auto-trigger"]]), "false") else TRUE

  SkillMeta(
    name          = name,
    description   = parsed[["description"]] %||% "",
    argument_hint = parsed[["argument-hint"]] %||% "",
    auto_trigger  = auto_trigger,
    allowed_tools = parsed[["allowed-tools"]] %||% NULL,
    base_dir      = dirname(path),
    path          = path
  )
}

# Remove YAML frontmatter from lines
.strip_frontmatter <- function(lines) {
  if (length(lines) < 2L || !identical(trimws(lines[1L]), "---")) return(lines)
  end_idx <- which(trimws(lines[-1L]) == "---")[1L] + 1L
  if (is.na(end_idx)) return(lines)
  if (end_idx >= length(lines)) return(character(0))
  lines[(end_idx + 1L):length(lines)]
}

# Substitute $ARGUMENTS / $ARG1 / $ARG2 in skill body
.substitute_args <- function(body, args = "") {
  body <- gsub("$ARGUMENTS", args, body, fixed = TRUE)
  tokens <- strsplit(trimws(args), "\\s+")[[1L]]
  for (i in seq_along(tokens))
    body <- gsub(paste0("$ARG", i), tokens[i], body, fixed = TRUE)
  body
}
