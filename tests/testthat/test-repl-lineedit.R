# Console line editor -- .console_apply_key handles every key case.

st <- function(chars = character(0), pos = length(chars), history = character(0)) {
  list(chars = chars, pos = pos, history = history,
       hist_pos = length(history) + 1L, stash = character(0), action = NULL)
}
ak <- function(...) codeagent:::.console_apply_key(...)
buf <- function(s) paste(s$chars, collapse = "")

test_that("printable characters insert at the cursor", {
  s <- ak(st(c("a", "c"), pos = 1L), "b")   # cursor between a and c
  expect_equal(buf(s), "abc")
  expect_equal(s$pos, 2L)
})

test_that("arrow keys move the cursor and are NOT inserted as text", {
  s <- ak(st(c("a", "b", "c"), pos = 3L), "left")
  expect_equal(s$pos, 2L)
  expect_equal(buf(s), "abc")                # no "[[D" leaked
  s <- ak(s, "right"); expect_equal(s$pos, 3L)
  s <- ak(s, "right"); expect_equal(s$pos, 3L)   # clamped at end
  s <- ak(st(pos = 0L), "left"); expect_equal(s$pos, 0L)  # clamped at start
})

test_that("home/end and ctrl-a/ctrl-e jump to line edges", {
  expect_equal(ak(st(c("a","b","c"), 3L), "home")$pos, 0L)
  expect_equal(ak(st(c("a","b","c"), 0L), "end")$pos, 3L)
  expect_equal(ak(st(c("a","b","c"), 3L), "ctrl-a")$pos, 0L)
  expect_equal(ak(st(c("a","b","c"), 0L), "ctrl-e")$pos, 3L)
})

test_that("backspace deletes before the cursor; delete deletes at the cursor", {
  s <- ak(st(c("a","b","c"), 3L), "backspace")
  expect_equal(buf(s), "ab"); expect_equal(s$pos, 2L)
  expect_equal(buf(ak(st(character(0), 0L), "backspace")), "")   # no-op at start
  s <- ak(st(c("a","b","c"), 0L), "delete")
  expect_equal(buf(s), "bc"); expect_equal(s$pos, 0L)
  expect_equal(buf(ak(st(c("a","b","c"), 3L), "delete")), "abc") # no-op at end
})

test_that("ctrl-u kills to start, ctrl-k kills to end", {
  expect_equal(buf(ak(st(c("a","b","c","d"), 2L), "ctrl-u")), "cd")
  expect_equal(buf(ak(st(c("a","b","c","d"), 2L), "ctrl-k")), "ab")
})

test_that("enter submits, ctrl-c cancels, ctrl-d EOFs only on empty line", {
  expect_equal(ak(st(c("h","i"), 2L), "enter")$action, "submit")
  expect_equal(ak(st(c("h","i"), 2L), "ctrl-c")$action, "cancel")
  expect_equal(ak(st(character(0), 0L), "ctrl-d")$action, "eof")
  expect_null(ak(st(c("h","i"), 2L), "ctrl-d")$action)   # non-empty -> no EOF
})

test_that("up/down navigate history and restore the in-progress line", {
  s <- st(c("n","e","w"), 3L, history = c("first", "second"))
  s <- ak(s, "up");   expect_equal(buf(s), "second")
  s <- ak(s, "up");   expect_equal(buf(s), "first")
  s <- ak(s, "up");   expect_equal(buf(s), "first")     # clamped at oldest
  s <- ak(s, "down"); expect_equal(buf(s), "second")
  s <- ak(s, "down"); expect_equal(buf(s), "new")       # restores stash
})

test_that("unsupported special keys are ignored (no garbage inserted)", {
  for (k in c("tab", "escape", "insert", "pageup", "f1", "f12", "ctrl-x")) {
    expect_equal(buf(ak(st(c("a","b"), 2L), k)), "ab", info = k)
  }
})
