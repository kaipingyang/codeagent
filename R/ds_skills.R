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
#' @param skill Character or NULL. Install only a specific skill from the
#'   collection; `NULL` (default) installs all.
#' @param scope Character. `"user"` (default) installs to the user-global btw
#'   skills dir; `"project"` installs to the project's `.btw/skills`.
#' @param overwrite Logical. Overwrite an existing skill of the same name.
#' @return Invisibly `TRUE` on success, `FALSE` if btw is unavailable.
#' @examples
#' \dontrun{
#' install_ds_skills()                       # all posit-dev/skills, user scope
#' install_ds_skills(skill = "shiny")        # just one
#' list_skills_meta()                        # now includes the new skills
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
  cli::cli_alert_info(
    "Installing posit-dev/skills ({scope} scope) via btw...")
  ok <- tryCatch({
    btw::btw_skill_install_github(
      repo      = "posit-dev/skills",
      skill     = skill,
      scope     = scope,
      overwrite = overwrite
    )
    TRUE
  }, error = function(e) {
    cli::cli_warn(c("Failed to install posit-dev/skills.",
                    "x" = conditionMessage(e)))
    FALSE
  })
  if (isTRUE(ok))
    cli::cli_alert_success(
      "Installed. Run {.code list_skills_meta()} to see the new skills.")
  invisible(ok)
}
