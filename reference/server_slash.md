# Official shinychat slash-command typeahead (standalone driver)

Drives shinychat's **official** slash-command typeahead palette (dev
feature \#239: the native `/`-triggered command menu) WITHOUT using
`shinychat::chat_server()`.

codeagent owns its own streaming (`server_chat()` + `stream_task`), so
it cannot adopt `chat_server()` (whose input observer would
double-stream every message alongside codeagent's harness – see
`lessons/2026-07-03-shiny-async-interaction.md`). shinychat has no
public standalone `register_slash_command()` yet (upstream TODO), so we
speak its client protocol directly:

  - **Register**: send `{type: "update_slash_commands", commands:
    [...]}` via the `shinyChatMessage` custom message (same envelope
    shinychat's `send_chat_action()` uses). Each command is `{name,
    description, echo}`.

  - **Select**: the client sends `input$<id>_slash_command = {command,
    userText}`. We reconstruct `/command args` and submit it through the
    normal input via `update_chat_user_input(submit = TRUE)`, so all
    routing stays in the one place (`server_chat` -\>
    `.preprocess_input`): local commands are handled client-of-LLM,
    skills inject their prompt, etc.

Graceful degradation: on a shinychat build without the typeahead, the
registration message is simply ignored and the footer `pickerInput`
remains as the fallback slash UI. REPL is unaffected (uses
`.preprocess_input`).

## Usage

``` r
server_slash(
  input,
  session,
  cwd = getwd(),
  id = "chat",
  stream_task = NULL,
  chat = NULL,
  settings = NULL,
  state = NULL
)
```

## Arguments

  - input, session:
    
    Standard Shiny server args.

  - cwd:
    
    Character. Working directory (for skill discovery).

  - id:
    
    Character. The `chat_ui()` id (default `"chat"`).

  - stream\_task:
    
    The `ExtendedTask` returned by `server_chat()`, used to run
    skill/normal slash commands through the harness (compaction, skill
    injection, streaming). Required for skill commands to reach the LLM.

  - chat, settings, state:
    
    Harness handles for executing local commands directly (via
    `.handle_chat_command()`).

## Value

Invisibly NULL.

## Details

Slash commands are dispatched **directly inside this handler** — we do
NOT re-submit `/command` through `update_chat_user_input()`.
Re-submitting is broken: shinychat re-recognises the re-submitted
`/command` as a slash command and fires `input$<id>_slash_command` again
with the *same* value, which Shiny's `observeEvent` de-dupes into a
no-op — so the command never reaches `input$<id>_user_input` /
`.preprocess_input` and silently dies. Instead we mirror `server_chat`'s
routing here: local commands run via `.handle_chat_command()`,
skills/normal go through the shared `stream_task` (which injects the
skill prompt internally).
