# The "dsh" theme (inst/themes/dsh.scss); design rules in the file header.

dsh_css <- function() {
  path <- system.file("themes", "dsh.scss", package = "codeagent")
  if (!nzchar(path)) path <- test_path("..", "..", "inst", "themes", "dsh.scss")
  readLines(path, warn = FALSE)
}

# Component rules start after the token sections (1-4).
dsh_component_css <- function() {
  css <- dsh_css()
  start <- grep("^/\\* == 5\\.", css)
  expect_length(start, 1L)
  css[start:length(css)]
}

test_that("codeagent_theme('dsh') builds on page_chat_theme and compiles", {
  theme <- codeagent_theme("dsh")
  expect_s3_class(theme, "bs_theme")
  expect_null(tryCatch(bslib::theme_bootswatch(theme), error = function(e) NULL))
  expect_no_error(bslib::bs_theme_dependencies(theme))
})

test_that("the dsh rules ship only with the dsh theme", {
  css_of <- function(style) paste(as.character(sass::sass(
    bslib::bs_bundle(codeagent_theme(style)), options = sass::sass_options(output_style = "compressed"))),
    collapse = "")
  expect_match(css_of("dsh"), "--ca-dsh-bg-base", fixed = TRUE)
  for (style in c("default", "ios", "aurora"))
    expect_false(grepl("--ca-dsh-", css_of(style), fixed = TRUE), info = style)
})

test_that("codeagent_app accepts the dsh theme in both layouts", {
  for (layout in c("classic", "page_chat"))
    expect_s3_class(codeagent_app(theme = "dsh", ui_layout = layout,
                                  launch.browser = FALSE), "shiny.appobj")
})

test_that("dsh component rules use tokens, not literal colours", {
  css <- dsh_component_css()
  css <- sub("/\\*.*?\\*/", "", css)          # one-line comments
  hits <- grep("#[0-9a-fA-F]{3,8}\\b|\\brgba?\\(|\\b(white|black)\\b", css, value = TRUE)
  hits <- hits[!grepl("box-shadow|--ca-dsh-elevation|color-mix\\(in srgb, var", hits)]
  expect_identical(hits, character())
})

test_that("dark mode only rebinds tokens", {
  css <- dsh_component_css()
  expect_false(any(grepl("data-bs-theme", css)))
})

test_that("radii come from the role scale", {
  css <- dsh_component_css()
  r <- regmatches(css, regexpr("border-radius:[^;]+", css))
  bad <- r[!grepl("var\\(--ca-dsh-radius-|\\b0\\b|50%|999px|inherit", r)]
  expect_identical(bad, character())
})

test_that("no element pairs a neutral border with an elevation shadow", {
  css <- paste(dsh_component_css(), collapse = "\n")
  blocks <- regmatches(css, gregexpr("\\{[^{}]*\\}", css))[[1]]
  both <- blocks[grepl("border[^:]*:[^;]*--ca-dsh-border-l", blocks) &
                 grepl("box-shadow:[^;]*--ca-dsh-elevation", blocks)]
  expect_identical(both, character())
})
