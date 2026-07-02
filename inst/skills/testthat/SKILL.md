---
name: testthat
description: Write testthat unit tests for R functions
argument-hint: "<function name or description>"
allowed-tools:
  - Read
  - Glob
  - Grep
  - LS
  - Edit
  - Write
  - Bash
---

Write testthat tests for R functions following TDD best practices.

Steps:
1. Read the function(s) to test — understand inputs, outputs, edge cases
2. Check `tests/testthat/` for existing test files and conventions
3. Write tests covering:
   - **Happy path**: expected inputs produce expected outputs
   - **Edge cases**: NULL, NA, empty vector, zero-length, boundary values
   - **Error conditions**: invalid input types, missing required args
   - **Type stability**: return type matches documented `@return`

Test structure:
```r
test_that("function_name does X when Y", {
  # Arrange
  input <- ...
  expected <- ...
  # Act
  result <- function_name(input)
  # Assert
  expect_equal(result, expected)
})
```

Naming conventions:
- File: `test-{file-being-tested}.R` (mirrors R/ file name)
- Test descriptions: sentence case, state what the function does

Coverage target: 80%+ line coverage. Use `covr::function_coverage()` to check.

Do NOT:
- Mock internal functions unless unavoidable
- Write tests that require network access (use `skip_if_offline()`)
- Modify global state without `withr::with_*` cleanup
