#!/usr/bin/env Rscript
# Installed-package Chrome E2E gate for Plan 37 section 16.14.
# Run from outside the source project, for example:
#   cd /tmp
#   Rscript --vanilla /path/to/codeagent/tests/e2e/verify-upstream-adoption.R
# Set CODEAGENT_E2E_CASE to core, pass, redact, or block to run one case.
# When unset, all four cases run in isolated app/browser processes.

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

fail <- function(...) stop(paste0(...), call. = FALSE)
assert <- function(ok, message) if (!isTRUE(ok)) fail(message)

append_site_library <- function() {
  site <- file.path(
    "/posit_share/site_library_u",
    paste(R.version$major, R.version$minor, sep = "."))
  if (dir.exists(site)) .libPaths(unique(c(.libPaths(), site)))
  invisible(site)
}

mandatory_preflight <- function(start_wd) {
  description <- file.path(start_wd, "DESCRIPTION")
  if (file.exists(description)) {
    first <- tryCatch(readLines(description, n = 1L, warn = FALSE),
                      error = function(e) "")
    if (identical(first, "Package: codeagent")) {
      fail("Driver must start outside the codeagent source project; current directory is ",
           start_wd)
    }
  }
  if (file.exists(file.path(start_wd, ".Renviron"))) {
    fail("Driver start directory contains .Renviron; use a clean outside-project directory.")
  }

  append_site_library()
  packages <- c(
    "codeagent", "ellmer", "btw", "shinychat", "shiny", "bslib",
    "callr", "chromote", "httpuv", "jsonlite")
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing)) {
    fail("Mandatory E2E packages are missing: ", paste(missing, collapse = ", "))
  }

  frozen <- list(
    ellmer = c(version = "0.4.2.9000",
               sha = "19be478ebf1a2e5d2db96a8aeaca71592c8d3f26"),
    btw = c(version = "1.4.0.9000",
            sha = "d11591b09d9127b05d673e8c96569d2bbae2ec44"),
    shinychat = c(version = "0.4.0.9000",
                  sha = "aa35a0988319103c35637e6d467ebc02a3180e3c"),
    shiny = c(version = "1.14.0.9000", sha = "d19095f4b3dd"),
    bslib = c(version = "0.12.0.9000", sha = "97aa1abc262b")
  )
  for (package in names(frozen)) {
    info <- utils::packageDescription(package)
    actual_version <- as.character(info$Version %||% "")
    actual_sha <- as.character(info$RemoteSha %||% "")
    assert(identical(actual_version, unname(frozen[[package]][["version"]])),
           paste0("Frozen version mismatch for ", package, ": ", actual_version))
    assert(startsWith(actual_sha, unname(frozen[[package]][["sha"]])),
           paste0("Frozen SHA mismatch for ", package, ": ", actual_sha))
  }

  chrome <- tryCatch(chromote::find_chrome(), error = function(e) character())
  assert(length(chrome) > 0L && file.exists(unname(chrome[[1L]])),
         "Mandatory Chrome/Chromium binary was not found.")

  app_path <- system.file("examples", "test_web_citations.R", package = "codeagent")
  assert(nzchar(app_path) && file.exists(app_path),
         paste0(
           "Installed codeagent does not contain examples/test_web_citations.R. ",
           "Install the current work tree before running this gate."))
  package_path <- normalizePath(system.file(package = "codeagent"),
                                winslash = "/", mustWork = TRUE)
  app_path <- normalizePath(app_path, winslash = "/", mustWork = TRUE)
  assert(startsWith(app_path, paste0(package_path, "/")),
         "E2E app was not resolved from the installed codeagent package.")

  app_text <- paste(readLines(app_path, warn = FALSE), collapse = "\n")
  forbidden <- c("devtools::load_all", "pkgload::load_all", "readRenviron")
  found <- forbidden[vapply(forbidden, grepl, logical(1L), x = app_text,
                            fixed = TRUE)]
  assert(!length(found),
         paste0("Installed E2E app contains forbidden bootstrap calls: ",
                paste(found, collapse = ", ")))

  required_exports <- c(
    "codeagent_app", "codeagent_client", "save_session", "shield_regex")
  missing_exports <- setdiff(required_exports, getNamespaceExports("codeagent"))
  assert(!length(missing_exports),
         paste0("Installed codeagent lacks required exports: ",
                paste(missing_exports, collapse = ", ")))
  required_internal <- c(
    ".new_web_source", ".new_citation_registry", ".citation_registry_add",
    ".citation_sources_from_result", ".finalize_server_reply",
    ".output_gate_guarded", ".BTW_GROUPS")
  missing_internal <- required_internal[!vapply(
    required_internal, exists, logical(1L),
    envir = asNamespace("codeagent"), inherits = FALSE)]
  assert(!length(missing_internal),
         paste0("Installed codeagent lacks required E2E capabilities: ",
                paste(missing_internal, collapse = ", ")))

  cat("mandatory_preflight=PASS installed_app=", app_path, "\n", sep = "")
  app_path
}

wait_for_port <- function(proc, port, timeout_s, log_file) {
  deadline <- Sys.time() + timeout_s
  repeat {
    if (!proc$is_alive()) {
      log <- tryCatch(tail(readLines(log_file, warn = FALSE), 30L),
                      error = function(e) character())
      fail("App process exited before readiness. Log tail:\n",
           paste(log, collapse = "\n"))
    }
    con <- suppressWarnings(tryCatch(
      socketConnection("127.0.0.1", port = port, open = "r+",
                       blocking = TRUE, timeout = 0.2),
      error = function(e) NULL))
    if (!is.null(con)) {
      close(con)
      return(invisible(TRUE))
    }
    if (Sys.time() >= deadline) {
      fail("Timed out waiting for localhost app port ", port)
    }
    Sys.sleep(0.1)
  }
}

run_case <- function(case, app_path, root) {
  case_root <- file.path(root, paste0("case-", case))
  dir.create(case_root, recursive = TRUE, showWarnings = FALSE)
  home <- file.path(case_root, "home")
  dir.create(home, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(case_root, "app.log")
  port <- httpuv::randomPort()

  child_env <- c(
    HOME = home,
    R_USER = home,
    CODEAGENT_E2E_CASE = case,
    CODEAGENT_E2E_ROOT = case_root,
    CODEAGENT_HOME = file.path(home, ".codeagent"),
    http_proxy = "http://127.0.0.1:9",
    https_proxy = "http://127.0.0.1:9",
    HTTP_PROXY = "http://127.0.0.1:9",
    HTTPS_PROXY = "http://127.0.0.1:9",
    NO_PROXY = "127.0.0.1,localhost",
    no_proxy = "127.0.0.1,localhost",
    CODEAGENT_BASE_URL = NA_character_,
    CODEAGENT_API_KEY = NA_character_,
    CODEAGENT_MODEL = NA_character_,
    CODEAGENT_FAST_MODEL = NA_character_,
    CODEAGENT_HEAVY_MODEL = NA_character_,
    OPENAI_API_KEY = NA_character_,
    ANTHROPIC_API_KEY = NA_character_,
    GOOGLE_API_KEY = NA_character_,
    BRAVE_API_KEY = NA_character_
  )

  proc <- callr::r_bg(
    function(app_path, port) {
      Sys.unsetenv(c(
        "CODEAGENT_BASE_URL", "CODEAGENT_API_KEY", "CODEAGENT_MODEL",
        "CODEAGENT_FAST_MODEL", "CODEAGENT_HEAVY_MODEL", "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY", "GOOGLE_API_KEY", "BRAVE_API_KEY"))
      shiny::runApp(
        app_path, host = "127.0.0.1", port = port,
        launch.browser = FALSE, quiet = TRUE)
    },
    args = list(app_path = app_path, port = port),
    libpath = .libPaths(),
    stdout = log_file,
    stderr = log_file,
    cmdargs = c("--vanilla", "--slave", "--no-save", "--no-restore"),
    system_profile = FALSE,
    user_profile = FALSE,
    env = child_env,
    supervise = TRUE,
    wd = case_root
  )

  browser_session <- NULL
  browser_process <- NULL
  on.exit({
    if (!is.null(browser_session)) {
      try(browser_session$close(), silent = TRUE)
    }
    if (!is.null(browser_process)) {
      try(browser_process$kill(), silent = TRUE)
    }
    if (!is.null(proc) && proc$is_alive()) {
      try(proc$kill(), silent = TRUE)
      try(proc$wait(timeout = 3000L), silent = TRUE)
    }
  }, add = TRUE)

  wait_for_port(proc, port, timeout_s = 150, log_file = log_file)

  browser_session <- chromote::ChromoteSession$new()
  browser_process <- tryCatch(
    browser_session$parent$get_browser()$get_process(),
    error = function(e) NULL)

  events <- new.env(parent = emptyenv())
  events$errors <- character()
  events$external_requests <- character()
  events$external_responses <- character()

  browser_session$Runtime$enable()
  browser_session$Network$enable()
  browser_session$Network$setBlockedURLs(urls = c(
    "https://*", "http://localhost/*", "http://0.0.0.0/*", "http://[::1]/*"))
  browser_session$Runtime$consoleAPICalled(callback_ = function(message) {
    if (!identical(message$type, "error")) return()
    values <- vapply(message$args %||% list(), function(arg) {
      as.character(arg$value %||% arg$description %||% "")[[1L]]
    }, character(1L))
    events$errors <- c(events$errors, paste(values, collapse = " "))
  })
  browser_session$Runtime$exceptionThrown(callback_ = function(message) {
    details <- message$exceptionDetails %||% list()
    text <- details$exception$description %||% details$text %||% "unknown exception"
    events$errors <- c(events$errors, paste0("EXCEPTION: ", text))
  })

  app_url <- sprintf("http://127.0.0.1:%d", port)
  is_allowed_browser_url <- function(url) {
    startsWith(url, app_url) || startsWith(url, "data:") ||
      startsWith(url, "blob:") || startsWith(url, "about:")
  }
  browser_session$Network$requestWillBeSent(callback_ = function(message) {
    url <- as.character(message$request$url %||% "")[[1L]]
    if (nzchar(url) && !is_allowed_browser_url(url))
      events$external_requests <- c(events$external_requests, url)
  })
  browser_session$Network$responseReceived(callback_ = function(message) {
    url <- as.character(message$response$url %||% "")[[1L]]
    if (nzchar(url) && !is_allowed_browser_url(url)) {
      events$external_responses <- c(events$external_responses, url)
    }
  })

  browser_session$Emulation$setDeviceMetricsOverride(
    width = 1440L, height = 900L, deviceScaleFactor = 1, mobile = FALSE)
  browser_session$Page$navigate(url = app_url)

  evaluate <- function(expression) {
    result <- browser_session$Runtime$evaluate(
      expression = expression, returnByValue = TRUE)
    if (!is.null(result$exceptionDetails)) {
      fail("Browser evaluation failed: ",
           result$exceptionDetails$text %||% "unknown JavaScript error")
    }
    result$result$value %||% NULL
  }
  js_quote <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))

  wait_until <- function(label, predicate, timeout_s = 45, interval_s = 0.1,
                         observe = NULL) {
    deadline <- Sys.time() + timeout_s
    repeat {
      if (!proc$is_alive()) fail("App process exited while waiting for ", label)
      value <- tryCatch(predicate(), error = function(e) FALSE)
      if (!is.null(observe)) observe()
      if (isTRUE(value)) return(invisible(TRUE))
      if (Sys.time() >= deadline) fail("Timed out waiting for ", label)
      Sys.sleep(interval_s)
    }
  }

  overlay_seen <- FALSE
  observe_overlay <- function() {
    shown <- tryCatch(isTRUE(evaluate(paste0(
      "(function(){const e=document.getElementById('ca_init_overlay');",
      "return !!e && /Initializing codeagent/.test(e.innerText);})()"))),
      error = function(e) FALSE)
    overlay_seen <<- overlay_seen || shown
  }

  wait_until(
    "Shiny shell",
    function() isTRUE(evaluate(paste0(
      "document.readyState === 'complete' && !!window.Shiny && ",
      "!!document.getElementById('chat')"))),
    timeout_s = 45, interval_s = 0.05, observe = observe_overlay)
  wait_until(
    "initialization overlay presentation",
    function() isTRUE(evaluate(paste0(
      "(function(){const o=document.getElementById('ca_init_overlay');",
      "return !!o && /Initializing codeagent/.test(o.textContent||'');})()"))),
    timeout_s = 15, interval_s = 0.05, observe = observe_overlay)
  wait_until(
    "initialization completion and enabled composer",
    function() isTRUE(evaluate(paste0(
      "(function(){const o=document.getElementById('ca_init_overlay');",
      "const e=document.querySelector('#chat .ProseMirror[contenteditable=\"true\"]');",
      "return !!e && (!o || !/Initializing codeagent/.test(o.textContent||''));})()"))),
    timeout_s = if (identical(case, "core")) 150 else 45,
    interval_s = 0.05, observe = observe_overlay)
  value <- function(expression) evaluate(paste0("(function(){", expression, "})()"))
  count <- function(selector) as.integer(value(paste0(
    "return document.querySelectorAll(", js_quote(selector), ").length;")))
  text <- function(selector) as.character(value(paste0(
    "const e=document.querySelector(", js_quote(selector), ");",
    "return e ? e.innerText : '';")) %||% "")
  assert(count("#ca_init_overlay") == 1L,
         "Initialization overlay output container is missing.")

  # A checked checkbox only proves the browser's local state changed. Capture
  # toast mutations so each real click must also receive a fresh acknowledgement
  # from server_settings() after .replace_btw_tool_groups() commits or fails.
  reset_tool_ack_capture <- function() {
    value(paste0(
      "if(window.__caE2EToolAckObserver)",
      "window.__caE2EToolAckObserver.disconnect();",
      "window.__caE2EToolAcks=[];",
      "const record=n=>{",
      "const t=(n&&n.textContent)||'';",
      "if(/btw tool groups updated|tool-group update|could not|duplicate|disabled/i.test(t))",
      "window.__caE2EToolAcks.push(t.trim());};",
      "window.__caE2EToolAckObserver=new MutationObserver(ms=>",
      "ms.forEach(m=>{",
      "if(m.type==='characterData')record(m.target);",
      "m.addedNodes.forEach(record);",
      "}));",
      "window.__caE2EToolAckObserver.observe(document.body,",
      "{childList:true,subtree:true,characterData:true});",
      "return true;"))
    invisible(TRUE)
  }
  tool_ack_status <- function() as.character(value(paste0(
    "const a=window.__caE2EToolAcks||[];",
    "if(a.some(x=>/failed|could not|duplicate|disabled|restored/i.test(x)))",
    "return 'failure';",
    "if(a.some(x=>/btw tool groups updated/i.test(x)))return 'success';",
    "return '';")) %||% "")
  wait_for_tool_ack <- function(label, timeout_s = 90) {
    wait_until(
      paste0(label, " server acknowledgement"),
      function() nzchar(tool_ack_status()), timeout_s = timeout_s)
    status <- tool_ack_status()
    assert(identical(status, "success"),
           paste0(label, " received a server-side tool-group failure acknowledgement."))
    invisible(TRUE)
  }

  click_expression <- function(element_expression, label) {
    payload <- value(paste0(
      "const e=", element_expression, ";",
      "if(!e)return null;",
      "e.scrollIntoView({block:'center',inline:'center'});",
      "const r=e.getBoundingClientRect();",
      "if(r.width<=0||r.height<=0)return null;",
      "const x=r.left+r.width/2,y=r.top+r.height/2;",
      "const h=document.elementFromPoint(x,y);",
      "return JSON.stringify({x:x,y:y,hit:!!h&&(h===e||e.contains(h)),",
      "hitTag:h?h.tagName:'',hitId:h?h.id:'',hitClass:h?String(h.className||''):'',",
      "hitHtml:h?h.outerHTML.slice(0,300):''});"))
    if (is.null(payload) || !nzchar(payload)) fail("Clickable element missing: ", label)
    point <- jsonlite::fromJSON(payload)
    if (!isTRUE(point$hit))
      fail("Pointer target is covered for ", label, ": ",
           point$hitTag %||% "", "#", point$hitId %||% "", ".",
           point$hitClass %||% "", " ", point$hitHtml %||% "")
    browser_session$Input$dispatchMouseEvent(
      type = "mouseMoved", x = point$x, y = point$y)
    browser_session$Input$dispatchMouseEvent(
      type = "mousePressed", x = point$x, y = point$y,
      button = "left", buttons = 1L, clickCount = 1L)
    browser_session$Input$dispatchMouseEvent(
      type = "mouseReleased", x = point$x, y = point$y,
      button = "left", buttons = 0L, clickCount = 1L)
    invisible(TRUE)
  }
  click_selector <- function(selector, label = selector, index = 0L) {
    click_expression(paste0(
      "document.querySelectorAll(", js_quote(selector), ")[", index, "]"), label)
  }

  assert(count("#ca_left_sidebar") == 1L, "Left sidebar is missing.")
  assert(count("#ca_output_sidebar") == 1L, "Right output sidebar is missing.")
  assert(count("#main_tab") == 1L, "Right-panel static navset is missing.")
  tab_values <- value(paste0(
    "return Array.from(document.querySelectorAll('#main_tab [data-value]'))",
    ".map(e=>e.getAttribute('data-value'));"))
  assert(all(c("output", "files", "file_view") %in% unlist(tab_values)),
         "Output/Files/File static tabs are not all present.")
  assert(count(".shiny-chat-greeting") == 1L,
         "Persistent greeting is missing or duplicated at startup.")
  assert(grepl("codeagent", text(".shiny-chat-greeting"), fixed = TRUE),
         "Persistent greeting content is incorrect.")

  case_token <- paste0("E2E_CASE_", toupper(case))
  tryCatch(
    wait_until(
      paste0(case, " lossless session restore"),
      function() {
        restored_text <- text("#chat")
        if (identical(case, "block"))
          grepl("block", restored_text, ignore.case = TRUE) else
          grepl(case_token, restored_text, fixed = TRUE)
      },
      timeout_s = 45),
    error = function(e) fail(
      conditionMessage(e), "\nChat DOM text: ", substr(text("#chat"), 1L, 2000L)))

  assert(!grepl(sentinel <- "E2EPROTECTED123", text("#chat"), fixed = TRUE),
         paste0("Protected sentinel reached the browser after lossless session restore; ",
                "citation replay did not fail closed."))
  assert(!grepl("[[cite:", text("#chat"), fixed = TRUE),
         "A raw citation marker reached the browser after lossless session restore.")

  verify_citation <- function(expected_asides, expected_grounded_text = NULL) {
    wait_until(
      "citation Sources pill",
      function() count(".shiny-sources-pill") == 1L,
      timeout_s = 30)
    grounded <- count(".shiny-aside-grounded")
    assert(grounded >= expected_asides,
           paste0("Expected at least ", expected_asides,
                  " grounded citation spans, found ", grounded, "."))
    if (!is.null(expected_grounded_text)) {
      grounded_text <- text(".shiny-aside-grounded")
      assert(grepl(expected_grounded_text, grounded_text, fixed = TRUE),
             paste0("Grounded citation text missing: ", expected_grounded_text))
    }

    click_selector(".shiny-sources-pill", "Sources pill")
    Sys.sleep(0.3)
    if (count(".shiny-sources-popover") == 0L) {
      focused <- isTRUE(value(
        "return document.activeElement && document.activeElement.classList.contains('shiny-sources-pill');"))
      assert(focused, "Sources pill did not receive real pointer focus.")
      browser_session$Input$dispatchKeyEvent(
        type = "keyDown", key = "Enter", code = "Enter",
        windowsVirtualKeyCode = 13L)
      browser_session$Input$dispatchKeyEvent(
        type = "keyUp", key = "Enter", code = "Enter",
        windowsVirtualKeyCode = 13L)
    }
    tryCatch(
      wait_until(
        "Sources popover",
        function() count(".shiny-sources-popover") == 1L,
        timeout_s = 15),
      error = function(e) {
        source_dom <- as.character(value(paste0(
          "return Array.from(document.querySelectorAll('*')).filter(e=>",
          "/source/i.test(String(e.className||''))||/Sources/.test(e.innerText||''))",
          ".slice(0,30).map(e=>({tag:e.tagName,cls:String(e.className||''),",
          "text:(e.innerText||'').slice(0,200)}));")))
        fail(conditionMessage(e), "\nSources DOM: ", paste(source_dom, collapse = " | "))
      })
    assert(identical(trimws(text(".shiny-sources-popover__title")), "Sources"),
           "Sources popover title is incorrect.")
    assert(count(".shiny-sources-item") == 1L,
           "Duplicate citations were not deduplicated to one source.")
    href <- as.character(value(paste0(
      "const e=document.querySelector('.shiny-sources-item__link');",
      "return e ? e.href : '';")) %||% "")
    assert(identical(href, "https://example.com/codeagent-e2e"),
           paste0("Citation href is not the validated source URL: ", href))
    in_viewport <- isTRUE(value(paste0(
      "const e=document.querySelector('.shiny-sources-popover');",
      "if(!e)return false;const r=e.getBoundingClientRect();",
      "return r.width>0&&r.height>0&&r.left>=0&&r.top>=0&&",
      "r.right<=window.innerWidth&&r.bottom<=window.innerHeight;")))
    assert(in_viewport, "Sources popover is present but outside the viewport.")
  }

  if (case %in% c("core", "pass", "redact")) {
    verify_citation(
      expected_asides = if (identical(case, "core")) 2L else 1L,
      expected_grounded_text = switch(
        case,
        core = "grounded evidence",
        pass = "safe grounded evidence",
        redact = "[REDACTED]"))
  }
  if (identical(case, "redact")) {
    assert(grepl("[REDACTED]", text("#chat"), fixed = TRUE),
           "Redact case did not expose an assertable redaction result.")
  }
  if (identical(case, "block")) {
    assert(grepl("blocked", tolower(text("#chat")), fixed = TRUE),
           "Block case did not expose an assertable blocked result.")
    assert(count(".shiny-sources-pill") == 0L,
           "Blocked response unexpectedly rendered a citation source pill.")
    assert(count(".shiny-aside-grounded") == 0L,
           "Blocked response unexpectedly rendered grounded citation text.")
  }

  if (identical(case, "core")) {
    # Real mouse navigation through Files, then a real jsTree node click.
    click_expression(paste0(
      "Array.from(document.querySelectorAll('#main_tab [data-value=\"files\"]'))",
      ".find(e=>e.matches('a,button'))"), "Files tab")
    wait_until(
      "Files tab activation",
      function() isTRUE(value(paste0(
        "const e=Array.from(document.querySelectorAll(",
        "'#main_tab [data-value=\"files\"]')).find(x=>x.matches('a,button'));",
        "return !!e&&e.classList.contains('active');"))),
      timeout_s = 15)

    # jsTreeR loads directory children lazily when the disclosure icon receives a
    # real pointer click; the root intentionally starts as a disabled leaf.
    wait_until(
      "file tree root disclosure icon",
      function() count("#file_tree-treeNavigator___ > ul > li.jstree-x > i.jstree-ocl") == 1L,
      timeout_s = 20)
    click_expression(
      "document.querySelector('#file_tree-treeNavigator___ > ul > li.jstree-x > i.jstree-ocl')",
      "file tree root disclosure icon")

    tryCatch(
      wait_until(
        "deterministic file tree node",
        function() isTRUE(value(paste0(
          "return Array.from(document.querySelectorAll('.jstree-anchor'))",
          ".some(e=>e.innerText.trim()==='e2e-visible.txt');"))),
        timeout_s = 30),
      error = function(e) {
        tree_dom <- value(paste0(
          "return Array.from(document.querySelectorAll('*')).filter(e=>",
          "/e2e-visible|jstree|tree/i.test((e.innerText||'')+' '+String(e.className||'')))",
          ".slice(-40).map(e=>({tag:e.tagName,id:e.id,cls:String(e.className||''),",
          "text:(e.innerText||'').slice(0,200)}));"))
        fail(conditionMessage(e), "\nFile tree DOM: ", paste(tree_dom, collapse = " | "))
      })
    click_expression(paste0(
      "Array.from(document.querySelectorAll('.jstree-anchor'))",
      ".find(e=>e.innerText.trim()==='e2e-visible.txt')"),
      "e2e-visible.txt file node")
    wait_until(
      "File tab preview",
      function() grepl("E2E_FILE_CONTENT", text("#ca_file_view"), fixed = TRUE),
      timeout_s = 20)
    assert(grepl("e2e-visible.txt", text("#ca_file_view"), fixed = TRUE),
           "File viewer header did not retain the selected filename.")

    # Real CDP keyboard input: type into ProseMirror, select all, and clear.
    click_selector("#chat .ProseMirror[contenteditable=\"true\"]", "chat composer")
    browser_session$Input$insertText(text = "E2E keyboard probe")
    wait_until(
      "composer keyboard text",
      function() grepl("E2E keyboard probe",
                       text("#chat .ProseMirror"), fixed = TRUE),
      timeout_s = 10)
    browser_session$Input$dispatchKeyEvent(
      type = "keyDown", key = "a", code = "KeyA",
      windowsVirtualKeyCode = 65L, modifiers = 2L)
    browser_session$Input$dispatchKeyEvent(
      type = "keyUp", key = "a", code = "KeyA",
      windowsVirtualKeyCode = 65L, modifiers = 2L)
    browser_session$Input$dispatchKeyEvent(
      type = "keyDown", key = "Backspace", code = "Backspace",
      windowsVirtualKeyCode = 8L)
    browser_session$Input$dispatchKeyEvent(
      type = "keyUp", key = "Backspace", code = "Backspace",
      windowsVirtualKeyCode = 8L)
    wait_until(
      "composer keyboard clear",
      function() !grepl("E2E keyboard probe",
                        text("#chat .ProseMirror"), fixed = TRUE),
      timeout_s = 10)

    # Open Settings with a real pointer, then exercise all -> docs -> none.
    click_expression(paste0(
      "Array.from(document.querySelectorAll('#ca_left_accordion .accordion-button'))",
      ".find(e=>e.innerText.trim()==='Settings')"), "Settings accordion")
    wait_until(
      "btw group checkboxes",
      function() count("input[name=\"btw_groups_input\"]") >= 2L,
      timeout_s = 15)
    wait_until(
      "uncovered btw group labels",
      function() isTRUE(value(paste0(
        "const xs=Array.from(document.querySelectorAll('input[name=\"btw_groups_input\"]:checked'));",
        "return xs.length>0&&xs.every(i=>{const e=i.labels&&i.labels[0];if(!e)return false;",
        "const r=e.getBoundingClientRect(),h=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);",
        "return !!h&&(h===e||e.contains(h));});"))),
      timeout_s = 10)
    initial_groups <- unlist(value(paste0(
      "return Array.from(document.querySelectorAll(",
      "'input[name=\"btw_groups_input\"]:checked')).map(e=>e.value);")))
    all_groups <- unlist(value(paste0(
      "return Array.from(document.querySelectorAll(",
      "'input[name=\"btw_groups_input\"]')).map(e=>e.value);")))
    assert(length(initial_groups) == length(all_groups) && "docs" %in% all_groups,
           "Tool group UI did not start in the all-groups state.")
    for (group in setdiff(initial_groups, "docs")) {
      reset_tool_ack_capture()
      click_expression(paste0(
        "(()=>{const i=Array.from(document.querySelectorAll(",
        "'input[name=\"btw_groups_input\"]')).find(e=>e.value===",
        js_quote(group), ");return i&&i.labels&&i.labels[0];})()"),
        paste0("btw group ", group))
      wait_until(
        paste0("btw group ", group, " unchecked"),
        function() isTRUE(value(paste0(
          "const e=Array.from(document.querySelectorAll(",
          "'input[name=\"btw_groups_input\"]')).find(x=>x.value===",
          js_quote(group), ");return !!e&&!e.checked;"))),
        timeout_s = 30)
      wait_for_tool_ack(paste0("btw group ", group, " removal"))
    }
    checked_after_docs <- unlist(value(paste0(
      "return Array.from(document.querySelectorAll(",
      "'input[name=\"btw_groups_input\"]:checked')).map(e=>e.value);")))
    assert(identical(checked_after_docs, "docs"),
           "Tool group UI did not reach the acknowledged docs-only state.")

    reset_tool_ack_capture()
    click_expression(paste0(
      "(()=>{const i=Array.from(document.querySelectorAll(",
      "'input[name=\"btw_groups_input\"]')).find(e=>e.value==='docs');",
      "return i&&i.labels&&i.labels[0];})()"),
      "btw docs group")
    wait_until(
      "tool groups docs to none",
      function() count("input[name=\"btw_groups_input\"]:checked") == 0L,
      timeout_s = 30)
    wait_for_tool_ack("btw docs group removal")
    assert(count("input[name=\"btw_groups_input\"]:checked") == 0L,
           "Tool group UI did not retain the acknowledged empty state.")

    # New clears the restored conversation but preserves exactly one greeting.
    click_selector("#new_session", "New session")
    wait_until(
      "new session clear",
      function() !grepl(case_token, text("#chat"), fixed = TRUE),
      timeout_s = 20)
    assert(count(".shiny-chat-greeting") == 1L,
           "New session lost or duplicated the persistent greeting.")
    assert(count(".shiny-sources-pill") == 0L,
           "New session retained stale citation sources.")

    wait_until(
      "saved fixture session button",
      function() count(".ca-session-btn") >= 1L,
      timeout_s = 20)
    click_selector(".ca-session-btn", "saved fixture session")
    wait_until(
      "explicit session restore",
      function() grepl(case_token, text("#chat"), fixed = TRUE),
      timeout_s = 30)
    assert(count(".shiny-chat-greeting") == 1L,
           "Session restore lost or duplicated the persistent greeting.")
    wait_until(
      "restored citation Sources pill",
      function() count(".shiny-sources-pill") == 1L,
      timeout_s = 20)
  }

  Sys.sleep(0.5)
  assert(!length(events$external_requests),
         paste0("Non-local browser request attempted: ",
                paste(unique(events$external_requests), collapse = ", ")))
  assert(!length(events$external_responses),
         paste0("Non-local network response observed: ",
                paste(unique(events$external_responses), collapse = ", ")))
  assert(!length(events$errors),
         paste0("Browser console.error or uncaught exception: ",
                paste(events$errors, collapse = " | ")))

  cat("CODEAGENT_E2E_CASE=", case, " PASS", "\n", sep = "")
  invisible(TRUE)
}

main <- function() {
  start_wd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  app_path <- mandatory_preflight(start_wd)

  requested <- Sys.getenv("CODEAGENT_E2E_CASE", "")
  valid_cases <- c("core", "pass", "redact", "block")
  if (nzchar(requested) && !requested %in% valid_cases) {
    fail("CODEAGENT_E2E_CASE must be one of: ",
         paste(valid_cases, collapse = ", "))
  }
  cases <- if (nzchar(requested)) requested else valid_cases

  root <- tempfile("codeagent-installed-e2e-")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  setwd(root)
  assert(!file.exists(".Renviron"), "Isolated E2E root unexpectedly has .Renviron.")

  chromote::set_chrome_args(unique(c(
    chromote::default_chrome_args(),
    "--disable-dev-shm-usage",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-background-networking",
    "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"
  )))

  failures <- character()
  for (case in cases) {
    tryCatch(
      run_case(case, app_path, root),
      error = function(e) {
        log_file <- file.path(root, paste0("case-", case), "app.log")
        log_tail <- tryCatch(tail(readLines(log_file, warn = FALSE), 40L),
                             error = function(e2) character())
        detail <- paste0(case, ": ", conditionMessage(e),
                         if (length(log_tail)) paste0("\nApp log:\n",
                           paste(log_tail, collapse = "\n")) else "")
        failures <<- c(failures, detail)
        cat("CODEAGENT_E2E_CASE=", case, " FAIL: ", detail, "\n", sep = "")
      })
  }
  if (length(failures)) {
    fail("Installed Chrome E2E failed:\n", paste(failures, collapse = "\n"))
  }
  cat("verify_upstream_adoption=PASS cases=",
      paste(cases, collapse = ","), "\n", sep = "")
  invisible(TRUE)
}

main()
