# R CMD check's "checking running R code from vignettes" tangles every vignette
# with knitr::purl() and sources the result. Our vignette chunks are
# documentation, not runnable examples: they are set eval = FALSE, and several
# need credentials (CODEAGENT_BASE_URL) or an attached package that the tangled
# script never loads. chunk-level `eval = FALSE` does NOT stop purl -- only
# `purl = FALSE` does -- so a chunk missing it becomes a check ERROR the moment
# its code cannot run standalone.

.vignette_dir <- function() {
  for (p in c(testthat::test_path("..", "..", "vignettes"), "vignettes")) {
    if (dir.exists(p)) return(p)
  }
  NULL
}

test_that("every vignette chunk opts out of purl", {
  dir <- .vignette_dir()
  if (is.null(dir)) skip("vignettes/ is not available (installed package)")
  offenders <- character()
  for (f in list.files(dir, pattern = "\\.Rmd$", full.names = TRUE)) {
    lines   <- readLines(f, warn = FALSE)
    headers <- grep("^```\\{r", lines)
    bad     <- headers[!grepl("purl\\s*=\\s*FALSE", lines[headers])]
    if (length(bad))
      offenders <- c(offenders, sprintf("%s:%s", basename(f),
                                        paste(bad, collapse = ",")))
  }
  expect_identical(offenders, character(0),
                   info = paste("chunks missing purl = FALSE:\n",
                                paste(offenders, collapse = "\n")))
})

test_that("no vignette tangles to executable code", {
  dir <- .vignette_dir()
  if (is.null(dir)) skip("vignettes/ is not available (installed package)")
  skip_if_not_installed("knitr")
  offenders <- character()
  for (f in list.files(dir, pattern = "\\.Rmd$", full.names = TRUE)) {
    out <- tempfile(fileext = ".R")
    on.exit(unlink(out), add = TRUE)
    suppressWarnings(knitr::purl(f, output = out, quiet = TRUE))
    lines <- readLines(out, warn = FALSE)
    code  <- lines[nzchar(trimws(lines)) & !grepl("^\\s*#", lines)]
    if (length(code))
      offenders <- c(offenders, sprintf("%s (%d lines)", basename(f), length(code)))
  }
  expect_identical(offenders, character(0),
                   info = paste("vignettes that tangle to runnable code:\n",
                                paste(offenders, collapse = "\n")))
})
