# Scenario steps for run.R. Each step is JavaScript evaluated in the page with the
# helpers from lib.js; a returned "@click x,y" / "@wheel x,y,dy" / "@size w,h" /
# "@key K" / "@text T" string becomes a real CDP input event.
# `prepare[[target]](mode)` runs first in every scenario (first-run dialogs, theme).

W <- function(sec) sleep_js(sec)

# --- DSH ---------------------------------------------------------------------------
dsh_theme <- function(mode) c("__d.waitAt('Account menu')", "__d.waitAt('Settings')",
                             sprintf("__d.waitAt('%s')", if (mode == "dark") "Dark" else "Light"),
                             "__d.at('Close')")
dsh_new <- "(() => document.body.innerText.includes('Into the Unknown') ? 'hero' : __d.at('New session in project'))()"
dsh_send <- function(text) c(
  sprintf("__d.type(document.querySelector('[contenteditable=true]'), %s)", deparse(text)),
  "__d.at('Send message')", W(2),
  "(() => document.body.innerText.includes('Into the Unknown') ? __d.at('Summary of R/demo.R') : 'in session')()")

prepare <- list()
dsh_dialog <- "document.body.innerText.includes('Select Workspace Directory')"
prepare$dsh <- function(mode) c(
  # first run in a fresh browser profile: preview notice, sign-in prompt
  "__d.waitAt('Continue', 8000)", "__d.waitAt('Close', 4000)",
  # workspace (fresh DSH_HOME only)
  "(() => document.body.innerText.includes('Choose a workspace') ? __d.at('Choose workspace') : 'ws ok')()",
  sprintf("(() => %s ? __d.at('Edit path') : 'no dialog')()", dsh_dialog),
  sprintf("(() => { const e = document.querySelector('input[aria-label=\"Edit path\"]'); if (!e) return 'no path input'; __d.type(e, %s); __d.enter(e); return 'path' })()", deparse(project)),
  sprintf("(() => %s ? __d.waitAt('Open', 3000) : 'no dialog')()", dsh_dialog),
  "__d.waitAt('Close', 2000)",
  "__d.waitAt('Select model', 3000)",
  "(() => [...document.querySelectorAll('body *')].some(e => e.offsetParent && e.innerText === 'Mock model') ? __d.at('Mock model') : 'no menu')()",
  dsh_theme(mode),
  dsh_new)

# --- codeagent -----------------------------------------------------------------------
ca_input <- "(document.querySelector('shiny-chat-input textarea, shiny-chat-container textarea, [contenteditable=true]'))"
ca_send <- function(text) c(
  sprintf("(() => { const e = %s; if (!e) return 'no input'; e.focus(); return 'focus' })()", ca_input),
  paste0("'@text ", text, "'"),
  "'@key Enter'")
prepare$ca <- function(mode) c(
  W(4),
  sprintf("(() => { document.documentElement.setAttribute('data-bs-theme', '%s'); return 'theme' })()", mode))

# --- scenarios -----------------------------------------------------------------------
scenario_steps <- list(
  P = list(dsh = "__d.list()", ca = "__d.list() + ' || ' + __d.inputs()"),
  S1 = list(dsh = W(1), ca = W(1)),
  S2 = list(dsh = c(dsh_send("Explain R/demo.R and summarise it in a table"), W(8), "'@wheel 856,400,-3000'"),
            ca  = c(ca_send("Explain R/demo.R and summarise it in a table"), W(8))),
  S3 = list(dsh = c(dsh_send("Explain R/demo.R and summarise it in a table"), W(8), "'@wheel 856,400,-3000'",
                    "__d.at('Completed in 1s')", "__d.at('Read files')"),
            ca  = c(ca_send("Explain R/demo.R and summarise it in a table"), W(8),
                    "(() => { const s = document.querySelector('shiny-tool-result summary, .shiny-tool-card summary, details summary'); if (!s) return 'no tool'; s.click(); return 'open' })()")),
  S4 = list(dsh = c(dsh_send("Use bash to run the summary"), W(7)),
            ca  = c(ca_send("Use bash to run the summary"), W(7))),
  S5 = list(dsh = c(dsh_send("Please ask me which format to use"), W(7)),
            ca  = c(ca_send("Please ask me which format to use"), W(7))),
  S6 = list(dsh = c(dsh_send("Explain R/demo.R and summarise it in a table"), W(8),
                    "__d.at('Open right sidebar')", "__d.at('Workspace files')", "__d.at('R')", "__d.at('demo.R')"),
            ca  = c(ca_send("Explain R/demo.R and summarise it in a table"), W(8))),
  S8 = list(dsh = c(dsh_send("Explain R/demo.R and summarise it in a table"), W(8), "'@size 760,900'"),
            ca  = c(ca_send("Explain R/demo.R and summarise it in a table"), W(8), "'@size 760,900'"))
)
