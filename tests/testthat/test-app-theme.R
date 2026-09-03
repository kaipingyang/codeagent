test_that("theme resolvers return a bs_theme for every supported input", {
  for (nm in list("default", "ios", "aurora", "flatly", "darkly", "glass",
                  "light", "dark", "glassmorphism", "GLASS",
                  "unknown-theme", NULL, NA)) {
    expect_s3_class(.resolve_app_theme(nm), "bs_theme")
    expect_s3_class(.resolve_page_chat_theme(nm), "bs_theme")
  }
})

test_that("theme vocabularies map to the expected preset", {
  bsw <- function(x) tryCatch(bslib::theme_bootswatch(.resolve_app_theme(x)),
                              error = function(e) NULL)
  expect_equal(bsw("darkly"), "darkly")
  expect_equal(bsw("dark"),   "darkly")
  expect_equal(bsw("flatly"), "flatly")
  expect_null(bsw("default"))
  expect_null(bsw("light"))
  expect_null(bsw("ios"))
  expect_null(bsw("aurora"))
  expect_null(bsw("glass"))
})

test_that("custom codeagent themes carry additional rules", {
  default <- .resolve_app_theme("default")
  for (style in c("glass", "ios", "aurora")) {
    themed <- .resolve_app_theme(style)
    expect_false(identical(
      utils::capture.output(str(themed)),
      utils::capture.output(str(default))
    ))
  }
})

test_that("classic and page_chat resolvers share shinychat's official baseline", {
  calls <- list()
  testthat::local_mocked_bindings(
    .shinychat_export = function(name) {
      expect_identical(name, "page_chat_theme")
      function(..., preset = "shiny") {
        calls[[length(calls) + 1L]] <<- list(preset = preset, dots = list(...))
        bslib::bs_theme(
          version = 5,
          preset = if (identical(preset, "shiny")) "shiny" else preset,
          ...
        )
      }
    }
  )
  expect_s3_class(codeagent:::.resolve_app_theme("default"), "bs_theme")
  expect_s3_class(codeagent:::.resolve_page_chat_theme("flatly"), "bs_theme")
  expect_identical(calls[[1L]]$preset, "shiny")
  expect_identical(calls[[2L]]$preset, "flatly")
})

test_that("ios theme exposes white cards on an iOS grouped canvas", {
  calls <- list()
  testthat::local_mocked_bindings(
    .shinychat_export = function(name) {
      function(..., preset = "shiny") {
        calls[[length(calls) + 1L]] <<- list(preset = preset, dots = list(...))
        bslib::bs_theme(version = 5, preset = "shiny", ...)
      }
    }
  )
  theme <- codeagent_theme("ios")
  expect_s3_class(theme, "bs_theme")
  expect_identical(calls[[1L]]$preset, "shiny")
  expect_identical(calls[[1L]]$dots$bg, "#ffffff")
  expect_identical(calls[[1L]]$dots$primary, "#007aff")
  expect_identical(
    calls[[1L]]$dots[["shiny-chat-page-surface-bg"]], "#f2f2f7")
  expect_identical(
    calls[[1L]]$dots[["shiny-chat-page-sidebar-bg"]], "#ffffff")
  expect_identical(
    calls[[1L]]$dots[["shiny-chat-page-canvas-bg"]], "#f2f2f7")
  expect_identical(
    calls[[1L]]$dots[["shiny-chat-page-drawer-bg"]], "#ffffff")
})

test_that("ios theme mirrors the Young Voice white-card tokens", {
  css <- .ios_theme_rules()
  expect_match(css, "--ca-card-border: rgba(0,0,0,0.08);", fixed = TRUE)
  expect_match(css, "--ca-card-radius: 14px;", fixed = TRUE)
  expect_match(
    css,
    "--ca-card-shadow: 0 2px 12px rgba(0,0,0,0.07), 0 1px 3px rgba(0,0,0,0.04);",
    fixed = TRUE
  )
  expect_match(
    css,
    "--shiny-chat-page-sidebar-bg: var(--ca-app-surface-bg);",
    fixed = TRUE
  )
  expect_match(css, ".shiny-chat-suggestion-list-item", fixed = TRUE)
})

test_that("codeagent footer keeps the shinychat composer at the bottom", {
  footer <- as.character(htmltools::tagList(.skill_picker_footer(NULL)))
  expect_match(footer, "ca-chat-footer-actions", fixed = TRUE)

  css_path <- system.file("www", "styles.css", package = "codeagent")
  if (!nzchar(css_path))
    css_path <- test_path("..", "..", "inst", "www", "styles.css")
  css <- paste(readLines(css_path, warn = FALSE), collapse = "\n")
  expect_match(css, ".ca-chat-footer-actions", fixed = TRUE)
  expect_match(css, "translate: 0 0 !important", fixed = TRUE)
})

test_that("ios theme tokens can be overridden", {
  calls <- list()
  testthat::local_mocked_bindings(
    .shinychat_export = function(name) {
      function(..., preset = "shiny") {
        dots <- rlang::dots_list(..., .homonyms = "last")
        calls[[length(calls) + 1L]] <<- list(preset = preset, dots = dots)
        do.call(bslib::bs_theme, c(list(version = 5, preset = "shiny"), dots))
      }
    }
  )
  codeagent_theme(
    "ios", primary = "#0057d9",
    `shiny-chat-page-canvas-bg` = "#ffffff")
  expect_identical(calls[[1L]]$dots$primary, "#0057d9")
  expect_identical(
    calls[[1L]]$dots[["shiny-chat-page-canvas-bg"]], "#ffffff")
})

test_that("custom bslib themes pass through unchanged", {
  custom <- shinychat::page_chat_theme(primary = "#0057d9")
  expect_identical(.resolve_app_theme(custom), custom)
  expect_identical(.resolve_page_chat_theme(custom), custom)
})

test_that("codeagent_theme is exported", {
  expect_true("codeagent_theme" %in% getNamespaceExports("codeagent"))
})


test_that("codeagent_app accepts ios and custom themes in both layouts", {
  custom <- shinychat::page_chat_theme(primary = "#0057d9")
  for (layout in c("classic", "page_chat")) {
    expect_s3_class(
      codeagent_app(theme = "ios", ui_layout = layout, launch.browser = FALSE),
      "shiny.appobj")
    expect_s3_class(
      codeagent_app(theme = custom, ui_layout = layout, launch.browser = FALSE),
      "shiny.appobj")
  }
})


test_that("aurora theme uses the shiny baseline and frosted light tokens", {
  calls <- list()
  testthat::local_mocked_bindings(
    .shinychat_export = function(name) {
      expect_identical(name, "page_chat_theme")
      function(..., preset = "shiny") {
        dots <- rlang::dots_list(..., .homonyms = "last")
        calls[[length(calls) + 1L]] <<- list(preset = preset, dots = dots)
        do.call(bslib::bs_theme, c(list(version = 5, preset = "shiny"), dots))
      }
    }
  )

  theme <- codeagent_theme("aurora")
  expect_s3_class(theme, "bs_theme")
  expect_identical(calls[[1L]]$preset, "shiny")
  expect_identical(calls[[1L]]$dots$bg, "#f2f2f7")
  expect_identical(calls[[1L]]$dots$primary, "#5856d6")
  expect_identical(
    calls[[1L]]$dots[["shiny-chat-page-canvas-bg"]], "#f2f2f7")
  expect_identical(
    calls[[1L]]$dots[["shiny-chat-page-sidebar-bg"]],
    "rgba(255,255,255,0.76)")
})

test_that("aurora theme separates ambient glass from opaque content", {
  css <- .aurora_theme_rules()
  expect_match(css, "--ca-aurora-canvas: #f2f2f7;", fixed = TRUE)
  expect_match(css, "--ca-aurora-glass: rgba(255,255,255,0.76);", fixed = TRUE)
  expect_match(css, "--ca-aurora-content: rgba(255,255,255,0.94);", fixed = TRUE)
  expect_match(css, "body, .bslib-page-fill, shiny-chat-page", fixed = TRUE)
  expect_match(css, "body > shiny-chat-page.shiny-bound-input", fixed = TRUE)
  expect_match(css, "background-image:", fixed = TRUE)
  expect_match(css, "radial-gradient", fixed = TRUE)
  expect_match(css, "backdrop-filter: blur(18px) saturate(140%);", fixed = TRUE)
  expect_match(css, ".shiny-chat-composer {", fixed = TRUE)
  expect_match(css, "border-radius: 14px;", fixed = TRUE)
  expect_match(css, ".shiny-chat-page-sidebar", fixed = TRUE)
  expect_match(css, ".shiny-chat-drawer", fixed = TRUE)
  expect_match(css, ".shiny-chat-composer", fixed = TRUE)
  expect_match(css, ".toolcard", fixed = TRUE)
  expect_match(css, "pre, code", fixed = TRUE)
  expect_match(css, "[data-bs-theme='dark']", fixed = TRUE)
  expect_match(css, "@media (prefers-reduced-transparency: reduce)", fixed = TRUE)
  expect_match(css, "@media (prefers-reduced-motion: reduce)", fixed = TRUE)
  expect_match(css, "@supports not ((backdrop-filter: blur(1px))", fixed = TRUE)
})

test_that("aurora theme tokens can be overridden", {
  calls <- list()
  testthat::local_mocked_bindings(
    .shinychat_export = function(name) {
      function(..., preset = "shiny") {
        dots <- rlang::dots_list(..., .homonyms = "last")
        calls[[length(calls) + 1L]] <<- dots
        do.call(bslib::bs_theme, c(list(version = 5, preset = "shiny"), dots))
      }
    }
  )

  codeagent_theme(
    "aurora", primary = "#4338ca",
    `shiny-chat-page-canvas-bg` = "#f8fafc")
  expect_identical(calls[[1L]]$primary, "#4338ca")
  expect_identical(
    calls[[1L]][["shiny-chat-page-canvas-bg"]], "#f8fafc")
})

test_that("codeagent_app accepts aurora in both layouts", {
  for (layout in c("classic", "page_chat")) {
    expect_s3_class(
      codeagent_app(
        theme = "aurora", ui_layout = layout, launch.browser = FALSE),
      "shiny.appobj")
  }
})


test_that("runnable examples delegate browser launch to the outer runApp", {
  for (name in c("run_theme_preview.R", "run_page_chat.R")) {
    source_path <- test_path("..", "..", "inst", "examples", name)
    installed_path <- system.file("examples", name, package = "codeagent")
    path <- if (file.exists(source_path)) source_path else installed_path
    expect_true(nzchar(path) && file.exists(path), info = name)
    script <- paste(readLines(path, warn = FALSE), collapse = "\n")

    expect_match(script, "launch.browser = FALSE", fixed = TRUE, info = name)
    expect_match(
      script,
      "launch.browser = getOption(\"shiny.launch.browser\", interactive())",
      fixed = TRUE,
      info = name
    )
    expect_match(
      script,
      "Sys.getenv(c(\"RS_SERVER_URL\", \"RS_SESSION_URL\"))",
      fixed = TRUE,
      info = name
    )
    expect_match(
      script,
      "host <- if (is_workbench) \"0.0.0.0\" else \"127.0.0.1\"",
      fixed = TRUE,
      info = name
    )
    expect_match(script, "host = host", fixed = TRUE, info = name)
  }
})
