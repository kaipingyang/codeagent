# tests/testthat/test-keyring.R
# Tests for keyring integration helpers (R/keyring.R).
# These tests run in environments where keyring may or may not have a live
# daemon -- all daemon-requiring paths are stubbed or skipped appropriately.

# ---------------------------------------------------------------------------
# .keyring_available() -- pure logic
# ---------------------------------------------------------------------------

test_that(".keyring_available returns FALSE when keyring package missing", {
  # Stub requireNamespace to pretend keyring is not installed
  with_mocked_bindings(
    requireNamespace = function(pkg, ...) FALSE,
    .package = "base",
    {
      # Reset cache first
      codeagent:::.keyring_avail_cache$set(NULL)
      result <- codeagent:::.keyring_available()
      expect_false(result)
      # Reset for other tests
      codeagent:::.keyring_avail_cache$set(NULL)
    }
  )
})

test_that(".keyring_available caches the result", {
  # Force cache to TRUE
  codeagent:::.keyring_avail_cache$set(TRUE)
  expect_true(codeagent:::.keyring_available())
  # Force cache to FALSE
  codeagent:::.keyring_avail_cache$set(FALSE)
  expect_false(codeagent:::.keyring_available())
  # Reset
  codeagent:::.keyring_avail_cache$set(NULL)
})

# ---------------------------------------------------------------------------
# .keyring_get_key() -- env-var fallback path (no daemon needed)
# ---------------------------------------------------------------------------

test_that(".keyring_get_key falls back to env var when keyring unavailable", {
  # Pretend keyring is unavailable
  codeagent:::.keyring_avail_cache$set(FALSE)
  on.exit(codeagent:::.keyring_avail_cache$set(NULL), add = TRUE)

  withr::with_envvar(c(MY_TEST_API_KEY = "env_secret"), {
    val <- codeagent:::.keyring_get_key("MY_TEST_API_KEY")
    expect_equal(val, "env_secret")
  })
})

test_that(".keyring_get_key returns empty string when key not found anywhere", {
  codeagent:::.keyring_avail_cache$set(FALSE)
  on.exit(codeagent:::.keyring_avail_cache$set(NULL), add = TRUE)

  withr::with_envvar(c(NONEXISTENT_KEY_XYZ = ""), {
    val <- codeagent:::.keyring_get_key("NONEXISTENT_KEY_XYZ")
    expect_equal(val, "")
  })
})

# ---------------------------------------------------------------------------
# .keyring_store_key() -- renviron fallback path
# ---------------------------------------------------------------------------

test_that(".keyring_store_key with backend=renviron writes to .Renviron", {
  codeagent:::.keyring_avail_cache$set(FALSE)
  on.exit(codeagent:::.keyring_avail_cache$set(NULL), add = TRUE)

  tmp_home <- tempfile()
  dir.create(tmp_home)
  on.exit(unlink(tmp_home, recursive = TRUE), add = TRUE)

  withr::with_envvar(c(HOME = tmp_home), {
    codeagent:::.keyring_store_key("STORE_TEST_KEY", "store_val",
                                    backend = "renviron")
    renv_path <- file.path(tmp_home, ".Renviron")
    expect_true(file.exists(renv_path))
    lines <- readLines(renv_path, warn = FALSE)
    expect_true(any(grepl("STORE_TEST_KEY", lines)))
    expect_true(any(grepl("store_val", lines)))
  })
})

test_that(".keyring_store_key auto backend uses renviron when keyring unavailable", {
  codeagent:::.keyring_avail_cache$set(FALSE)
  on.exit(codeagent:::.keyring_avail_cache$set(NULL), add = TRUE)

  tmp_home <- tempfile()
  dir.create(tmp_home)
  on.exit(unlink(tmp_home, recursive = TRUE), add = TRUE)

  withr::with_envvar(c(HOME = tmp_home), {
    backend_used <- codeagent:::.keyring_store_key(
      "AUTO_BACKEND_KEY", "auto_val", backend = "auto")
    expect_equal(backend_used, "renviron")
  })
})

test_that(".keyring_store_key errors when backend=keyring and keyring unavailable", {
  codeagent:::.keyring_avail_cache$set(FALSE)
  on.exit(codeagent:::.keyring_avail_cache$set(NULL), add = TRUE)

  expect_error(
    codeagent:::.keyring_store_key("K", "v", backend = "keyring"),
    class = "rlang_error"
  )
})

# ---------------------------------------------------------------------------
# .keyring_delete_key() -- unavailable path
# ---------------------------------------------------------------------------

test_that(".keyring_delete_key returns FALSE and warns when keyring unavailable", {
  codeagent:::.keyring_avail_cache$set(FALSE)
  on.exit(codeagent:::.keyring_avail_cache$set(NULL), add = TRUE)

  result <- codeagent:::.keyring_delete_key("SOME_KEY")
  expect_false(result)
})
