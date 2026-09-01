test_that(".resolve_app_theme returns a bs_theme for every input (never errors)", {
  for (nm in list("default", "flatly", "darkly", "glass", "light", "dark",
                  "glassmorphism", "GLASS", "unknown-theme", NULL, NA)) {
    th <- .resolve_app_theme(nm)
    expect_s3_class(th, "bs_theme")
  }
})

test_that(".resolve_app_theme maps README + CLI vocabularies to the right preset", {
  bsw <- function(x) tryCatch(bslib::theme_bootswatch(.resolve_app_theme(x)),
                              error = function(e) NULL)
  expect_equal(bsw("darkly"), "darkly")
  expect_equal(bsw("dark"),   "darkly")   # CLI alias
  expect_equal(bsw("flatly"), "flatly")
  # default / light / glass are not bootswatch presets
  expect_null(bsw("default"))
  expect_null(bsw("light"))               # CLI alias -> default
  expect_null(bsw("glass"))               # custom rules, not a bootswatch
})

test_that("glass theme carries custom rules (distinct from default)", {
  glass   <- .resolve_app_theme("glass")
  default <- .resolve_app_theme("default")
  # The glass theme adds extra Sass layers (bg override + backdrop-filter rules),
  # so its compiled/deparsed form differs from the bare default theme.
  expect_false(identical(
    utils::capture.output(str(glass)),
    utils::capture.output(str(default))
  ))
})


test_that("page_chat themes use shinychat's official page baseline", {
  calls <- list()
  testthat::local_mocked_bindings(
    .shinychat_export = function(name) {
      expect_identical(name, "page_chat_theme")
      function(..., preset = "shiny") {
        calls[[length(calls) + 1L]] <<- list(preset = preset, dots = list(...))
        bslib::bs_theme(version = 5, bootswatch = if (preset == "shiny") NULL else preset)
      }
    }
  )
  expect_s3_class(codeagent:::.resolve_page_chat_theme("default"), "bs_theme")
  expect_s3_class(codeagent:::.resolve_page_chat_theme("flatly"), "bs_theme")
  expect_identical(calls[[1L]]$preset, "shiny")
  expect_identical(calls[[2L]]$preset, "flatly")
})
