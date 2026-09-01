# Public, UI-neutral tool artifact contract.

library(ellmer)

test_that("tool_result creates a versioned UI-neutral artifact", {
  result <- tool_result(
    value = "2 rows",
    kind = "table",
    title = "Query result",
    payload = list(columns = c("id", "value"), rows = 2L)
  )

  artifact <- tool_result_artifact(result)
  expect_s3_class(artifact, "codeagent_tool_artifact")
  expect_named(
    artifact,
    c("schema", "version", "kind", "status", "icon", "title", "payload")
  )
  expect_identical(artifact$schema, "codeagent.tool-artifact")
  expect_identical(artifact$version, 1L)
  expect_identical(artifact$kind, "table")
  expect_identical(artifact$payload$rows, 2L)
  expect_identical(tool_result_value(result), "2 rows")
  expect_s3_class(result@extra$display, "shinychat_tool_result_display")
})

test_that("artifact accessors support stream events without shinychat", {
  artifact <- structure(
    list(
      schema = "codeagent.tool-artifact",
      version = 1L,
      kind = "code",
      status = "success",
      icon = NULL,
      title = "Code",
      payload = list(text = "x <- 1")
    ),
    class = c("codeagent_tool_artifact", "list")
  )
  event <- list(value = "x <- 1", artifact = artifact, display = NULL)

  expect_identical(tool_result_artifact(event), artifact)
  expect_identical(tool_result_value(event), "x <- 1")
  expect_identical(tool_result_value("plain fallback"), "plain fallback")
})

test_that("unsupported artifact versions fail to the value channel", {
  future <- list(
    schema = "codeagent.tool-artifact",
    version = 99L,
    kind = "future",
    status = "success",
    icon = NULL,
    title = "Future",
    payload = list(new_field = TRUE)
  )
  event <- list(value = "portable fallback", artifact = future)

  expect_null(tool_result_artifact(event))
  expect_identical(tool_result_artifact(event, version = NULL), future)
  expect_identical(tool_result_value(event), "portable fallback")
})

test_that("legacy unversioned artifacts upgrade on display adaptation", {
  legacy <- ContentToolResult(
    value = "legacy value",
    extra = list(codeagent = list(artifact = list(
      kind = "text", status = "success", icon = NULL,
      title = "Legacy", payload = list(text = "legacy value")
    )))
  )

  adapted <- codeagent:::.adapt_tool_result(legacy)
  artifact <- tool_result_artifact(adapted)
  expect_identical(artifact$schema, "codeagent.tool-artifact")
  expect_identical(artifact$version, 1L)
  expect_identical(tool_result_value(adapted), "legacy value")
})

test_that(".tool_result2 remains a compatibility forwarder", {
  old <- codeagent:::.tool_result2(
    "legacy caller", kind = "text", payload = list(text = "legacy caller"))
  current <- codeagent:::.artifact_tool_result(
    "legacy caller", kind = "text", payload = list(text = "legacy caller"))

  expect_identical(tool_result_artifact(old), tool_result_artifact(current))
  expect_identical(tool_result_value(old), tool_result_value(current))
})


test_that("future artifact versions are transported unchanged", {
  future <- list(
    schema = "codeagent.tool-artifact",
    version = 2L,
    kind = "future-kind",
    status = "success",
    icon = NULL,
    title = "Future",
    payload = list(extension = "kept")
  )
  result <- ContentToolResult(
    value = "future fallback",
    extra = list(codeagent = list(artifact = future)))

  adapted <- codeagent:::.adapt_tool_result(result)
  expect_identical(tool_result_artifact(adapted, version = NULL), future)
  expect_null(tool_result_artifact(adapted))
  expect_identical(tool_result_value(adapted), "future fallback")
})


test_that("plain display titles are escaped while trusted HTML stays explicit", {
  unsafe <- tool_result(
    "value", title = "<img src=x onerror=alert(1)>",
    payload = list(text = "value"))
  rendered <- as.character(unsafe@extra$display$title)
  expect_false(grepl("<img", rendered, fixed = TRUE))
  expect_match(rendered, "&lt;img", fixed = TRUE)

  trusted <- codeagent:::.artifact_tool_result(
    "value", title = htmltools::HTML("<strong>Trusted</strong>"),
    payload = list(text = "value"))
  expect_match(as.character(trusted@extra$display$title),
               "<strong>Trusted</strong>", fixed = TRUE)
})

test_that("adapter preserves errors and unrelated extra metadata", {
  req <- ContentToolRequest(id = "error-1", name = "Fixture", arguments = list())
  raw <- ContentToolResult(
    value = "denied", error = "permission denied", request = req,
    extra = list(custom = list(trace_id = "trace-1")))

  adapted <- codeagent:::.adapt_tool_result(raw)
  artifact <- tool_result_artifact(adapted)
  expect_identical(artifact$kind, "error")
  expect_identical(artifact$status, "error")
  expect_identical(adapted@error, "permission denied")
  expect_identical(adapted@extra$custom$trace_id, "trace-1")
  expect_identical(adapted@request@id, "error-1")
})

test_that("artifact versions must be finite positive whole numbers", {
  base <- list(
    schema = "codeagent.tool-artifact", version = 1L,
    kind = "text", status = "success", icon = NULL, title = "x",
    payload = list(text = "x"))
  for (bad in c(1.5, Inf, NaN, 0, -1)) {
    candidate <- base
    candidate$version <- bad
    expect_null(tool_result_artifact(candidate, version = NULL))
  }
  expect_error(tool_result_artifact(base, version = 1.5), "whole")
  expect_error(tool_result_artifact(base, version = 0), "positive")
})

test_that("legacy and web direct producers originate artifact v1", {
  legacy <- codeagent:::.tool_result("legacy", title = "Legacy")
  web <- codeagent:::.web_tool_result(
    "web value", "Web result", "**web value**", sources = list())

  expect_identical(tool_result_artifact(legacy)$version, 1L)
  expect_identical(tool_result_artifact(web)$version, 1L)
  expect_identical(tool_result_value(legacy), "legacy")
  expect_identical(tool_result_value(web), "web value")
})


test_that("malformed artifact metadata degrades to a valid value-backed artifact", {
  malformed <- list("atomic", 42L, TRUE)
  for (value in malformed) {
    raw <- ContentToolResult(
      value = "portable value",
      extra = list(codeagent = list(artifact = value)))
    adapted <- expect_no_error(codeagent:::.adapt_tool_result(raw))
    expect_identical(tool_result_value(adapted), "portable value")
    expect_identical(tool_result_artifact(adapted)$version, 1L)
  }

  legacy <- ContentToolResult(
    value = "legacy portable",
    extra = list(display = list(toolcard = "not-a-card")))
  adapted <- expect_no_error(codeagent:::.adapt_tool_result(legacy))
  expect_identical(tool_result_value(adapted), "legacy portable")
  expect_identical(tool_result_artifact(adapted)$version, 1L)
})

test_that("error kind always implies error status", {
  result <- codeagent:::.artifact_tool_result(
    "failed", kind = "error", payload = list(message = "failed"))
  expect_identical(tool_result_artifact(result)$status, "error")

  legacy <- ContentToolResult(
    value = "legacy error",
    extra = list(codeagent = list(artifact = list(
      kind = "error", status = "success", icon = NULL, title = "Legacy",
      payload = list(message = "legacy error")))))
  expect_identical(
    tool_result_artifact(codeagent:::.adapt_tool_result(legacy))$status,
    "error")

  versioned <- list(
    schema = "codeagent.tool-artifact", version = 1L,
    kind = "error", status = "success", icon = NULL, title = "External",
    payload = list(message = "external error"))
  external <- ContentToolResult(
    value = "external error",
    extra = list(codeagent = list(artifact = versioned)))
  expect_identical(tool_result_artifact(external)$status, "error")
  expect_identical(
    tool_result_artifact(codeagent:::.adapt_tool_result(external))$status,
    "error")
})


test_that("list-shaped malformed metadata also fails soft", {
  malformed_artifact <- list(
    kind = function() "text", status = "success", icon = NULL,
    title = "bad", payload = list(text = "x"))
  raw <- ContentToolResult(
    value = "closure fallback",
    extra = list(codeagent = list(artifact = malformed_artifact)))
  adapted <- expect_no_error(codeagent:::.adapt_tool_result(raw))
  expect_identical(tool_result_value(adapted), "closure fallback")
  expect_identical(tool_result_artifact(adapted)$version, 1L)

  malformed_card <- list(
    kind = "text", status = "success", icon = NULL,
    title = new.env(parent = emptyenv()), payload = list(text = "x"))
  legacy <- ContentToolResult(
    value = "environment fallback",
    extra = list(display = list(toolcard = malformed_card)))
  adapted_legacy <- expect_no_error(codeagent:::.adapt_tool_result(legacy))
  expect_identical(tool_result_value(adapted_legacy), "environment fallback")
  expect_identical(tool_result_artifact(adapted_legacy)$version, 1L)
})

test_that("malformed display options fall back to artifact presentation", {
  result <- tool_result(
    "value", kind = "text", title = "Result", payload = list(text = "value"))
  ex <- result@extra
  ex$display <- list(title = "Result", open_style = "not-a-style")
  result@extra <- ex

  adapted <- expect_no_error(codeagent:::.adapt_tool_result(result))
  expect_s3_class(adapted@extra$display, "shinychat_tool_result_display")
  expect_identical(tool_result_artifact(adapted)$version, 1L)
})

test_that("legacy promotion replaces malformed artifact without duplicate keys", {
  valid_legacy <- list(
    kind = "text", status = "success", icon = NULL, title = "Legacy",
    payload = list(text = "legacy"))
  raw <- ContentToolResult(
    value = "legacy",
    extra = list(
      display = list(toolcard = valid_legacy),
      codeagent = list(artifact = "malformed", sources = list("kept"))))

  adapted <- expect_no_error(codeagent:::.adapt_tool_result(raw))
  expect_identical(sum(names(adapted@extra$codeagent) == "artifact"), 1L)
  expect_identical(adapted@extra$codeagent$sources, list("kept"))
  expect_identical(tool_result_artifact(adapted)$version, 1L)
})


test_that("artifact renderers escape untrusted raw HTML payloads", {
  hostile <- "<img src=x onerror=alert(1)><script>alert(2)</script>"

  text_result <- tool_result(
    "safe fallback", kind = "text", payload = list(text = hostile))
  text_html <- as.character(render_artifact(
    tool_result_artifact(text_result), mode = "panel"))
  expect_false(grepl("<img", text_html, fixed = TRUE))
  expect_false(grepl("<script", text_html, fixed = TRUE))
  expect_match(text_html, "&lt;img", fixed = TRUE)

  fallback_html <- as.character(render_artifact(list(
    markdown = hostile, payload = list()), mode = "panel"))
  expect_false(grepl("<script", fallback_html, fixed = TRUE))
  expect_match(fallback_html, "&lt;script", fixed = TRUE)

  plain_table <- tool_result(
    "table fallback", kind = "table", payload = list(html = hostile))
  plain_html <- as.character(render_artifact(
    tool_result_artifact(plain_table), mode = "panel"))
  expect_false(grepl("<img", plain_html, fixed = TRUE))
  expect_match(plain_html, "&lt;img", fixed = TRUE)

  trusted_table <- tool_result(
    "trusted table", kind = "table",
    payload = list(html = htmltools::HTML("<strong>Trusted</strong>")))
  trusted_html <- as.character(render_artifact(
    tool_result_artifact(trusted_table), mode = "panel"))
  expect_match(trusted_html, "<strong>Trusted</strong>", fixed = TRUE)
})

test_that("provider errors override rich artifact status", {
  diff_result <- ContentToolResult(
    value = "diff --git a/a b/a\n@@ -1 +1 @@\n-old\n+new",
    error = "boom")
  diff_artifact <- tool_result_artifact(
    codeagent:::.adapt_tool_result(diff_result))
  expect_identical(diff_artifact$kind, "diff")
  expect_identical(diff_artifact$status, "error")

  image_result <- ContentToolResult(
    value = "image failed",
    error = "boom",
    extra = list(contents = list(
      ContentImageInline(type = "image/png", data = "aW1hZ2U="))))
  image_artifact <- tool_result_artifact(
    codeagent:::.adapt_tool_result(image_result))
  expect_identical(image_artifact$kind, "image")
  expect_identical(image_artifact$status, "error")

  for (kind in c("diff", "image")) {
    versioned <- tool_result(
      "rich failed", kind = kind, status = "success",
      payload = if (kind == "diff") {
        list(old = "old", new = "new", path = "a")
      } else {
        list(images = list(), output = "failed")
      })
    versioned@error <- "boom"
    adapted <- codeagent:::.adapt_tool_result(versioned)
    expect_identical(tool_result_artifact(adapted)$kind, kind)
    expect_identical(tool_result_artifact(adapted)$status, "error")
  }

  legacy <- ContentToolResult(
    value = "legacy rich failed", error = "boom",
    extra = list(display = list(toolcard = list(
      kind = "diff", status = "success", icon = NULL, title = "Legacy diff",
      payload = list(old = "old", new = "new", path = "a")))))
  legacy_artifact <- tool_result_artifact(
    codeagent:::.adapt_tool_result(legacy))
  expect_identical(legacy_artifact$kind, "diff")
  expect_identical(legacy_artifact$status, "error")
})


test_that("external shinychat display metadata respects the HTML trust boundary", {
  hostile <- "<img src=x onerror=alert(1)><script>alert(2)</script>"
  base <- tool_result(
    "portable", kind = "text", payload = list(text = "portable"))

  ex <- base@extra
  ex$display <- list(markdown = hostile, html = hostile)
  base@extra <- ex
  adapted <- expect_no_error(codeagent:::.adapt_tool_result(base))
  display <- adapted@extra$display
  expect_false(grepl("<script", display$markdown, fixed = TRUE))
  expect_match(display$markdown, "&lt;script", fixed = TRUE)
  display_html <- as.character(display$html)
  expect_false(grepl("<img", display_html, fixed = TRUE))
  expect_match(display_html, "&lt;img", fixed = TRUE)

  typed <- tool_result(
    "portable", kind = "text", payload = list(text = "portable"))
  typed_ex <- typed@extra
  typed_ex$display <- shinychat::tool_result_display(markdown = hostile)
  typed@extra <- typed_ex
  typed_display <- codeagent:::.adapt_tool_result(typed)@extra$display
  expect_false(grepl("<script", typed_display$markdown, fixed = TRUE))
  expect_match(typed_display$markdown, "&lt;script", fixed = TRUE)

  trusted <- tool_result(
    "portable", kind = "text", payload = list(text = "portable"))
  trusted_ex <- trusted@extra
  trusted_ex$display <- list(html = htmltools::HTML("<strong>Trusted</strong>"))
  trusted@extra <- trusted_ex
  trusted_display <- codeagent:::.adapt_tool_result(trusted)@extra$display
  expect_match(as.character(trusted_display$html),
               "<strong>Trusted</strong>", fixed = TRUE)
})

test_that("atomic codeagent metadata degrades to a value-backed artifact", {
  raw <- ContentToolResult(
    value = "portable fallback", extra = list(codeagent = "malformed"))
  adapted <- expect_no_error(codeagent:::.adapt_tool_result(raw))
  expect_identical(tool_result_value(adapted), "portable fallback")
  expect_identical(tool_result_artifact(adapted)$version, 1L)
})


test_that("raw results preserve a safe official framed display while gaining artifact", {
  raw <- ContentToolResult(
    value = "portable raw value",
    extra = list(display = shinychat::tool_result_display(
      title = "External framed result",
      html = htmltools::tags$pre("FRAMED_CONTENT"),
      open_style = "framed")))

  adapted <- expect_no_error(codeagent:::.adapt_tool_result(raw))
  expect_identical(tool_result_artifact(adapted)$version, 1L)
  expect_identical(tool_result_value(adapted), "portable raw value")
  expect_s3_class(adapted@extra$display, "shinychat_tool_result_display")
  expect_identical(adapted@extra$display$open_style, "framed")
  expect_match(as.character(adapted@extra$display$html),
               "FRAMED_CONTENT", fixed = TRUE)
})
