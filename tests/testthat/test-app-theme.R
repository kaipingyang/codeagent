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
