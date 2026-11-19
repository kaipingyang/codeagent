# Side-by-side UI comparison: real DSH Web UI vs codeagent, same mock model.
#
#   Rscript tools/dsh-compare/run.R scenarios=S1,S2 modes=light,dark \
#     ca_theme=dsh ca_layout=page_chat targets=dsh,ca label=step1
#
# Output: tools/dsh-compare/out/<label>/<scenario>-<mode>-{dsh,ca,pair}.png
# Needs: Node 24 with `dsh` installed globally, chromote, processx, magick.
# Nothing leaves 127.0.0.1; no real model, key or endpoint is used.

args <- commandArgs(trailingOnly = TRUE)
opt <- list(scenarios = "S1,S2,S3,S4,S5,S6,S8", modes = "light,dark", ca_theme = "dsh",
            ca_layout = "page_chat", targets = "dsh,ca", label = "latest",
            root = "/tmp/dsh-compare", verbose = "0", width = "1440", height = "900", keep = "0")
for (a in args) { kv <- strsplit(a, "=", fixed = TRUE)[[1]]; opt[[kv[1]]] <- paste(kv[-1], collapse = "=") }
split <- function(x) strsplit(x, ",", fixed = TRUE)[[1]]
here <- normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))))
node_bin <- "/home/kaiping.yang/.nvm/versions/node/v24.15.0/bin"
out_dir <- file.path(here, "out", opt$label); dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
root <- opt$root; project <- file.path(root, "project"); dsh_home <- file.path(root, "dsh-home")
targets <- split(opt$targets)

# -- fixture project ------------------------------------------------------------
dir.create(file.path(project, "R"), recursive = TRUE, showWarnings = FALSE)
writeLines(c("x <- 1:10", "mean(x)"), file.path(project, "R", "demo.R"))
writeLines(c("# Demo project", "", "A small project for UI screenshots."), file.path(project, "README.md"))

# -- services ---------------------------------------------------------------------
env_path <- paste(node_bin, Sys.getenv("PATH"), sep = ":")
wait_for <- function(f, what, tries = 60) {
  for (i in seq_len(tries)) { v <- tryCatch(f(), error = function(e) NULL); if (isTRUE(!is.null(v) && !identical(v, FALSE))) return(v); Sys.sleep(1) }
  stop("timed out waiting for ", what)
}
http_ok <- function(url) {
  h <- curl::new_handle(); curl::handle_setopt(h, timeout = 2)
  r <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) NULL)
  !is.null(r)
}
procs <- list()
on.exit(if (opt$keep != "1") for (p in procs) try(p$kill_tree(), silent = TRUE), add = TRUE)
# Leftovers of an interrupted run hold the ports. processx runs pkill without a
# shell, so no parent command line carries the pattern.
for (pat in c("dsh-compare/mock-llm.mjs", "dsh-compare/ca-app.R", "dsh web --no-open --port 3080"))
  try(processx::run("pkill", c("-f", pat), error_on_status = FALSE), silent = TRUE)
Sys.sleep(1)

mock_log <- file.path(root, "mock.log")
procs$mock <- processx::process$new(file.path(node_bin, "node"), file.path(here, "mock-llm.mjs"),
  env = c("current", MOCK_LOG = mock_log), stdout = file.path(root, "mock.out"), stderr = "2>&1")
wait_for(function() http_ok("http://127.0.0.1:18080/v1/models"), "mock model")

dsh_url <- NULL
if ("dsh" %in% targets) {
  start_dsh <- function() {
    lf <- file.path(root, "dsh-web.log"); unlink(lf)
    p <- processx::process$new(file.path(node_bin, "dsh"), c("web", "--no-open", "--port", "3080"),
      wd = project, env = c("current", PATH = env_path, DSH_HOME = dsh_home, MOCK_LLM_KEY = "mock"),
      stdout = lf, stderr = "2>&1")
    url <- wait_for(function() {
      if (!p$is_alive()) stop("dsh exited: ", paste(utils::tail(readLines(lf, warn = FALSE), 3), collapse = " | "))
      l <- if (file.exists(lf)) readLines(lf, warn = FALSE) else character()
      u <- regmatches(l, regexpr("http://127\\.0\\.0\\.1:[0-9]+/\\?token=[^ ]+", l))
      if (length(u)) u[[1]] else NULL
    }, "dsh web", tries = 300)
    list(p = p, url = url)
  }
  patch <- file.path(dsh_home, "profiles", "web", "cordis.patch.yml")
  if (!file.exists(patch) || !any(grepl("mock-model", readLines(patch, warn = FALSE)))) {
    s <- start_dsh(); s$p$kill_tree(); Sys.sleep(1)
    old <- readLines(patch, warn = FALSE); old <- old[!grepl("^\\[\\]\\s*$", old)]
    writeLines(c(old, "- id: llm-pi-ai", "  config:", "    providers:", "      mock:",
          "        apiKeyEnv: MOCK_LLM_KEY", "        api: openai-completions",
          "        baseURL: http://127.0.0.1:18080/v1", "        models:",
          "          - id: mock-model", "            name: Mock model"), patch)
  }
  s <- start_dsh(); procs$dsh <- s$p; dsh_url <- s$url
}

ca_url <- NULL
if ("ca" %in% targets) {
  ca_port <- 3990L
  procs$ca <- processx::process$new(file.path(R.home("bin"), "Rscript"), wd = project,
    c(file.path(here, "ca-app.R"), opt$ca_theme, opt$ca_layout, ca_port, project),
    # A throwaway HOME keeps the user's ~/.codeagent settings (model, permission
    # rules) out of the comparison; the libraries stay on R_LIBS_USER.
    env = c("current", HOME = file.path(root, "ca-user"),
            R_LIBS_USER = paste(.libPaths(), collapse = ":"),
            CODEAGENT_BASE_URL = "", CODEAGENT_MODEL = "mock-model"),
    stdout = file.path(root, "ca.log"), stderr = "2>&1")
  ca_url <- sprintf("http://127.0.0.1:%d/", ca_port)
  wait_for(function() http_ok(ca_url), "codeagent app", tries = 90)
}

# -- browser ------------------------------------------------------------------------
chromote::set_chrome_args(c(chromote::default_chrome_args(), "--disable-dev-shm-usage"))
lib <- paste(readLines(file.path(here, "lib.js"), warn = FALSE), collapse = "\n")
w <- as.integer(opt$width); h <- as.integer(opt$height)

session <- function() {
  b <- chromote::ChromoteSession$new(width = w, height = h)
  list(b = b,
       js = function(code) {
         r <- b$Runtime$evaluate(paste0(lib, "\n;", code), returnByValue = TRUE, awaitPromise = TRUE)
         if (!is.null(r$exceptionDetails)) return(paste("JS error:", r$exceptionDetails$exception$description))
         r$result$value
       })
}
act <- function(s, step) {
  v <- s$js(step)
  if (is.character(v) && length(v) == 1L) {
    if (startsWith(v, "@click ")) {
      xy <- as.numeric(strsplit(sub("@click ", "", v), ",")[[1]])
      for (t in c("mouseMoved", "mousePressed", "mouseReleased"))
        s$b$Input$dispatchMouseEvent(type = t, x = xy[1], y = xy[2], button = "left", clickCount = 1)
    } else if (startsWith(v, "@wheel ")) {
      xy <- as.numeric(strsplit(sub("@wheel ", "", v), ",")[[1]])
      s$b$Input$dispatchMouseEvent(type = "mouseWheel", x = xy[1], y = xy[2], deltaX = 0, deltaY = xy[3])
    } else if (startsWith(v, "@size ")) {
      wh <- as.numeric(strsplit(sub("@size ", "", v), ",")[[1]])
      s$b$Emulation$setDeviceMetricsOverride(width = wh[1], height = wh[2], deviceScaleFactor = 1, mobile = wh[1] < 700)
    } else if (startsWith(v, "@key ")) {
      k <- sub("@key ", "", v)
      for (t in c("keyDown", "keyUp")) s$b$Input$dispatchKeyEvent(type = t, key = k, code = k, windowsVirtualKeyCode = if (k == "Enter") 13 else 0)
    } else if (startsWith(v, "@text ")) {
      s$b$Input$insertText(text = sub("@text ", "", v))
    }
  }
  v
}
sleep_js <- function(sec) sprintf("new Promise(r => setTimeout(() => r('waited'), %d))", as.integer(sec * 1000))
shoot <- function(s, file) {
  x <- s$b$Page$captureScreenshot(format = "png")
  writeBin(jsonlite::base64_dec(x$data), file)
}

source(file.path(here, "scenarios.R"), local = TRUE)

modes <- split(opt$modes)
for (sc in split(opt$scenarios)) for (mode in modes) {
  files <- character()
  for (tg in targets) {
    s <- session()
    url <- if (tg == "dsh") dsh_url else ca_url
    invisible(s$b$Page$navigate(url)); Sys.sleep(if (tg == "dsh") 8 else 10)
    steps <- c(prepare[[tg]](mode), scenario_steps[[sc]][[tg]])
    for (st in steps) { v <- act(s, st); if (opt$verbose == "1") cat("  ", substr(paste(v, collapse = " "), 1, 1500), "\n"); Sys.sleep(1.2) }
    f <- file.path(out_dir, sprintf("%s-%s-%s.png", sc, mode, tg))
    shoot(s, f); files <- c(files, f)
    cat(sc, mode, tg, "->", basename(f), "\n")
    s$b$close()
  }
  if (length(files) == 2L) {
    imgs <- lapply(files, function(f) magick::image_annotate(magick::image_read(f),
      if (grepl("-dsh\\.png$", f)) "DSH" else paste("codeagent:", opt$ca_theme, opt$ca_layout),
      size = 18, color = "#d33", boxcolor = "#ffffffcc", location = "+8+8"))
    pair <- magick::image_append(c(imgs[[1]], magick::image_blank(12, magick::image_info(imgs[[1]])$height, "#888"), imgs[[2]]))
    magick::image_write(pair, file.path(out_dir, sprintf("%s-%s-pair.png", sc, mode)))
  }
}
cat("done:", out_dir, "\n")
