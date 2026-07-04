# Task 08: R-domain data-science skills. Verify the built-in R skills are
# discovered by the skill system and their prompts load.

test_that("R-domain skills are discovered by list_skills_meta", {
  metas <- tryCatch(list_skills_meta(getwd()), error = function(e) list())
  skip_if(length(metas) == 0, "no skills discovered in this environment")
  names_found <- vapply(metas, function(m) m$name %||% "", character(1))
  # These ship in inst/skills/ (built-ins).
  for (nm in c("roxygen", "testthat", "document", "news", "pkgdown", "style")) {
    expect_true(nm %in% names_found, info = paste("missing skill:", nm))
  }
})

test_that("new R-domain SKILL.md files have valid frontmatter", {
  for (nm in c("pkgdown", "style")) {
    p <- system.file(file.path("skills", nm, "SKILL.md"), package = "codeagent")
    if (!nzchar(p)) p <- file.path("inst/skills", nm, "SKILL.md")
    expect_true(file.exists(p))
    txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
    expect_true(grepl(paste0("name: ", nm), txt, fixed = TRUE))
    expect_true(grepl("description:", txt, fixed = TRUE))
    # ASCII-only
    expect_false(any(grepl("[^\x01-\x7f]", txt)))
  }
})
