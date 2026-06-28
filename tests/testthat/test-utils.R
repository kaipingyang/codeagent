test_that(".simple_hash returns consistent 8-char hex strings", {
  expect_equal(codeagent:::.simple_hash("hello"), codeagent:::.simple_hash("hello"))
  expect_false(identical(codeagent:::.simple_hash("hello"),
                         codeagent:::.simple_hash("world")))
  h <- codeagent:::.simple_hash("some path/to/project")
  expect_equal(nchar(h), 8L)
  expect_true(grepl("^[0-9a-f]{8}$", h))
  # Empty string should not error
  expect_no_error(codeagent:::.simple_hash(""))
})

test_that(".generate_uuid_v4 produces RFC 4122 v4 UUIDs", {
  uuids <- replicate(200L, codeagent:::.generate_uuid_v4())
  # Format: 8-4-4-4-12 hex groups
  expect_true(all(grepl(
    "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    uuids
  )))
  # Version nibble must be '4'
  expect_true(all(substr(uuids, 15L, 15L) == "4"))
  # Variant bits: char 20 must be 8, 9, a, or b
  expect_true(all(substr(uuids, 20L, 20L) %in% c("8", "9", "a", "b")))
  # UUIDs should be (practically) unique
  expect_equal(length(unique(uuids)), 200L)
})

test_that(".validate_uuid accepts valid UUIDs and rejects invalid ones", {
  valid <- "550e8400-e29b-41d4-a716-446655440000"
  expect_equal(codeagent:::.validate_uuid(valid), valid)
  expect_null(codeagent:::.validate_uuid("not-a-uuid"))
  expect_null(codeagent:::.validate_uuid(""))
  expect_null(codeagent:::.validate_uuid(NULL))
  expect_null(codeagent:::.validate_uuid(123L))
  # Too short
  expect_null(codeagent:::.validate_uuid("550e8400-e29b-41d4-a716"))
})

test_that("truncate_tool_result truncates at per-tool limits", {
  long_text <- paste(rep("a", 40000L), collapse = "")
  result <- truncate_tool_result(long_text, "Bash")
  expect_lt(nchar(result), 40001L)
  expect_true(grepl("truncated", result))

  # Short text passes through unchanged
  short <- "hello"
  expect_equal(truncate_tool_result(short, "Bash"), short)

  # Unknown tool uses default limit
  long_default <- paste(rep("b", 15000L), collapse = "")
  result_default <- truncate_tool_result(long_default, "UnknownTool")
  expect_true(grepl("truncated", result_default))
})

test_that("truncate_tool_result: WebSearch has its own limit (not falling back to default)", {
  # Bug fix: web_search_tool was using "WebFetch" as the key, meaning a
  # web-search-specific limit was never checked. "WebSearch" is now in
  # .TOOL_MAX_CHARS with a 20K limit (same as WebFetch).
  long_text <- paste(rep("w", 25000L), collapse = "")
  # WebSearch limit = 20000L, so 25K chars should be truncated
  result_ws <- truncate_tool_result(long_text, "WebSearch")
  expect_true(grepl("truncated", result_ws))
  # default limit = 10000L, so same text would also be truncated there
  result_def <- truncate_tool_result(long_text, "default")
  expect_true(grepl("truncated", result_def))
  # WebSearch allows more chars than the default limit
  medium_text <- paste(rep("w", 12000L), collapse = "")
  # 12K > default (10K): truncated with default, but NOT with WebSearch (20K)
  expect_true(grepl("truncated", truncate_tool_result(medium_text, "default")))
  expect_false(grepl("truncated", truncate_tool_result(medium_text, "WebSearch")))
})

test_that("estimate_tokens_text returns reasonable estimates", {
  # 350 chars => ~100 tokens at char/3.5
  text <- paste(rep("x", 350L), collapse = "")
  est  <- estimate_tokens_text(text)
  expect_equal(est, 100L)
  # Empty string
  expect_equal(estimate_tokens_text(""), 0L)
  # Character vector
  expect_gt(estimate_tokens_text(c("hello", "world")), 0L)
})

test_that(".safe_get_turns returns list() when chat$get_turns() errors", {
  # Create a minimal fake chat that errors on get_turns
  fake_chat <- list(get_turns = function() stop("cannot get turns"))
  result <- codeagent:::.safe_get_turns(fake_chat)
  expect_equal(result, list())
})

test_that(".safe_normalize_path returns error for non-existent file", {
  r <- codeagent:::.safe_normalize_path("/nonexistent/path/file.R")
  expect_true(!is.null(r$error))
  expect_true(grepl("File not found", r$error))
})

test_that(".safe_normalize_path returns path for existing file", {
  tmp <- tempfile(fileext = ".R")
  writeLines("1 + 1", tmp)
  on.exit(unlink(tmp))
  r <- codeagent:::.safe_normalize_path(tmp)
  expect_null(r$error)
  expect_true(file.exists(r$path))
})
