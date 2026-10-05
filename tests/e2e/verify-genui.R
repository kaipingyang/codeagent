#!/usr/bin/env Rscript
# Installed-package Chrome E2E gate for the generative UI canvas.
# Run from outside the source project after installing the work tree:
#   cd /tmp && Rscript --vanilla /path/to/codeagent/tests/e2e/verify-genui.R
#
# Deterministic cases (no model, no network) run the fixture app
# inst/examples/test_genui_canvas.R in classic and page_chat layouts:
#   restore  -- a saved canvas comes back, mounted and rendered
#   shielded -- the same with an active Data Shield
#   mismatch -- a canvas that no longer matches its conversation fails closed
#
# CODEAGENT_E2E_LIVE=1 adds one live case against the model configured by
# CODEAGENT_BASE_URL / CODEAGENT_MODEL / CODEAGENT_API_KEY (read from the
# environment, never printed): the model creates, updates and the user
# rewinds a canvas component.

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
fail <- function(...) stop(paste0(...), call. = FALSE)
assert <- function(ok, ...) if (!isTRUE(ok)) fail(...)

start_wd <- getwd()
if (file.exists(file.path(start_wd, "DESCRIPTION")) &&
    identical(readLines(file.path(start_wd, "DESCRIPTION"), n = 1L), "Package: codeagent"))
  fail("Run this driver from outside the codeagent source tree.")
for (p in c("codeagent", "shinygenui", "callr", "chromote", "httpuv", "jsonlite"))
  assert(requireNamespace(p, quietly = TRUE), "Missing package: ", p)
# This container's /dev/shm is 64 MB; without this flag Chromium's renderer
# crashes on desktop-width page_chat layouts (same setting as the upstream gate).
chromote::set_chrome_args(unique(c(chromote::default_chrome_args(),
                                   "--disable-dev-shm-usage", "--disable-background-networking",
                                   "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1")))
fixture <- system.file("examples", "test_genui_canvas.R", package = "codeagent")
assert(nzchar(fixture), "Installed codeagent lacks examples/test_genui_canvas.R; ",
       "install the current work tree first.")

wait_for_port <- function(proc, port, log_file, timeout_s = 150) {
  deadline <- Sys.time() + timeout_s
  repeat {
    if (!proc$is_alive())
      fail("App exited before readiness:\n",
           paste(tail(c(readLines(log_file, warn = FALSE),
                        readLines(paste0(log_file, ".stderr"), warn = FALSE)), 30L),
                 collapse = "\n"))
    con <- suppressWarnings(tryCatch(socketConnection(
      "127.0.0.1", port = port, open = "r+", blocking = TRUE, timeout = 0.2),
      error = function(e) NULL))
    if (!is.null(con)) { close(con); return(invisible(TRUE)) }
    if (Sys.time() > deadline) fail("Timed out waiting for port ", port)
    Sys.sleep(0.1)
  }
}

launch <- function(label, app_fun, args, env) {
  root <- file.path(tempdir(), paste0("genui-e2e-", label))
  unlink(root, recursive = TRUE)
  dir.create(file.path(root, "home"), recursive = TRUE)
  log_file <- file.path(root, "app.log")
  port <- httpuv::randomPort()
  env <- c(env, HOME = file.path(root, "home"), R_USER = file.path(root, "home"),
           CODEAGENT_HOME = file.path(root, "home", ".codeagent"),
           CODEAGENT_E2E_ROOT = root)
  proc <- callr::r_bg(app_fun, args = c(args, list(port = port)),
                      libpath = .libPaths(), stdout = log_file,
                      stderr = paste0(log_file, ".stderr"),
                      cmdargs = c("--vanilla", "--slave"),
                      env = env, supervise = TRUE, wd = root)
  wait_for_port(proc, port, log_file)
  list(proc = proc, port = port, log = log_file)
}

open_browser <- function(app) {
  b <- chromote::ChromoteSession$new()
  ev <- new.env(parent = emptyenv())
  ev$errors <- character(); ev$external <- character()
  url <- sprintf("http://127.0.0.1:%d", app$port)
  b$Runtime$enable(); b$Network$enable()
  b$Runtime$consoleAPICalled(callback_ = function(m) {
    if (!identical(m$type, "error")) return()
    ev$errors <- c(ev$errors, paste(vapply(m$args %||% list(), function(a)
      as.character(a$value %||% a$description %||% "")[[1L]], ""), collapse = " "))
  })
  b$Runtime$exceptionThrown(callback_ = function(m)
    ev$errors <- c(ev$errors, paste0("EXCEPTION: ",
      m$exceptionDetails$exception$description %||% m$exceptionDetails$text)))
  b$Log$enable()
  b$Log$entryAdded(callback_ = function(m) {
    if (identical(m$entry$level, "error") && !grepl("/favicon.ico$", m$entry$url %||% ""))
      ev$errors <- c(ev$errors, paste0("LOG: ", m$entry$text, " ", m$entry$url %||% ""))
  })
  b$Network$requestWillBeSent(callback_ = function(m) {
    u <- as.character(m$request$url %||% "")
    if (nzchar(u) && !startsWith(u, url) && !grepl("^(data|blob|about):", u))
      ev$external <- c(ev$external, u)
  })
  b$Emulation$setDeviceMetricsOverride(width = 1440L, height = 900L,
                                       deviceScaleFactor = 1, mobile = FALSE)
  b$Page$navigate(url = url)
  js <- function(expr) {
    r <- b$Runtime$evaluate(expression = expr, returnByValue = TRUE)
    if (!is.null(r$exceptionDetails)) fail("JS failed: ", r$exceptionDetails$text)
    r$result$value
  }
  wait <- function(label, pred, timeout_s = 60) {
    deadline <- Sys.time() + timeout_s
    repeat {
      if (!app$proc$is_alive()) fail("App exited while waiting for ", label)
      if (isTRUE(tryCatch(pred(), error = function(e) FALSE))) return(invisible())
      if (Sys.time() > deadline) fail("Timed out waiting for ", label)
      Sys.sleep(0.2)
    }
  }
  list(b = b, ev = ev, js = js, wait = wait)
}

count <- function(s, selector)
  s$js(sprintf("document.querySelectorAll(%s).length",
               jsonlite::toJSON(selector, auto_unbox = TRUE)))

shells <- function(s) count(s, "#ca_genui_canvas > .genui-shell")

common_checks <- function(s, label) {
  assert(count(s, "meta[http-equiv='Content-Security-Policy']") == 1L,
         label, ": CSP meta missing")
  assert(!length(s$ev$external), label, ": external browser requests: ",
         paste(unique(s$ev$external), collapse = ", "))
  assert(!length(s$ev$errors), label, ": browser errors: ",
         paste(unique(s$ev$errors), collapse = " | "))
}

fixture_app <- function(fixture, port) {
  app <- source(fixture, local = new.env())$value
  shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE,
                quiet = TRUE)
}

run_fixture <- function(case, layout) {
  label <- paste(case, layout, sep = "-")
  app <- launch(label, fixture_app, list(fixture = fixture),
                c(CODEAGENT_E2E_CASE = case, CODEAGENT_E2E_UI_LAYOUT = layout,
                  http_proxy = "http://127.0.0.1:9", https_proxy = "http://127.0.0.1:9",
                  NO_PROXY = "127.0.0.1,localhost"))
  on.exit(try(app$proc$kill(), silent = TRUE), add = TRUE)
  s <- open_browser(app)
  on.exit(try(s$b$close(), silent = TRUE), add = TRUE)
  s$wait("app ready", function() isTRUE(s$js(
    "!!window.Shiny && !!document.getElementById('ca_genui_canvas')")))
  s$wait("restored chat", function() grepl("E2E_ASSISTANT_DONE", s$js(
    "document.getElementById('chat') ? document.getElementById('chat').innerText : ''"),
    fixed = TRUE))
  s$js("(function(){var a=document.querySelector('a[data-value=\"canvas\"]');if(a)a.click();})()")
  if (identical(layout, "page_chat"))
    s$js("(function(){var b=document.getElementById('ca_workspace_toggle');if(b&&!document.querySelector('.shiny-chat-layout[data-drawer-open]'))b.click();})()")

  if (case %in% c("restore", "shielded")) {
    s$wait("two mounted components", function() shells(s) == 2L)
    s$wait("histogram rendered", function()
      count(s, "#ca_genui_c1-plot img") == 1L)
    s$wait("value box rendered", function()
      identical(s$js("(document.getElementById('ca_genui_c2-value')||{}).innerText||''"),
                format(max(mtcars$hp), big.mark = ",")))
    assert(grepl("E2E_HISTOGRAM_TITLE", s$js(
      "document.getElementById('ca_genui_canvas').innerText"), fixed = TRUE),
      label, ": histogram title missing")
    tab_visible <- s$js(
      "(function(){var a=document.querySelector('a[data-value=\"canvas\"]');return !!a && a.offsetParent!==null;})()")
    assert(isTRUE(tab_visible) || identical(layout, "page_chat"),
           label, ": Canvas tab not visible")
  } else {
    s$wait("fail-closed notice", function() grepl(
      "could not be safely restored", s$js("document.body.innerText"), fixed = TRUE))
    Sys.sleep(1)
    assert(shells(s) == 0L, label, ": partial canvas after a failed restore")
  }
  common_checks(s, label)
  cat("genui_e2e=PASS case=", label, "\n", sep = "")
}

live_app <- function(port) {
  # Credentials come from the user's own .Renviron (HOME is isolated here);
  # they are read into this process only and never printed.
  readRenviron(Sys.getenv("CODEAGENT_E2E_RENVIRON"))
  chat <- ellmer::chat_openai_compatible(
    base_url = Sys.getenv("CODEAGENT_BASE_URL"),
    model = Sys.getenv("CODEAGENT_MODEL"),
    credentials = function() Sys.getenv("CODEAGENT_API_KEY"))
  assign("e2e_cars", mtcars, envir = globalenv())
  app <- codeagent::codeagent_app(chat, permission_mode = "bypass",
                                  cwd = tempdir(), launch.browser = FALSE)
  shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE,
                quiet = TRUE)
}

send <- function(s, text) {
  s$js(sprintf("Shiny.setInputValue('chat_user_input', %s, {priority: 'event'})",
               jsonlite::toJSON(text, auto_unbox = TRUE)))
}

idle <- function(s) isTRUE(s$js(paste0(
  "(function(){var c=document.querySelector('shiny-chat-container [contenteditable]');",
  "return !!c && c.getAttribute('contenteditable')!=='false';})()")))

messages <- function(s) nchar(s$js("(document.getElementById('chat')||{}).innerText||''"))

# Send one message and wait for the turn to finish (input re-enabled).
turn <- function(s, text, timeout_s = 240) {
  before <- messages(s)
  send(s, text)
  s$wait(paste("turn finished:", text), function()
    messages(s) > before && idle(s), timeout_s = timeout_s)
  Sys.sleep(1)
}

canvas_text <- function(s) s$js(
  "(document.getElementById('ca_genui_canvas')||{}).innerText||''")

run_live <- function() {
  app <- launch("live", live_app, list(),
                c(CODEAGENT_E2E_RENVIRON = path.expand("~/.Renviron")))
  on.exit(try(app$proc$kill(), silent = TRUE), add = TRUE)
  s <- open_browser(app)
  on.exit(try(s$b$close(), silent = TRUE), add = TRUE)
  dump <- function(e) {
    cat("--- chat ---\n", substr(s$js("document.getElementById('chat').innerText"), 1, 4000),
        "\n--- canvas ---\n", canvas_text(s),
        "\n--- app stderr ---\n",
        paste(tail(readLines(paste0(app$log, ".stderr"), warn = FALSE), 40),
              collapse = "\n"), "\n", sep = "")
    stop(e)
  }
  withCallingHandlers({
    s$wait("app ready", function() isTRUE(s$js(paste0(
      "!!window.Shiny && !!document.getElementById('ca_genui_canvas') && ",
      "!(document.getElementById('ca_init_overlay')||{}).innerText"))) && idle(s),
      timeout_s = 180)
    Sys.sleep(3)
    s$wait("input enabled after initialization", function() idle(s))
    turn(s, paste("Put a histogram of the mpg column of the data frame e2e_cars",
                  "on the canvas. Use the canvas tool directly; do not run R code."))
    assert(shells(s) == 1L, "live: create did not mount exactly one component")
    s$wait("live plot", function() count(s, "#ca_genui_canvas .genui-shell img") >= 1L)
    turn(s, paste("Change that canvas histogram to show the hp column instead.",
                  "Update the existing component in place."))
    assert(shells(s) == 1L, "live: update did not keep exactly one component")
    assert(grepl("hp", canvas_text(s), ignore.case = TRUE),
           "live: the component was not updated to hp")
    # Each exchange above was user -> tool request -> tool result -> reply, so
    # rewinding two "exchanges" (four turns) drops exactly the update round.
    send(s, "/rewind 2")
    s$wait("rewind rolls the update back", function()
      shells(s) == 1L && grepl("mpg", canvas_text(s), ignore.case = TRUE),
      timeout_s = 60)
    send(s, "/clear")
    s$wait("clear empties the canvas", function() shells(s) == 0L, timeout_s = 60)
    common_checks(s, "live")
  }, error = dump)
  cat("genui_e2e=PASS case=live\n")
}

for (layout in strsplit(Sys.getenv("CODEAGENT_E2E_LAYOUTS", "classic,page_chat"), ",")[[1L]])
  for (case in c("restore", "shielded", "mismatch"))
    run_fixture(case, layout)
if (identical(Sys.getenv("CODEAGENT_E2E_LIVE"), "1")) run_live()
cat("genui_e2e=ALL_PASS\n")
