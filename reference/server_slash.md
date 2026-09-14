# Official shinychat slash-command typeahead (standalone driver)

Drives shinychat's **official** slash-command typeahead palette (dev
feature \#239: the native `/`-triggered command menu) WITHOUT using
[`shinychat::chat_server()`](https://posit-dev.github.io/shinychat/r/reference/chat_app.html).

codeagent owns its own streaming
([`server_chat()`](https://kaipingyang.github.io/codeagent/reference/server_chat.md) +
`stream_task`), so it cannot adopt `chat_server()` (whose input observer
would double-stream every message alongside codeagent's harness – see
`lessons/2026-07-03-shiny-async-interaction.md`). shinychat has no
public standalone `register_slash_command()` yet (upstream TODO), so we
speak its client protocol directly:

- **Register**: send `{type: "update_slash_commands", commands: [...]}`
  via the `shinyChatMessage` custom message (same envelope shinychat's
  `send_chat_action()` uses). Each command is
  `{name, description, echo}`.

- **Select**: the client sends
  `input$<id>_slash_command = {command, userText}`. We reconstruct
  `/command args` and submit it through the normal input via
  `update_chat_user_input(submit = TRUE)`, so all routing stays in the
  one place (`server_chat` -\> `.preprocess_input`): local commands are
  handled client-of-LLM, skills inject their prompt, etc.

Graceful degradation: on a shinychat build without the typeahead, the
registration message is simply ignored and the footer `pickerInput`
remains as the fallback slash UI. REPL is unaffected (uses
`.preprocess_input`).
