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
