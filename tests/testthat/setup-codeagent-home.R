# Every test run keeps sessions, tool-result caches, skill caches and memory in
# a throwaway CODEAGENT_HOME, never in the developer's own codeagent directory
# (runs without it left thousands of session directories there). A test that
# needs another value sets it locally with withr::local_envvar().
withr::local_envvar(
  CODEAGENT_HOME = withr::local_tempdir("codeagent-home-", .local_envir = testthat::teardown_env()),
  .local_envir = testthat::teardown_env())
