# Launch the codeagent Shiny application

Launch the codeagent Shiny application

## Usage

``` r
codeagent_app(
  client = NULL,
  client_factory = NULL,
  theme = "default",
  pinned_skills = character(0),
  greeting = NULL,
  port = NULL,
  launch.browser = TRUE,
  file_tree_show_hidden = FALSE,
  file_tree_exclude = c("renv", "node_modules", "packrat", ".git", ".Rproj.user"),
  chat_submit_key = c("enter", "enter+modifier"),
  model = NULL,
  permission_mode = "default",
  cwd = getwd(),
  btw_groups = NULL,
  chat = NULL,
  web_citations = c("off", "shiny_aside"),
  web_allow_private = FALSE,
  ui_layout = c("classic", "page_chat")
)
```

## Arguments

- client:

  A pre-built `CodeagentClient` (single-user compatibility) or, for
  backward compatibility, an
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  template (cloned per Shiny session). Prefer `chat=` for the template
  form.

- client_factory:

  Optional `function(session)` (or zero-argument function) returning a
  fresh `CodeagentClient` for each Shiny session. This is the most
  flexible multi-user mode.

- theme:

  UI theme. One of `"default"` (light Bootstrap 5), `"flatly"`,
  `"darkly"` (dark), or `"glass"` (dark glassmorphism). The CLI aliases
  `"light"` -\> `"default"`, `"dark"` -\> `"darkly"`, and
  `"glassmorphism"` -\> `"glass"` are also accepted. Set at launch; the
  live dark-mode toggle in the sidebar still flips light/dark on top of
  the chosen theme.

- pinned_skills:

  Character vector. Retained for backward compatibility; the old Skills
  picker panel was replaced by the slash-command typeahead (type `/` in
  the chat input), so this argument is currently unused.

- greeting:

  Character or NULL. If provided, pre-fills the chat input box with this
  text on startup (used by the "Chat about selection" IDE addin to seed
  the first message with the selected code). NULL leaves the input
  empty.

- port:

  Integer or NULL. Shiny port (NULL = random).

- launch.browser:

  Logical. Open in browser (default TRUE).

- file_tree_show_hidden:

  Logical. Show hidden dotfiles (e.g. `.git`, `.codegraph`) in the file
  tree. Default `FALSE` to reduce clutter/lag.

- file_tree_exclude:

  Character vector. Directory names excluded from the file tree (default
  `renv`, `node_modules`, `packrat`, `.git`, `.Rproj.user`). Set
  `character(0)` to disable exclusion.

- chat_submit_key:

  How the chat input submits: `"enter"` (default, Enter sends,
  Shift/Ctrl+Enter inserts a newline) or `"enter+modifier"`
  (Ctrl/Cmd+Enter sends, plain Enter inserts a newline – friendlier for
  long multi-line prompts). Set at launch; not switchable live.

- model:

  Character. Legacy: model name.

- permission_mode:

  Character. Legacy: permission mode.

- cwd:

  Character. Legacy: working directory.

- btw_groups:

  Character vector or NULL. Legacy: btw tool groups.

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  template cloned inside each Shiny session; convenient multi-user entry
  point.

- web_citations:

  Citation presentation mode: `"off"` (default) or `"shiny_aside"` for
  the deterministic current-turn `[[cite:SOURCE_ID|claim]]` bridge.
  Logical `TRUE`/`FALSE` remains accepted for compatibility. Enabled
  replies are buffered and validated before any `<shiny-aside>` markup
  is built server-side.

- web_allow_private:

  Logical. Reserved opt-in for local development. Private-network
  fetching remains disabled in this release; `TRUE` fails closed rather
  than weakening SSRF protection.

- ui_layout:

  UI shell. `"classic"` (default) preserves the existing three-column
  layout. `"page_chat"` opts into shinychat's full-window page with
  codeagent controls on the left and the Output/Files/File workspace in
  the official resizable drawer on the right.

## Value

A `shiny.appobj`.
