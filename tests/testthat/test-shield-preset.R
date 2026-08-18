# shield_preset_strict/balanced/clinical() -- callable versions of the three
# vignette "ready-to-use combination templates". These tests lock the exact
# strategy composition documented in vignettes/data-shield.Rmd /
# data-shield-cn.Rmd so the presets and the docs cannot silently drift apart.
#
# .new_shield_strategy() stores fields under $config, not at the top level
# (only $type is top-level). shield_regex()/shield_ingress() bake `on_fail`
# into the closure `$config$fn` rather than exposing it as a readable field,
# so those two are verified behaviorally by invoking the closure against a
# known-triggering string instead of inspecting config directly.

test_that("shield_preset_strict() matches the documented strict template", {
  strict <- shield_preset_strict()
  expect_true(is.list(strict))
  expect_length(strict, 4L)

  types <- vapply(strict, `[[`, character(1), "type")
  expect_equal(types, c("describe", "egress", "scanner", "ingress"))

  describe <- strict[[1L]]$config
  expect_equal(describe$k_anon, 5L)

  egress <- strict[[2L]]$config
  expect_equal(egress$detectors, c("row_cap", "value_match"))
  expect_equal(egress$max_rows, 0L)
  expect_equal(egress$on_fail, "block")

  regex_fn <- strict[[3L]]$config$fn
  res <- regex_fn("token: sk-ABCDEFGHIJKLMNOPQRST", list())
  expect_equal(res$action, "block")

  ingress_fn <- strict[[4L]]$config$fn
  res <- ingress_fn("saveRDS(df, \"out.rds\")", list())
  expect_equal(res$action, "block")
})

test_that("shield_preset_balanced() matches the documented balanced template", {
  balanced <- shield_preset_balanced()
  expect_length(balanced, 2L)

  types <- vapply(balanced, `[[`, character(1), "type")
  expect_equal(types, c("egress", "scanner"))

  egress <- balanced[[1L]]$config
  expect_equal(egress$max_rows, 0L)
  expect_equal(egress$on_fail, "redact")

  regex_fn <- balanced[[2L]]$config$fn
  res <- regex_fn("token: sk-ABCDEFGHIJKLMNOPQRST", list())
  expect_equal(res$action, "redact")
})

test_that("shield_preset_clinical() matches the documented clinical template", {
  clinical <- shield_preset_clinical()
  expect_length(clinical, 5L)

  types <- vapply(clinical, `[[`, character(1), "type")
  expect_equal(types, c("describe", "egress", "scanner", "ingress", "reviewer"))

  describe <- clinical[[1L]]$config
  expect_equal(describe$k_anon, 5L)

  egress <- clinical[[2L]]$config
  expect_equal(egress$on_fail, "redact")   # default, unlike strict's "block"

  ingress_fn <- clinical[[4L]]$config$fn
  res <- ingress_fn("saveRDS(df, \"out.rds\")", list())
  expect_equal(res$action, "ask")

  reviewer <- clinical[[5L]]$config
  expect_equal(reviewer$on_risk, "ask")
})

test_that("all three presets construct a usable DataShield instance", {
  for (preset_fn in list(shield_preset_strict, shield_preset_balanced,
                        shield_preset_clinical)) {
    strategies <- preset_fn()
    # shield_reviewer() in the clinical preset needs no live client until a
    # review actually runs, so construction alone must not require network.
    shield <- DataShield$new(strategies = strategies)
    expect_s3_class(shield, "DataShield")
  }
})

test_that("presets can be passed directly as codeagent_client(data_shield=)", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "https://example.invalid", model = "gpt-4.1",
    credentials = function() "unused", echo = "none")
  # register_tools = FALSE (the harness-only / lazy-init path) intentionally
  # defers shield$install(chat) to the caller -- see query.R's "Harness-only
  # hosts attach tools then call client$data_shield$install(chat)" comment.
  # Verify the resolved DataShield engine is attached on the client itself
  # (the install-independent contract) rather than the chat attribute.
  client <- codeagent_client(chat, data_shield = shield_preset_balanced(),
                            register_tools = FALSE)
  expect_s3_class(client$data_shield, "DataShield")

  client$data_shield$install(client$chat)
  expect_true(!is.null(attr(client$chat, "codeagent_data_shield")))
})
