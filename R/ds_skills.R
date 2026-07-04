#' @title Data-science skill libraries (posit-dev/skills integration)
#' @description Convenience installers for external data-science skill
#'   collections. codeagent discovers skills from btw's skill directories
#'   (`btw:::btw_skills_directories()`), so anything installed with btw's
#'   installers is picked up automatically by [list_skills_meta()] and the
#'   `/name` slash commands -- no extra wiring needed.
#' @name ds_skills
#' @keywords internal
NULL

#' Install Posit's data-science skill collection (posit-dev/skills)
#'
#' Installs the [posit-dev/skills](https://github.com/posit-dev/skills)
#' collection (r-lib / shiny / quarto / tidyverse / open-source domains) via
#' btw, into a btw skill directory that codeagent already discovers. After
#' installing, the skills appear in [list_skills_meta()] and as `/name`
#' commands.
#'
#' This is a thin, documented wrapper over
#' [btw::btw_skill_install_github()] -- codeagent does not vendor or re-host the
#' skills; it uses the upstream collection directly.
#'
#' @param skill Which posit-dev/skills to install: `NULL` (default) installs a
#'   curated R / data-science set; `"all"` installs every skill in the repo;
#'   or pass one or more skill names (character vector). btw installs one skill
#'   at a time, so multiple names are installed in a loop.
#' @param scope Character. `"user"` (default) installs to the user-global btw
#'   skills dir; `"project"` installs to the project's `.btw/skills`.
#' @param overwrite Logical. Overwrite an existing skill of the same name.
#' @return Invisibly `TRUE` if all requested skills installed, else `FALSE`.
#' @examples
#' \dontrun{
#' install_ds_skills()                        # curated R/data-science set
#' install_ds_skills("all")                   # everything in posit-dev/skills
#' install_ds_skills("shiny-bslib")           # a specific skill
#' install_ds_skills(c("cli", "quarto-authoring"))
#' list_skills_meta()                          # now includes the new skills
#' }
#' @seealso [btw::btw_skill_install_github()], [list_skills_meta()]
#' @export
install_ds_skills <- function(skill = NULL, scope = c("user", "project"),
                              overwrite = FALSE) {
  scope <- match.arg(scope)
  if (!requireNamespace("btw", quietly = TRUE)) {
    cli::cli_warn(c(
      "btw is required to install data-science skills.",
      "i" = 'Install it with {.code pak::pak("posit-dev/btw")}.'
    ))
    return(invisible(FALSE))
  }
  skills <-
    if (is.null(skill))            .posit_ds_default_skills()
    else if (identical(skill, "all")) .posit_dev_skill_names()
    else                           as.character(skill)
  skills <- unique(skills[nzchar(skills)])
  if (!length(skills)) {
    cli::cli_warn("No posit-dev/skills selected to install.")
    return(invisible(FALSE))
  }
  cli::cli_alert_info(
    "Installing {length(skills)} skill{?s} from posit-dev/skills ({scope} scope)...")
  ok <- vapply(skills, function(s) {
    tryCatch({
      # btw installs a single skill from a multi-skill repo at a time.
      btw::btw_skill_install_github(
        repo = "posit-dev/skills", skill = s, scope = scope,
        overwrite = overwrite)
      TRUE
    }, error = function(e) {
      cli::cli_warn(c("Failed to install skill {.val {s}}.",
                      "x" = conditionMessage(e)))
      FALSE
    })
  }, logical(1))
  n_ok <- sum(ok)
  if (n_ok > 0L)
    cli::cli_alert_success(
      "Installed {n_ok}/{length(skills)} skill{?s}. Run {.code list_skills_meta()} to see them.")
  invisible(n_ok == length(skills))
}

# Curated R / data-science subset of posit-dev/skills (sensible default so we
# don't pull ~40 skills incl. unrelated workflow ones). Override with "all" or
# explicit names.
.posit_ds_default_skills <- function() {
  c("quarto-authoring", "shiny-bslib", "shiny-bslib-theming", "cli",
    "brand-yml", "ggsql", "cran-extrachecks")
}

# All skill names in a GitHub skills repo, parsed from btw's own enumeration.
.posit_dev_skill_names <- function(repo = "posit-dev/skills") {
  fallback <- unique(c(.posit_ds_default_skills(), "describe-design",
                       "critical-code-reviewer", "review-testing", "implement"))
  if (!requireNamespace("btw", quietly = TRUE)) return(fallback)
  # btw enumerates the repo's skills in its error when no single skill is given;
  # parse that authoritative flat list (falls back to the curated set on error).
  msg <- tryCatch({
    btw::btw_skill_install_github(repo = repo, skill = NULL, scope = "project")
    NULL
  }, error = function(e) conditionMessage(e))
  if (is.null(msg)) return(fallback)
  nms <- gsub('"', '', regmatches(msg, gregexpr('"[^"]+"', msg))[[1]])
  nms <- nms[nzchar(nms) & !grepl("[[:space:]]", nms)]
  if (length(nms)) unique(nms) else fallback
}
