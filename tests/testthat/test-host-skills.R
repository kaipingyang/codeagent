# Host-chosen skill sets: codeagent_client(skills =) / list_skills_meta(skills =).

local_skill_dir <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  write_skill <- function(name, description, body) {
    d <- file.path(root, "skills", name)
    dir.create(d, recursive = TRUE)
    writeLines(c("---", paste0("name: ", name), paste0("description: ", description),
                 "---", body), file.path(d, "SKILL.md"))
  }
  write_skill("bip-query", "Plan results_table queries", "BIP QUERY BODY")
  # same name as a codeagent built-in: the host's own copy must win
  write_skill("compact", "Host compact", "HOST COMPACT BODY")
  root
}

fake_chat <- function() {
  ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                 credentials = function() "k")
}

test_that("NULL keeps the default discovery", {
  root <- local_skill_dir()
  expect_identical(names(list_skills_meta(root, NULL)),
                   names(list_skills_meta(root)))
})

test_that("FALSE offers no skills", {
  root <- local_skill_dir()
  expect_length(list_skills_meta(root, FALSE), 0L)
  expect_identical(build_skill_hint(root, skills = FALSE), "")
  expect_null(.make_skill_tool(root, FALSE))
})

test_that("a directory offers exactly its skills", {
  root <- local_skill_dir()
  metas <- list_skills_meta(root, "skills")
  expect_setequal(names(metas), c("bip-query", "compact"))
  expect_identical(load_skill_prompt("compact", "", root, "skills"), "HOST COMPACT BODY")
  expect_identical(load_skill_prompt("bip-query", "", root, "skills"), "BIP QUERY BODY")
  expect_error(load_skill_prompt("lint", "", root, "skills"), "Skill not found")
})

test_that("names pick discovered skills next to a host directory", {
  root <- local_skill_dir()
  skip_if_not("lint" %in% names(list_skills_meta(root)))
  metas <- list_skills_meta(root, c("skills", "lint"))
  expect_setequal(names(metas), c("bip-query", "compact", "lint"))
  # a name the host directory provides is taken from there
  expect_identical(list_skills_meta(root, c("skills", "compact"))$compact$description,
                   "Host compact")
})

test_that("an unknown entry is an error naming it", {
  root <- local_skill_dir()
  expect_error(list_skills_meta(root, c("skills", "no-such-skill")),
               "Unknown skill: 'no-such-skill'")
  expect_error(list_skills_meta(root, 1), "must be NULL, FALSE, or a character")
  expect_error(list_skills_meta(root, c("skills", "")), "must be NULL, FALSE")
})

test_that("the skill tool and the prompt list only the chosen skills", {
  root <- local_skill_dir()
  tool <- .make_skill_tool(root, "skills")
  expect_match(tool@description, "bip-query")
  expect_false(grepl("- lint:", tool@description, fixed = TRUE))
  hint <- build_skill_hint(root, skills = "skills")
  expect_match(hint, "<name>bip-query</name>", fixed = TRUE)
  expect_false(grepl("<name>lint</name>", hint, fixed = TRUE))
  defs <- .slash_command_defs(root, "skills")
  expect_true(any(vapply(defs, function(d) identical(d$name, "bip-query"), NA)))
  expect_false(any(vapply(defs, function(d) identical(d$name, "lint"), NA)))
})

test_that("codeagent_client stores the selection with absolute directories", {
  root <- local_skill_dir()
  client <- codeagent_client(fake_chat(), register_tools = FALSE, cwd = root,
                             setting_sources = "project", skills = "skills")
  expect_identical(client$settings$skills,
                   normalizePath(file.path(root, "skills"), mustWork = FALSE))
  expect_setequal(names(list_skills_meta(tempdir(), client$settings$skills)),
                  c("bip-query", "compact"))
  expect_null(codeagent_client(fake_chat(), register_tools = FALSE, cwd = root,
                               setting_sources = "project")$settings$skills)
})

test_that("codeagent_client rejects an unknown skill at creation", {
  root <- local_skill_dir()
  expect_error(codeagent_client(fake_chat(), register_tools = FALSE, cwd = root,
                                setting_sources = "project",
                                skills = c("skills", "no-such-skill")),
               "Unknown skill")
})
