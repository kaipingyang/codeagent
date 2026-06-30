# tests/testthat/test-memory.R
# Tests for auto-memory (M6): write / list / recall / remember tool / injection.

.with_temp_home <- function(code) {
  old <- Sys.getenv("HOME")
  tmp <- withr::local_tempdir()
  Sys.setenv(HOME = tmp)
  on.exit(Sys.setenv(HOME = old), add = TRUE)
  force(code)
}

test_that("write_memory persists a file with front-matter + updates index", {
  .with_temp_home({
    p <- write_memory("prefers-chinese", "User wants Chinese replies", "language pref")
    expect_true(file.exists(p))
    lines <- readLines(p)
    expect_true(any(grepl("^name: prefers-chinese", lines)))
    expect_true(any(grepl("^description: language pref", lines)))
    expect_true(any(grepl("User wants Chinese replies", lines)))
    # index
    idx <- file.path(dirname(p), "MEMORY.md")
    expect_true(file.exists(idx))
    expect_true(any(grepl("prefers-chinese", readLines(idx))))
  })
})

test_that("write_memory replaces an existing slug entry (no duplicates)", {
  .with_temp_home({
    write_memory("topic", "first version", "d1")
    write_memory("topic", "second version", "d2")
    ms <- list_memories()
    slugs <- vapply(ms, function(m) m$slug, character(1))
    expect_equal(sum(slugs == "topic"), 1L)        # not duplicated
    expect_match(ms[[which(slugs == "topic")]]$content, "second version")
    idx_lines <- readLines(file.path(codeagent:::.memory_dir(), "MEMORY.md"))
    expect_equal(sum(grepl("\\(topic\\.md\\)", idx_lines)), 1L)
  })
})

test_that("list_memories parses slug + description + body", {
  .with_temp_home({
    write_memory("alpha", "body text here", "the desc")
    ms <- list_memories()
    expect_length(ms, 1L)
    expect_identical(ms[[1]]$slug, "alpha")
    expect_identical(ms[[1]]$description, "the desc")
    expect_match(ms[[1]]$content, "body text here")
  })
})

test_that("recall_memories returns empty string when no memories", {
  .with_temp_home({
    expect_identical(recall_memories(), "")
  })
})

test_that("recall_memories summarizes stored memories", {
  .with_temp_home({
    write_memory("beta", "remember the beta fact", "beta summary")
    r <- recall_memories()
    expect_match(r, "Persistent memory")
    expect_match(r, "beta summary")
  })
})

test_that("system-reminder injects recall on iteration 1 only", {
  .with_temp_home({
    write_memory("gamma", "gamma content", "gamma desc")
    sr1 <- codeagent:::.build_system_reminder(list(), iteration = 1L, cwd = getwd())
    sr2 <- codeagent:::.build_system_reminder(list(), iteration = 2L, cwd = getwd())
    expect_match(sr1, "Persistent memory")
    expect_false(grepl("Persistent memory", sr2))
  })
})

test_that("remember tool writes a memory and returns a typed result", {
  .with_temp_home({
    t <- remember_tool()
    expect_identical(t@name, "remember")
    res <- t(title = "delta", content = "delta fact", description = "d")
    expect_true(S7::S7_inherits(res, ellmer::ContentToolResult))
    expect_length(list_memories(), 1L)
  })
})

test_that("delete_memory removes a memory file", {
  .with_temp_home({
    write_memory("epsilon", "x", "y")
    expect_length(list_memories(), 1L)
    delete_memory("epsilon")
    expect_length(list_memories(), 0L)
  })
})
