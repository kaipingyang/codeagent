#!/usr/bin/env Rscript
# Installed-package Chrome E2E gate for the current default GitHub HEAD manifest.
# Run from outside the source project, for example:
#   cd /tmp
#   Rscript --vanilla /path/to/codeagent/tests/e2e/verify-upstream-adoption.R
# Set CODEAGENT_E2E_CASE to core, pass, redact, or block to run one case.
# When unset, all four cases run in isolated app/browser processes.

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

fail <- function(...) stop(paste0(...), call. = FALSE)
assert <- function(ok, message) if (!isTRUE(ok)) fail(message)

configure_validation_libraries <- function() {
  default_lib <- .libPaths()[dir.exists(.libPaths())][[1L]]
  target <- path.expand(Sys.getenv("CODEAGENT_E2E_LIB", unset = default_lib))
  assert(dir.exists(target), paste0("E2E library does not exist: ", target))
  target <- normalizePath(target, winslash = "/", mustWork = TRUE)

  site <- file.path(
    "/posit_share/site_library_u",
    paste(R.version$major, R.version$minor, sep = "."))
  assert(dir.exists(site), paste0("Site library does not exist: ", site))
  site <- normalizePath(site, winslash = "/", mustWork = TRUE)

  shared <- normalizePath(
    "/usrfiles/shared-projects/users/kaiping_yang/Rlibs/codeagent/R-4.4",
    winslash = "/", mustWork = TRUE)
  .libPaths(unique(c(target, if (!identical(target, shared)) shared,
                     site, .Library)))
  assert(identical(normalizePath(.libPaths()[[1L]], winslash = "/",
                                 mustWork = TRUE), target),
         "E2E validation library is not first in .libPaths().")
  list(target = target, site = site)
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

  libraries <- configure_validation_libraries()
  packages <- c(
    "codeagent", "ellmer", "btw", "shinychat", "shiny", "bslib",
    "mcptools", "Rapp", "httr2", "callr", "chromote", "httpuv", "jsonlite")
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing)) {
    fail("Mandatory E2E packages are missing: ", paste(missing, collapse = ", "))
  }

  frozen <- list(
    codeagent = c(version = "0.2.1.9000", sha = ""),
    ellmer = c(version = "0.4.2.9000",
               sha = "2e96ac58a33d74bea585727daf8cd1535c67d7f1"),
    btw = c(version = "1.4.0.9000",
            sha = "d11591b09d9127b05d673e8c96569d2bbae2ec44"),
    shinychat = c(version = "0.4.0.9000",
                  sha = "2b249764ce45b224224b7d185b3f34f14d0ad84f"),
    shiny = c(version = "1.14.0.9000",
              sha = "81844600fc15f1952838546faa6699d0506ce7f9"),
    bslib = c(version = "0.12.0.9000",
              sha = "6935d9819fcb37e0b42ffa54f4e1cab0418ec2ce"),
    mcptools = c(version = "1.0.2.9000",
                 sha = "079e011e6f2a515565f903dc8a5b7c4d793746f1"),
    Rapp = c(version = "0.4.1.9000",
             sha = "489655f24945042791ddb083d0d5518c4a905d9f"),
    httr2 = c(version = "1.3.0.9000",
              sha = "7ce699f813e662850ea21d9f87e242e0c699f9fe")
  )
  for (package in names(frozen)) {
    info <- utils::packageDescription(package)
    actual_version <- as.character(info$Version %||% "")
    actual_sha <- as.character(info$RemoteSha %||% "")
    expected_version <- unname(frozen[[package]][["version"]])
    expected_sha <- unname(frozen[[package]][["sha"]])
    assert(identical(actual_version, expected_version),
           paste0("Frozen version mismatch for ", package, ": ", actual_version))
    if (nzchar(expected_sha)) {
      assert(identical(actual_sha, expected_sha),
             paste0("Frozen SHA mismatch for ", package, ": ", actual_sha))
    }

    installed_path <- normalizePath(system.file(package = package),
                                    winslash = "/", mustWork = TRUE)
    assert(identical(dirname(installed_path), libraries$target),
           paste0(package, " was not loaded from the E2E validation library: ",
                  installed_path))
    cat("validated_package=", package, " version=", actual_version,
        if (nzchar(actual_sha)) paste0(" sha=", actual_sha) else "",
        " path=", installed_path, "\n", sep = "")
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

run_case <- function(case, app_path, root, ui_layout) {
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
    CODEAGENT_E2E_UI_LAYOUT = ui_layout,
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
    stderr = paste0(log_file, ".stderr"),
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
  deep_count <- function(selector) as.integer(value(paste0(
    "const roots=[document];let n=0;for(let i=0;i<roots.length;i++){",
    "const r=roots[i];n+=r.querySelectorAll(", js_quote(selector), ").length;",
    "for(const e of r.querySelectorAll('*'))if(e.shadowRoot)roots.push(e.shadowRoot);}",
    "return n;")))
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
    deadline <- Sys.time() + 10
    point <- NULL
    repeat {
      payload <- value(paste0(
        "const e=", element_expression, ";",
        "if(!e)return null;",
        "e.scrollIntoView({block:'center',inline:'center'});",
        "const r=e.getBoundingClientRect();",
        "if(r.width<=0||r.height<=0)return null;",
        "const points=[[.5,.5],[.5,.8],[.25,.5],[.75,.5],[.25,.8],[.75,.8]];",
        "let x=r.left+r.width/2,y=r.top+r.height/2,h=null,hit=false;",
        "for(const p of points){x=r.left+r.width*p[0];y=r.top+r.height*p[1];",
        "h=document.elementFromPoint(x,y);hit=!!h&&(h===e||e.contains(h));if(hit)break;}",
        "return JSON.stringify({x:x,y:y,hit:hit,",
        "targetHtml:e.outerHTML.slice(0,300),targetRect:{left:r.left,top:r.top,width:r.width,height:r.height},",
        "hitRect:h?(()=>{const q=h.getBoundingClientRect();return {left:q.left,top:q.top,width:q.width,height:q.height};})():null,",
        "hitTag:h?h.tagName:'',hitId:h?h.id:'',hitClass:h?String(h.className||''):'',",
        "hitHtml:h?h.outerHTML.slice(0,300):''});"))
      if (!is.null(payload) && nzchar(payload)) {
        point <- jsonlite::fromJSON(payload)
        if (isTRUE(point$hit)) break
      }
      if (Sys.time() >= deadline) {
        if (is.null(point)) fail("Clickable element missing: ", label)
        fail("Pointer target is covered for ", label, ": ",
             point$hitTag %||% "", "#", point$hitId %||% "", ".",
             point$hitClass %||% "", " target=", point$targetHtml %||% "",
             " targetRect=", paste(unlist(point$targetRect %||% list()), collapse = ","),
             " hitRect=", paste(unlist(point$hitRect %||% list()), collapse = ","),
             " hit=", point$hitHtml %||% "")
      }
      Sys.sleep(0.1)
    }
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

  if (identical(ui_layout, "page_chat")) {
    assert(count("shiny-chat-page#chat_page") == 1L,
           "page_chat is not the unique top-level chat page.")
    assert(count("#chat-sidebar #ca_left_accordion") == 1L,
           "page_chat codeagent control sidebar is missing.")
    assert(count("#ca_workspace_toggle") == 1L,
           "Persistent Workspace toolbar toggle is missing.")
    dark_mode_count <- deep_count("#ca_dark_mode")
    if (!identical(dark_mode_count, 1L)) {
      dark_dom <- value(paste0(
        "const roots=[document],out=[];for(let i=0;i<roots.length;i++){",
        "const r=roots[i];for(const e of r.querySelectorAll('*')){",
        "if(e.shadowRoot)roots.push(e.shadowRoot);const h=e.outerHTML||'';",
        "if(/dark|theme|color-mode/i.test(h))out.push(h.slice(0,500));}}",
        "return out.slice(0,30);"))
      fail("Persistent global dark-mode input is missing. DOM: ",
           paste(as.character(dark_dom), collapse = " | "))
    }
    width_payload <- as.character(value(paste0(
      "const chat=document.getElementById('chat');",
      "const main=chat?chat.closest('.shiny-chat-page-panel'):null;",
      "if(!chat||!main)return '';",
      "const cr=chat.getBoundingClientRect(),mr=main.getBoundingClientRect();",
      "return JSON.stringify({chat:cr.width,main:mr.width,",
      "css:getComputedStyle(chat).getPropertyValue('--_chat-width').trim()});"))) %||% ""
    assert(nzchar(width_payload), "Could not measure page_chat main-column width.")
    page_width <- jsonlite::fromJSON(width_payload)
    assert(identical(page_width$css, "100%"),
           paste0("page_chat CSS width is not 100%: ", page_width$css %||% ""))
    assert(abs(page_width$chat - page_width$main) <= 2,
           paste0("page_chat does not fill its main panel: chat=", page_width$chat,
                  " panel=", page_width$main))
    cat("page_chat_width=PASS chat=", page_width$chat,
        " panel=", page_width$main, "\n", sep = "")
    wait_until(
      "open page_chat workspace drawer",
      function() count(".shiny-chat-layout[data-drawer-open] .shiny-chat-drawer:not([hidden]) #ca_page_chat_workspace") == 1L,
      timeout_s = 15)
    click_selector("#ca_workspace_toggle", "Workspace toolbar toggle close")
    wait_until(
      "toolbar-closed page_chat workspace drawer",
      function() count(".shiny-chat-layout[data-drawer-open]") == 0L,
      timeout_s = 15)
    click_selector("#ca_workspace_toggle", "Workspace toolbar toggle open")
    wait_until(
      "toolbar-reopened page_chat workspace drawer",
      function() count(".shiny-chat-layout[data-drawer-open] .shiny-chat-drawer:not([hidden]) #ca_page_chat_workspace") == 1L,
      timeout_s = 15)
    assert(count("#ca_output_sidebar") == 0L,
           "Classic output sidebar leaked into page_chat mode.")
  } else {
    assert(count("#ca_left_sidebar") == 1L, "Left sidebar is missing.")
    assert(count("#ca_output_sidebar") == 1L, "Right output sidebar is missing.")
  }
  assert(count("#main_tab") == 1L, "Workspace static navset is missing.")
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

  if (identical(case, "core")) {
    wait_until(
      "restored tool result row",
      function() count(".shiny-chat-tool-group__row, .shiny-chat-tool-call-row__summary") >= 1L,
      timeout_s = 30)
    click_expression(
      "document.querySelector('.shiny-chat-tool-group__row, .shiny-chat-tool-call-row__summary')",
      "restored framed tool result")
    wait_until(
      "framed tool result DOM",
      function() count(".shiny-chat-tool-group--framed, .shiny-chat-tool-call-row--framed") >= 1L,
      timeout_s = 15)
  }

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
    wait_until(
      "clickable deterministic file tree node",
      function() isTRUE(value(paste0(
        "const a=Array.from(document.querySelectorAll('.jstree-anchor'))",
        ".find(e=>e.innerText.trim()==='e2e-visible.txt');",
        "const e=a&&(a.querySelector('.jstree-themeicon')||a);if(!e)return false;",
        "e.scrollIntoView({block:'center',inline:'center'});",
        "const r=e.getBoundingClientRect(),h=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);",
        "return !!h&&(h===e||e.contains(h));"))),
      timeout_s = 15)
    click_expression(paste0(
      "(()=>{const a=Array.from(document.querySelectorAll('.jstree-anchor'))",
      ".find(e=>e.innerText.trim()==='e2e-visible.txt');",
      "return a&&(a.querySelector('.jstree-themeicon')||a);})()"),
      "e2e-visible.txt file node")
    wait_until(
      "File tab preview",
      function() grepl("E2E_FILE_CONTENT", text("#ca_file_view"), fixed = TRUE),
      timeout_s = 20)
    assert(grepl("e2e-visible.txt", text("#ca_file_view"), fixed = TRUE),
           "File viewer header did not retain the selected filename.")
    assert(count("#ca_attach_file") == 1L,
           "File viewer does not expose the Attach to chat action.")
    click_selector("#ca_attach_file", "Attach selected file to chat")
    tryCatch(
      wait_until(
        "selected file staged in composer",
        function() grepl(
          "e2e-visible.txt",
          text(".shiny-chat-input-attachments"),
          fixed = TRUE),
        timeout_s = 15),
      error = function(e) {
        attachment_dom <- value(paste0(
          "return Array.from(document.querySelectorAll('*')).filter(e=>",
          "/attachment/i.test(String(e.className||'')+' '+e.tagName))",
          ".slice(0,40).map(e=>({tag:e.tagName,id:e.id,",
          "cls:String(e.className||''),text:(e.innerText||'').slice(0,200)}));"))
        fail(conditionMessage(e), "\nAttachment DOM: ",
             paste(as.character(attachment_dom), collapse = " | "))
      })
    if (identical(ui_layout, "page_chat")) {
      assert(count(".shiny-chat-layout[data-drawer-open] .shiny-chat-drawer:not([hidden]) #ca_file_view") == 1L,
             "File selection did not retain/open the page_chat workspace drawer.")

      # Prove the server_right() integration, not just the drawer's initial open
      # state: close it with a real pointer, then re-send the file-tree selection
      # through Shiny's input transport and require chat_drawer_show() to reopen it.
      selection_id <- as.character(value(paste0(
        "const k=Object.keys(Shiny.shinyapp.$inputValues)",
        ".find(x=>x.includes('selected_paths'));if(!k)return '';",
        "window.__caE2EFileSelection={id:k,",
        "value:Shiny.shinyapp.$inputValues[k]};return window.__caE2EFileSelection.id;")) %||% "")
      assert(nzchar(selection_id),
             "Could not capture the real jsTree selected-paths Shiny input.")
      click_selector(".shiny-chat-drawer-close", "workspace drawer close")
      wait_until(
        "closed page_chat workspace drawer",
        function() count(".shiny-chat-layout[data-drawer-open]") == 0L,
        timeout_s = 15)
      reopen_file <- normalizePath(
        file.path(case_root, paste0("project-", case), "e2e-reopen.txt"),
        winslash = "/", mustWork = TRUE)
      replayed <- isTRUE(value(paste0(
        "const s=window.__caE2EFileSelection;",
        "const next=JSON.parse(JSON.stringify(s.value));",
        "if(!Array.isArray(next)||!next.length)return false;",
        "next[next.length-1].path=", js_quote(reopen_file), ";",
        "Shiny.setInputValue(s.id,next,{priority:'event'});return true;")))
      assert(replayed, "Could not replay a second file selection through Shiny.")
      wait_until(
        "server-reopened page_chat workspace drawer",
        function() count(".shiny-chat-layout[data-drawer-open] .shiny-chat-drawer:not([hidden]) #ca_file_view") == 1L &&
          grepl("E2E_REOPEN_CONTENT", text("#ca_file_view"), fixed = TRUE),
        timeout_s = 20)
    }

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
    initial_groups <- unlist(value(paste0(
      "return Array.from(document.querySelectorAll(",
      "'input[name=\"btw_groups_input\"]:checked')).map(e=>e.value);")))
    all_groups <- unlist(value(paste0(
      "return Array.from(document.querySelectorAll(",
      "'input[name=\"btw_groups_input\"]')).map(e=>e.value);")))
    assert(length(initial_groups) == length(all_groups) && "docs" %in% all_groups,
           "Tool group UI did not start in the all-groups state.")
    if (identical(ui_layout, "classic")) {
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
    }

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
  ui_layout <- Sys.getenv("CODEAGENT_E2E_UI_LAYOUT", "classic")
  if (!ui_layout %in% c("classic", "page_chat")) {
    fail("CODEAGENT_E2E_UI_LAYOUT must be classic or page_chat.")
  }
  valid_cases <- c("core", "pass", "redact", "block")
  if (nzchar(requested) && !requested %in% valid_cases) {
    fail("CODEAGENT_E2E_CASE must be one of: ",
         paste(valid_cases, collapse = ", "))
  }
  cases <- if (nzchar(requested)) requested else
    if (identical(ui_layout, "page_chat")) "core" else valid_cases

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
      run_case(case, app_path, root, ui_layout),
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
  cat("verify_upstream_adoption=PASS layout=", ui_layout, " cases=",
      paste(cases, collapse = ","), "\n", sep = "")
  invisible(TRUE)
}

main()
