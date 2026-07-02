# tests/testthat/test-setup.R

# ---------------------------------------------------------------------------
# .detect_available_providers
# ---------------------------------------------------------------------------

test_that(".detect_available_providers returns only providers with keys set", {
  withr::with_envvar(c(
    CODEAGENT_BASE_URL = "https://x.example.com",
    ANTHROPIC_API_KEY  = "",
    OPENAI_API_KEY     = "",
    GOOGLE_API_KEY     = "",
    DEEPSEEK_API_KEY   = "",
    GROQ_API_KEY       = "",
    GITHUB_PAT         = ""
  ), {
    detected <- codeagent:::.detect_available_providers()
    names_det <- vapply(detected, `[[`, character(1), "name")
    # CODEAGENT_BASE_URL set -> openai_compatible should be detected
    expect_true("openai_compatible" %in% names_det)
    # anthropic key not set -> should not be detected
    expect_false("anthropic" %in% names_det)
  })
})

test_that(".detect_available_providers detects anthropic when key present", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-test", CODEAGENT_BASE_URL = ""), {
    detected <- codeagent:::.detect_available_providers()
    names_det <- vapply(detected, `[[`, character(1), "name")
    expect_true("anthropic" %in% names_det)
  })
})

test_that(".detect_available_providers always includes ollama (no key needed)", {
  withr::with_envvar(c(
    CODEAGENT_BASE_URL = "", ANTHROPIC_API_KEY = "", OPENAI_API_KEY = ""
  ), {
    detected <- codeagent:::.detect_available_providers()
    names_det <- vapply(detected, `[[`, character(1), "name")
    expect_true("ollama" %in% names_det)
  })
})

# ---------------------------------------------------------------------------
# .append_renviron
# ---------------------------------------------------------------------------

test_that(".append_renviron writes key=value to a new .Renviron", {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  # Point HOME so .append_renviron writes to our temp file
  withr::with_envvar(c(HOME = dirname(tmp)), {
    # rename temp to ~/.Renviron path
    renv_path <- file.path(dirname(tmp), ".Renviron")
    on.exit(unlink(renv_path), add = TRUE)
    codeagent:::.append_renviron("MY_TEST_KEY", "my_secret_value")
    lines <- readLines(renv_path, warn = FALSE)
    expect_true(any(grepl("MY_TEST_KEY", lines)))
    expect_true(any(grepl("my_secret_value", lines)))
  })
})

test_that(".append_renviron does not overwrite existing key", {
  tmp_home <- tempfile()
  dir.create(tmp_home)
  on.exit(unlink(tmp_home, recursive = TRUE), add = TRUE)
  renv_path <- file.path(tmp_home, ".Renviron")
  writeLines('EXISTING_KEY="original"', renv_path)

  withr::with_envvar(c(HOME = tmp_home), {
    expect_warning(
      codeagent:::.append_renviron("EXISTING_KEY", "new_value"),
      regexp = NA   # cli_alert_warning -- not a warning in R sense, just message
    )
    # file unchanged
    lines <- readLines(renv_path, warn = FALSE)
    expect_true(any(grepl("original", lines)))
    expect_false(any(grepl("new_value", lines)))
  })
})

test_that(".append_renviron is idempotent for new keys", {
  tmp_home <- tempfile()
  dir.create(tmp_home)
  on.exit(unlink(tmp_home, recursive = TRUE), add = TRUE)

  withr::with_envvar(c(HOME = tmp_home), {
    renv_path <- file.path(tmp_home, ".Renviron")
    codeagent:::.append_renviron("IDEM_KEY", "val1")
    n1 <- length(readLines(renv_path, warn = FALSE))
    # Second call: key exists -> should NOT add a duplicate
    suppressMessages(codeagent:::.append_renviron("IDEM_KEY", "val2"))
    n2 <- length(readLines(renv_path, warn = FALSE))
    expect_equal(n1, n2)   # no new line added
  })
})

# ---------------------------------------------------------------------------
# use_codeagent_setup -- non-interactive guard
# ---------------------------------------------------------------------------

test_that("use_codeagent_setup aborts in non-interactive sessions", {
  expect_error(use_codeagent_setup(), class = "rlang_error")
})
