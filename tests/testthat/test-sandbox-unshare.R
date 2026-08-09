# tests/testthat/test-sandbox-unshare.R
# OS-level no-network sandbox via unprivileged user+net namespace (unshare).
# The Bash tool wraps commands in `unshare -Urn` in no-network mode, so any
# connect()/socket() fails at the kernel level regardless of how the command is
# written -- a bounded syscall boundary, not a bypassable command blacklist.
# RunR keeps callr + the R network-fn blacklist for now (see 31n: unshare can't
# directly wrap callr's internal fork; two-layer unshare+callr deferred).

test_that(".sandbox_unshare_available returns a logical (cached)", {
  r1 <- codeagent:::.sandbox_unshare_available()
  r2 <- codeagent:::.sandbox_unshare_available()
  expect_type(r1, "logical")
  expect_length(r1, 1L)
  expect_identical(r1, r2)   # cached
})

test_that(".sandbox_unshare_wrap prefixes only when no_network + available", {
  argv <- c("bash", "/tmp/x.sh")
  # network allowed -> never wrap
  expect_identical(codeagent:::.sandbox_unshare_wrap(argv, no_network = FALSE), argv)
  wrapped <- codeagent:::.sandbox_unshare_wrap(argv, no_network = TRUE)
  if (codeagent:::.sandbox_unshare_available()) {
    expect_identical(wrapped[1:3], c("unshare", "-Urn", "--"))
    expect_identical(wrapped[-(1:3)], argv)
  } else {
    expect_identical(wrapped, argv)   # unavailable -> unchanged (fallback)
  }
})

test_that("Bash no-net sandbox blocks a non-blacklisted net call (syscall level)", {
  skip_if_not(codeagent:::.sandbox_unshare_available(), "unshare -Urn unavailable")
  t <- codeagent:::bash_tool("bypass", list(), NULL,
                             sandbox = list(enabled = TRUE, allow_network = FALSE))
  fn <- S7::S7_data(t)
  # /dev/tcp is NOT in .SANDBOX_NETWORK_CMDS, so it bypasses the blacklist; only
  # the unshare net namespace can stop it.
  cmd <- "exec 3<>/dev/tcp/example.com/80 2>/dev/null && echo TCP_OK || echo TCP_BLOCKED"
  r <- fn(command = cmd)
  val <- tryCatch(r@value, error = function(e) as.character(r))
  expect_true(grepl("TCP_BLOCKED", val, fixed = TRUE))
  expect_false(grepl("TCP_OK", val, fixed = TRUE))
})

test_that("Bash with network allowed runs normally (no unshare wrap)", {
  t <- codeagent:::bash_tool("bypass", list(), NULL,
                             sandbox = list(enabled = TRUE, allow_network = TRUE))
  r <- S7::S7_data(t)(command = "echo NET_ALLOWED_PATH")
  val <- tryCatch(r@value, error = function(e) as.character(r))
  expect_true(grepl("NET_ALLOWED_PATH", val, fixed = TRUE))
})

test_that("Bash blacklist still fires as the cheap first line (curl)", {
  # Even without unshare, the blacklist catches known net utilities before exec.
  t <- codeagent:::bash_tool("bypass", list(), NULL,
                             sandbox = list(enabled = TRUE, allow_network = FALSE))
  expect_error(S7::S7_data(t)(command = "curl http://example.com"),
               class = "ellmer_tool_reject")
})
