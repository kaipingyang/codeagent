# GenUI hardening (Phase 3): property-style checks over generated inputs, and
# isolation between browser sessions. Seeds are fixed so failures reproduce.

random_words <- function(n) {
  vapply(seq_len(n), function(i) paste(
    replicate(sample(1:6, 1), paste(sample(c(letters, LETTERS, 0:9), sample(1:9, 1),
                                           replace = TRUE), collapse = "")),
    collapse = sample(c(" ", "_", "-", ".", " (", ") "), 1)), "")
}

test_that("plain text of any shape passes canvas-output validation", {
  set.seed(4201)
  for (s in random_words(300))
    expect_null(.genui_validate_strings(list(title = s)), info = s)
})

test_that("a dangerous token anywhere in a string is always caught", {
  set.seed(4202)
  tokens <- c("<script>", "<img src=x>", "</div>", "<!--", "javascript:",
              "JAVASCRIPT :", "data:", "vbscript:", "file:", "blob:",
              "http://", "https://", "HTTPS://", "ftp://", "wss://", "www.",
              intToUtf8(1L), intToUtf8(27L), intToUtf8(127L))
  base <- random_words(200)
  for (i in seq_along(base)) {
    tok <- sample(tokens, 1)
    at <- sample(0:nchar(base[[i]]), 1)
    s <- paste0(substr(base[[i]], 1, at), " ", tok, substr(base[[i]], at + 1, 1e4))
    # Hide it at a random depth of a nested argument list, too.
    arg <- if (runif(1) < 0.5) list(title = s) else list(a = list(b = c("ok", s)))
    expect_match(.genui_validate_strings(arg), "Canvas text", info = s)
  }
})

test_that("quota rejects exactly the calls that exceed a limit", {
  set.seed(4203)
  lim <- .GENUI_LIMITS
  for (i in 1:200) {
    n_items <- sample(0:(lim$array_items + 20), 1)
    len <- sample(0:(lim$string_chars + 200), 1)
    args <- list(columns = as.list(rep("x", n_items)), title = strrep("a", len))
    bytes <- nchar(jsonlite::toJSON(args, auto_unbox = TRUE), type = "bytes")
    expected <- n_items > lim$array_items || len > lim$string_chars ||
      bytes > lim$arg_bytes
    got <- !is.null(.genui_quota_check("create", args, 0L, 0L, 0L))
    expect_identical(got, expected, info = sprintf("items=%d chars=%d", n_items, len))
  }
})

test_that("random call sequences keep the canvas, the registry and the trace aligned", {
  skip_if_no_genui()
  set.seed(4204)
  h <- genui_test_adapter()
  cols <- c("mpg", "hp", "wt", "qsec", "nope")
  for (i in 1:60) {
    if (i %% 5 == 0) h$adapter$begin_turn()
    live <- names(h$adapter$state()$instances)
    id <- if (length(live) && runif(1) < 0.8) sample(live, 1) else "c999"
    switch(sample(c("create", "create", "update", "remove", "clear", "fail"), 1),
      create = h$adapter$call("canvas_histogram",
                              list(dataset = "cars", column = sample(cols, 1))),
      update = h$adapter$call("canvas_update", list(
        id = id, args = sprintf('{"column": "%s"}', sample(cols, 1)))),
      remove = h$adapter$call("canvas_remove", list(id = id)),
      clear  = h$adapter$call("canvas_clear", list()),
      fail   = {
        h$ops$fail_server <- function(module_id, args) TRUE
        h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
        h$ops$fail_server <- NULL
      })
    live <- names(h$adapter$state()$instances)
    expect_setequal(h$ops$dom, if (length(live)) .genui_shell_id(live) else character())
    folded <- .genui_fold_trace(h$adapter$catalog(), h$adapter$snapshot()$trace,
                                function(n) .genui_resolve_dataset(n, h$env))
    expect_identical(folded$instances, h$adapter$state()$instances)
  }
})

test_that("two per-session adapters never touch each other's canvas", {
  skip_if_no_genui()
  a <- genui_test_adapter()
  b <- genui_test_adapter()
  a$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  b$adapter$call("canvas_scatter_plot", list(dataset = "cars", x = "mpg", y = "hp"))
  b$adapter$call("canvas_clear", list())
  expect_identical(a$ops$dom, "ca_genui_shell_c1")
  expect_length(a$adapter$state()$instances, 1L)
  expect_identical(b$ops$dom, character())
})

test_that("a shared adapter stays poisoned for every session once shared", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$bind(session = "second", ops = h$ops$ops)
  h$adapter$bind(session = "second", ops = h$ops$ops)
  expect_true(h$adapter$poisoned())
  for (tool in c("canvas_histogram", "canvas_clear", "canvas_state"))
    expect_match(h$adapter$call(tool, list(dataset = "cars", column = "mpg"))@error,
                 "more than one browser session", info = tool)
  expect_length(h$ops$log, 0L)
})

test_that("removed components' module scopes are destroyed on every path", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  for (i in 1:3)
    h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$call("canvas_update", list(id = "c2", args = '{"column": "hp"}'))
  h$adapter$call("canvas_remove", list(id = "c1"))
  h$adapter$begin_turn()
  h$adapter$call("canvas_clear", list())
  started <- vapply(Filter(function(x) identical(x$op, "server"), h$ops$log),
                    function(x) x$module_id, "")
  # Every scope that was ever started is gone once the canvas is empty.
  expect_setequal(h$ops$scopes, started)
})
