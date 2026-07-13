# Launch the codeagent Shiny application

Launch the codeagent Shiny application

## Usage

``` r
codeagent_app(
  client = NULL,
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
  chat = NULL
)
```

## Arguments

  - client:
    
    A `CodeagentClient` from `codeagent_client()`, an `ellmer::Chat`, or
    NULL (legacy mode).

  - theme:
    
    UI theme. One of `"default"` (light Bootstrap 5), `"flatly"`,
    `"darkly"` (dark), or `"glass"` (dark glassmorphism). The CLI
    aliases `"light"` -\> `"default"`, `"dark"` -\> `"darkly"`, and
    `"glassmorphism"` -\> `"glass"` are also accepted. Set at launch;
    the live dark-mode toggle in the sidebar still flips light/dark on
    top of the chosen theme.

  - pinned\_skills:
    
    Character vector. Retained for backward compatibility; the old
    Skills picker panel was replaced by the slash-command typeahead
    (type `/` in the chat input), so this argument is currently unused.

  - greeting:
    
    Character or NULL. If provided, pre-fills the chat input box with
    this text on startup (used by the "Chat about selection" IDE addin
    to seed the first message with the selected code). NULL leaves the
    input empty.

  - port:
    
    Integer or NULL. Shiny port (NULL = random).

  - launch.browser:
    
    Logical. Open in browser (default TRUE).

  - file\_tree\_show\_hidden:
    
    Logical. Show hidden dotfiles (e.g. `.git`, `.codegraph`) in the
    file tree. Default `FALSE` to reduce clutter/lag.

  - file\_tree\_exclude:
    
    Character vector. Directory names excluded from the file tree
    (default `renv`, `node_modules`, `packrat`, `.git`, `.Rproj.user`).
    Set `character(0)` to disable exclusion.

  - chat\_submit\_key:
    
    How the chat input submits: `"enter"` (default, Enter sends,
    Shift/Ctrl+Enter inserts a newline) or `"enter+modifier"`
    (Ctrl/Cmd+Enter sends, plain Enter inserts a newline – friendlier
    for long multi-line prompts). Set at launch; not switchable live.

  - model:
    
    Character. Legacy: model name.

  - permission\_mode:
    
    Character. Legacy: permission mode.

  - cwd:
    
    Character. Legacy: working directory.

  - btw\_groups:
    
    Character vector or NULL. Legacy: btw tool groups.

  - chat:
    
    An `ellmer::Chat`. Legacy alias.

## Value

A `shiny.appobj`.
