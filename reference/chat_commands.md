# Local (slash) command dispatch – pure decision layer

`.chat_command_result()` decides *what* a local `/command` should do
given a handful of read-only facts, and returns a plain description
(`list(action, feedback, ...)`). It performs **no** side effects: no
chat mutation, no I/O, no Shiny calls. The Shiny handler
(`.handle_chat_command`, server_chat.R) gathers the facts, calls this,
then applies the effects (append message, show modal, truncate turns,
compact). Keeping the decision pure makes every command's logic
unit-testable without a running app – see
`tests/testthat/test-chat-commands.R`.
