# tests/testthat/test-hooks-watch.R
# FileChanged / ConfigChange filesystem-watch hooks (B group).

test_that("HookRegistry$has_hooks reports registration state", {
  reg <- HookRegistry$new()
  expect_false(reg$has_hooks(HookEvent$FILE_CHANGED))
  reg$register(HookEvent$FILE_CHANGED, function(fp, evt, ctx) NULL)
  expect_true(reg$has_hooks(HookEvent$FILE_CHANGED))
  expect_false(reg$has_hooks(HookEvent$CONFIG_CHANGE))
})

test_that(".config_source_for classifies settings paths", {
  f <- codeagent:::.config_source_for
  expect_identical(f("/proj/.codeagent/settings.json"), "project_settings")
  # A bare settings.json not under ~/.codeagent falls through to local.
  expect_identical(f("/somewhere/else/settings.json"), "local_settings")
  # Non-settings file -> NA (not a config change).
  expect_true(is.na(f("/proj/R/foo.R")))
})

test_that(".start_hook_watchers is a graceful no-op without hooks or listeners", {
  # NULL hooks -> NULL.
  expect_null(codeagent:::.start_hook_watchers(NULL, cwd = tempdir()))
  # A registry with no FileChanged/ConfigChange hooks -> NULL (nothing to watch).
  reg <- HookRegistry$new()
  reg$register(HookEvent$STOP, function(r, c) NULL)   # unrelated hook
  expect_null(codeagent:::.start_hook_watchers(reg, cwd = tempdir()))
})

test_that("FileChanged fires when a watched file changes (end to end)", {
  skip_on_cran()
  skip_if_not_installed("watcher")
  # inotify does not work on many networked/overlay filesystems (this repo's
  # tempdir is one). /dev/shm is a real local tmpfs where inotify is reliable;
  # skip where it is absent (e.g. macOS) rather than flake.
  skip_if(!dir.exists("/dev/shm"), "no local tmpfs for reliable inotify")

  dir <- file.path("/dev/shm", sprintf("cahw-%d", Sys.getpid()))
  dir.create(dir, showWarnings = FALSE)
  withr::defer(unlink(dir, recursive = TRUE))

  reg <- HookRegistry$new()
  fired <- new.env(parent = emptyenv()); fired$paths <- character(0)
  reg$register(HookEvent$FILE_CHANGED, function(fp, evt, ctx) {
    fired$paths <- c(fired$paths, fp)
    fired$evt   <- evt
  })

  handle <- codeagent:::.start_hook_watchers(reg, cwd = dir, latency = 0.1)
  skip_if(is.null(handle), "watcher could not start on this platform")
  withr::defer(handle$stop())
  Sys.sleep(0.3)   # let the monitor register before mutating

  # Trigger a change, then pump `later` until the callback lands (bounded wait).
  target <- file.path(dir, "changed.txt")
  writeLines("hello", target)

  ok <- FALSE
  deadline <- Sys.time() + 8   # generous: inotify + latency debounce
  while (!ok && Sys.time() < deadline) {
    later::run_now(0.2)
    Sys.sleep(0.05)
    if (length(fired$paths) > 0L) ok <- TRUE
  }

  expect_true(ok)
  expect_true(any(grepl("changed\\.txt$", fired$paths)))
  expect_identical(fired$evt, "change")   # watcher does not distinguish add/unlink
})
