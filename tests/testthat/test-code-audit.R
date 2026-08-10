# tests/testthat/test-code-audit.R
# 31w step 1: .audit_r_code_refs -- deterministic, LLM-free, filesystem-free
# static extraction of external-file references from R code. Parses (never
# evaluates) untrusted code; reports literal source/load paths (threat A) and
# flags dynamic primitives a static pass can't resolve (threat B).

test_that("extracts a literal source() path", {
  r <- codeagent:::.audit_r_code_refs('source("/x/evil.R")')
  expect_identical(r$static_paths, "/x/evil.R")
  expect_false(r$dynamic)
  expect_identical(r$source_calls, "source")
})

test_that("extracts multiple load/readRDS literal paths", {
  r <- codeagent:::.audit_r_code_refs('load("d.rds"); readRDS("e.rds")')
  expect_setequal(r$static_paths, c("d.rds", "e.rds"))
  expect_false(r$dynamic)
})

test_that("source(var) with no literal path is flagged dynamic", {
  r <- codeagent:::.audit_r_code_refs('p <- x; source(p)')
  expect_length(r$static_paths, 0L)
  expect_true(r$dynamic)
})

test_that("eval(parse()) is flagged dynamic", {
  r <- codeagent:::.audit_r_code_refs('eval(parse(text = x))')
  expect_true(r$dynamic)
})

test_that("assignment transfer f <- source is flagged dynamic", {
  # source referenced as a bare symbol -> may be called indirectly -> dynamic
  r <- codeagent:::.audit_r_code_refs('f <- source; f("y.R")')
  expect_true(r$dynamic)
})

test_that("get() obfuscation is flagged dynamic", {
  r <- codeagent:::.audit_r_code_refs('fn <- get("system"); fn("ls")')
  expect_true(r$dynamic)
})

test_that("clean code has no refs and is not dynamic", {
  r <- codeagent:::.audit_r_code_refs('x <- mean(1:10); print(x)')
  expect_length(r$static_paths, 0L)
  expect_false(r$dynamic)
})

test_that("mixed static + dynamic: extracts the literal AND flags dynamic", {
  r <- codeagent:::.audit_r_code_refs('source("ok.R"); source(dynp)')
  expect_identical(r$static_paths, "ok.R")
  expect_true(r$dynamic)   # the source(dynp) part can't be resolved
})

test_that("unparseable code fails safe to dynamic", {
  r <- codeagent:::.audit_r_code_refs('source("unclosed')
  expect_true(r$parse_error)
  expect_true(r$dynamic)
})

test_that("empty / non-character input is a no-op", {
  expect_false(codeagent:::.audit_r_code_refs("")$dynamic)
  expect_false(codeagent:::.audit_r_code_refs(character())$dynamic)
  expect_length(codeagent:::.audit_r_code_refs("")$static_paths, 0L)
})

test_that("sourceCpp literal path is extracted", {
  r <- codeagent:::.audit_r_code_refs('Rcpp::sourceCpp("x.cpp")')
  expect_true("x.cpp" %in% r$static_paths)
})

# --- step 2: .audit_code_impl whitelist + read + degrade -------------------

test_that(".audit_code_impl reads an in-project source file (whitelist pass)", {
  root <- withr::local_tempdir()
  writeLines("x <- 1", file.path(root, "helper.R"))
  r <- codeagent:::.audit_code_impl(
    sprintf('source("%s")', file.path(root, "helper.R")),
    shield = NULL, project_root = root)
  expect_length(r$allowed, 1L)
  expect_length(r$blocked, 0L)
  expect_identical(r$risk, "none")
})

test_that(".audit_code_impl blocks a path outside the project root", {
  root <- withr::local_tempdir()
  r <- codeagent:::.audit_code_impl('source("/etc/passwd")',
                                    shield = NULL, project_root = root)
  expect_length(r$allowed, 0L)
  expect_length(r$blocked, 1L)
  expect_match(r$blocked[[1]]$reason, "outside project")
  expect_identical(r$risk, "block")
})

test_that(".audit_code_impl blocks a non-source extension inside the project", {
  root <- withr::local_tempdir()
  writeLines("blob", file.path(root, "data.bin"))
  r <- codeagent:::.audit_code_impl(
    sprintf('readRDS("%s")', file.path(root, "data.bin")),
    shield = NULL, project_root = root)
  expect_match(r$blocked[[1]]$reason, "non-source extension")
  expect_identical(r$risk, "block")
})

test_that(".audit_code_impl flags dynamic code as review", {
  root <- withr::local_tempdir()
  r <- codeagent:::.audit_code_impl('source(dynvar)', shield = NULL, project_root = root)
  expect_true(r$dynamic)
  expect_identical(r$risk, "review")
})

test_that(".audit_code_impl passes clean code (risk none)", {
  root <- withr::local_tempdir()
  r <- codeagent:::.audit_code_impl('x <- mean(1:10)', shield = NULL, project_root = root)
  expect_identical(r$risk, "none")
})

test_that(".audit_path_allowed resolves symlink escape and rejects it", {
  root <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  writeLines("secret", file.path(outside, "s.R"))
  link <- file.path(root, "link.R")
  ok <- tryCatch({ file.symlink(file.path(outside, "s.R"), link); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "symlink unsupported here")
  dec <- codeagent:::.audit_path_allowed(link, root)
  expect_false(dec$ok)   # normalizePath resolves through the symlink -> outside root
})

# --- step 3: audit_code_tool ----------------------------------------------

test_that("audit_code_tool builds a read-only AuditCode tool with a code arg", {
  t <- codeagent::audit_code_tool(shield = NULL, project_root = tempdir())
  expect_identical(t@name, "AuditCode")
  expect_true("code" %in% names(t@arguments@properties))
  expect_true(isTRUE(t@annotations$read_only_hint))
})

test_that("audit_code_tool reports block for an out-of-project source, no content echo", {
  t <- codeagent::audit_code_tool(shield = NULL, project_root = tempdir())
  r <- S7::S7_data(t)(code = 'source("/etc/passwd")')
  val <- tryCatch(r@value, error = function(e) as.character(r))
  expect_match(val, "risk: block")
  expect_match(val, "path outside project root")
  expect_false(grepl("root:", val))   # metadata only, never file contents
})

