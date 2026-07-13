# Package index

## Core Client

Create and run the agent.

- [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
  : Create a codeagent client from any ellmer Chat

- [`codeagent_client_config()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client_config.md)
  :

  Reads `codeagent.md` or `.codeagent/config.md` in the project
  directory and constructs a
  [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
  from the declared settings. Supports multi-client aliases (pick
  interactively or by name).

- [`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
  : Run a one-shot codeagent query

- [`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md)
  : Main agentic query loop

- [`use_codeagent_settings()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_settings.md)
  : Create a codeagent settings.json file

- [`use_codeagent_setup()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_setup.md)
  : Interactive setup wizard for codeagent

## Shiny App

Interactive chat interface.

- [`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
  : Launch the codeagent Shiny application

## IDE Addins

RStudio / Positron keyboard-shortcut integration.

- [`codeagent_addin()`](https://kaipingyang.github.io/codeagent/reference/codeagent_addin.md)
  : Open the codeagent Shiny app from an IDE addin
- [`codeagent_addin_selection()`](https://kaipingyang.github.io/codeagent/reference/codeagent_addin_selection.md)
  : Open codeagent with the current editor selection as context

## CLI

Terminal REPL and command-line interface.

- [`codeagent_console()`](https://kaipingyang.github.io/codeagent/reference/codeagent_console.md)
  : Run the interactive REPL
- [`install_codeagent_cli()`](https://kaipingyang.github.io/codeagent/reference/install_codeagent_cli.md)
  : Install the codeagent CLI

## Core tools

Built-in tool factories registered on the Chat.

- [`bash_tool()`](https://kaipingyang.github.io/codeagent/reference/bash_tool.md)
  : Create the Bash tool
- [`read_tool()`](https://kaipingyang.github.io/codeagent/reference/read_tool.md)
  : Create the Read tool
- [`write_tool()`](https://kaipingyang.github.io/codeagent/reference/write_tool.md)
  : Create the Write tool
- [`edit_tool()`](https://kaipingyang.github.io/codeagent/reference/edit_tool.md)
  : Create the Edit tool
- [`multi_edit_tool()`](https://kaipingyang.github.io/codeagent/reference/multi_edit_tool.md)
  : Create the MultiEdit tool
- [`glob_tool()`](https://kaipingyang.github.io/codeagent/reference/glob_tool.md)
  : Create the Glob tool
- [`grep_tool()`](https://kaipingyang.github.io/codeagent/reference/grep_tool.md)
  : Create the Grep tool
- [`ls_tool()`](https://kaipingyang.github.io/codeagent/reference/ls_tool.md)
  : Create the LS tool
- [`run_r_tool()`](https://kaipingyang.github.io/codeagent/reference/run_r_tool.md)
  : Create the RunR tool
- [`explore_data_tool()`](https://kaipingyang.github.io/codeagent/reference/explore_data_tool.md)
  : Create the ExploreData tool
- [`register_builtin_tools()`](https://kaipingyang.github.io/codeagent/reference/register_builtin_tools.md)
  : Register all built-in codeagent tools to a Chat
- [`register_explore_data_tool()`](https://kaipingyang.github.io/codeagent/reference/register_explore_data_tool.md)
  : Register the ExploreData tool on a Chat

## Permissions

Seven-mode permission gate and rule system.

- [`check_permission()`](https://kaipingyang.github.io/codeagent/reference/check_permission.md)
  : Check whether a tool call is permitted
- [`PermissionMode`](https://kaipingyang.github.io/codeagent/reference/PermissionMode.md)
  : Permission modes for codeagent
- [`PermissionRule()`](https://kaipingyang.github.io/codeagent/reference/PermissionRule.md)
  : Create a permission rule

## Session Management

Save, load, and navigate conversation history.

- [`list_sessions()`](https://kaipingyang.github.io/codeagent/reference/list_sessions.md)
  : List codeagent sessions
- [`save_session()`](https://kaipingyang.github.io/codeagent/reference/save_session.md)
  : Save an ellmer Chat session to disk
- [`restore_session_into_chat()`](https://kaipingyang.github.io/codeagent/reference/restore_session_into_chat.md)
  : Restore a saved session's messages into a Chat object
- [`get_session_messages()`](https://kaipingyang.github.io/codeagent/reference/get_session_messages.md)
  : Get messages from a session
- [`fork_session()`](https://kaipingyang.github.io/codeagent/reference/fork_session.md)
  : Fork a session
- [`rename_session()`](https://kaipingyang.github.io/codeagent/reference/rename_session.md)
  : Rename a session
- [`tag_session()`](https://kaipingyang.github.io/codeagent/reference/tag_session.md)
  : Tag a session
- [`truncate_chat_turns()`](https://kaipingyang.github.io/codeagent/reference/truncate_chat_turns.md)
  : Rewind a chat to an earlier point in the conversation

## Memory

Persistent cross-session memory.

- [`write_memory()`](https://kaipingyang.github.io/codeagent/reference/write_memory.md)
  : Write a memory to disk
- [`list_memories()`](https://kaipingyang.github.io/codeagent/reference/list_memories.md)
  : List stored memories (parsed front-matter + body)
- [`recall_memories()`](https://kaipingyang.github.io/codeagent/reference/recall_memories.md)
  : Recall memories as a compact block for system-reminder injection
- [`recall_memories_relevant()`](https://kaipingyang.github.io/codeagent/reference/recall_memories_relevant.md)
  : Recall only the memories relevant to a query (haiku-selected)
- [`delete_memory()`](https://kaipingyang.github.io/codeagent/reference/delete_memory.md)
  : Delete a memory by slug
- [`read_todos()`](https://kaipingyang.github.io/codeagent/reference/read_todos.md)
  : Read the current todo list for a session

## Multi-Agent Teams

Parallel agent coordination.

- [`team_run()`](https://kaipingyang.github.io/codeagent/reference/team_run.md)
  : Run a set of independent tasks as a parallel agent team
- [`team_coordinate()`](https://kaipingyang.github.io/codeagent/reference/team_coordinate.md)
  : Coordinate a team of agents over a shared task board
- [`board_create()`](https://kaipingyang.github.io/codeagent/reference/board_create.md)
  : Create a new shared task board
- [`board_add_task()`](https://kaipingyang.github.io/codeagent/reference/board_add_task.md)
  : Add a task to the board
- [`board_claim()`](https://kaipingyang.github.io/codeagent/reference/board_claim.md)
  : Atomically claim the next claimable task (dependency-aware)
- [`board_complete()`](https://kaipingyang.github.io/codeagent/reference/board_complete.md)
  : Mark a claimed task complete with its result
- [`board_status()`](https://kaipingyang.github.io/codeagent/reference/board_status.md)
  : Read the full board state
- [`board_send_message()`](https://kaipingyang.github.io/codeagent/reference/board_send_message.md)
  : Post a message to the team message log
- [`board_messages()`](https://kaipingyang.github.io/codeagent/reference/board_messages.md)
  : Read messages from the team message log
- [`team_lead()`](https://kaipingyang.github.io/codeagent/reference/team_lead.md)
  : LLM-lead autonomous coordinator
- [`team_dashboard()`](https://kaipingyang.github.io/codeagent/reference/team_dashboard.md)
  : Live team-board dashboard
- [`board_reclaim_stale()`](https://kaipingyang.github.io/codeagent/reference/board_reclaim_stale.md)
  : Reclaim tasks whose worker died mid-flight
- [`board_watch()`](https://kaipingyang.github.io/codeagent/reference/board_watch.md)
  : Watch a task board for changes (event-driven coordinator engine)

## Skills

Skill discovery and loading.

- [`list_skills_meta()`](https://kaipingyang.github.io/codeagent/reference/list_skills_meta.md)
  : List skill metadata from all skill directories
- [`load_skill_prompt()`](https://kaipingyang.github.io/codeagent/reference/load_skill_prompt.md)
  : Load a skill's full prompt
- [`build_skill_hint()`](https://kaipingyang.github.io/codeagent/reference/build_skill_hint.md)
  : Build skill hint for system prompt
- [`install_ds_skills()`](https://kaipingyang.github.io/codeagent/reference/install_ds_skills.md)
  : Install Posit's data-science skill collection (posit-dev/skills)

## MCP

Model Context Protocol client and server.

- [`codeagent_mcp_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mcp_server.md)
  :

  Exposes codeagent's tool set as an MCP server. By default uses btw's
  `btw_mcp_server()` over stdio (for Claude Desktop / VS Code MCP
  config). With `transport = "http"` it serves over HTTP via
  [`mcptools::mcp_server()`](https://posit-dev.github.io/mcptools/reference/server.html)
  (\>= 0.2.1), enabling remote MCP clients. The server runs in a
  blocking loop.

- [`register_mcp_client()`](https://kaipingyang.github.io/codeagent/reference/register_mcp_client.md)
  : Register external MCP server tools onto a Chat

- [`r_mcp_server()`](https://kaipingyang.github.io/codeagent/reference/r_mcp_server.md)
  : Create an R-based MCP server entry

## RAG

Codebase semantic retrieval.

- [`build_codebase_store()`](https://kaipingyang.github.io/codeagent/reference/build_codebase_store.md)
  : Build (or rebuild) a codebase vector store
- [`register_rag_tool()`](https://kaipingyang.github.io/codeagent/reference/register_rag_tool.md)
  : Register a codebase retrieval tool on a chat

## Hooks

Lifecycle event hooks.

- [`HookRegistry`](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  : Tool hook registry
- [`HookEvent`](https://kaipingyang.github.io/codeagent/reference/HookEvent.md)
  : Hook event types

## Utilities

Miscellaneous helpers.

- [`switch_model()`](https://kaipingyang.github.io/codeagent/reference/switch_model.md)
  : Switch the active model on a CodeagentClient, preserving history
- [`verify_r_tests()`](https://kaipingyang.github.io/codeagent/reference/verify_r_tests.md)
  : R package test verification function
- [`verify_r_lints()`](https://kaipingyang.github.io/codeagent/reference/verify_r_lints.md)
  : Lint-based verification function
- [`codeagent_otel_status()`](https://kaipingyang.github.io/codeagent/reference/codeagent_otel_status.md)
  : Report OpenTelemetry observability status for codeagent
- [`use_codeagent_md()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_md.md)
  : Create a codeagent.md configuration file

## Additional tools & registration

Tool factories and registration.

- [`agent_tool()`](https://kaipingyang.github.io/codeagent/reference/agent_tool.md)
  : Create the Agent tool
- [`ask_user_tool()`](https://kaipingyang.github.io/codeagent/reference/ask_user_tool.md)
  : Create the AskUserQuestion tool
- [`notebook_edit_tool()`](https://kaipingyang.github.io/codeagent/reference/notebook_edit_tool.md)
  : Create the NotebookEdit tool
- [`notebook_read_tool()`](https://kaipingyang.github.io/codeagent/reference/notebook_read_tool.md)
  : Create the NotebookRead tool
- [`todo_write_tool()`](https://kaipingyang.github.io/codeagent/reference/todo_write_tool.md)
  : Create the TodoWrite tool
- [`web_fetch_tool()`](https://kaipingyang.github.io/codeagent/reference/web_fetch_tool.md)
  : Create the WebFetch tool
- [`web_search_tool()`](https://kaipingyang.github.io/codeagent/reference/web_search_tool.md)
  : Create the WebSearch tool
- [`register_agent_tool()`](https://kaipingyang.github.io/codeagent/reference/register_agent_tool.md)
  : Register the Agent tool and any btw custom agent tools
- [`register_ask_user_tool()`](https://kaipingyang.github.io/codeagent/reference/register_ask_user_tool.md)
  : Register the AskUserQuestion tool on a Chat
- [`register_btw_file_tools()`](https://kaipingyang.github.io/codeagent/reference/register_btw_file_tools.md)
  : Register btw file tools with permission control
- [`register_notebook_tools()`](https://kaipingyang.github.io/codeagent/reference/register_notebook_tools.md)
  : Register notebook tools to an ellmer Chat object
- [`register_r_tools()`](https://kaipingyang.github.io/codeagent/reference/register_r_tools.md)
  : Register btw R-environment tools to an ellmer Chat object
- [`register_task_tools()`](https://kaipingyang.github.io/codeagent/reference/register_task_tools.md)
  : Register task management tools to an ellmer Chat object
- [`register_web_tools()`](https://kaipingyang.github.io/codeagent/reference/register_web_tools.md)
  : Register web tools to an ellmer Chat object
- [`enable_btw_file_tools()`](https://kaipingyang.github.io/codeagent/reference/enable_btw_file_tools.md)
  : Patch codeagent_client() to use btw file tools (Path A)

## Data exploration (WEAR)

Interactive data exploration and reporting.

- [`wear_explore()`](https://kaipingyang.github.io/codeagent/reference/wear_explore.md)
  : Start a WEAR loop data exploration session
- [`generate_wear_report()`](https://kaipingyang.github.io/codeagent/reference/generate_wear_report.md)
  : Export the current WEAR exploration session to a Quarto document

## Sessions & settings

Session storage and settings helpers.

- [`delete_session()`](https://kaipingyang.github.io/codeagent/reference/delete_session.md)
  : Delete a session
- [`get_session_info()`](https://kaipingyang.github.io/codeagent/reference/get_session_info.md)
  : Get metadata for a single session
- [`migrate_sessions()`](https://kaipingyang.github.io/codeagent/reference/migrate_sessions.md)
  : Migrate legacy session files to the current format version
- [`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md)
  : Load codeagent settings
- [`save_user_settings()`](https://kaipingyang.github.io/codeagent/reference/save_user_settings.md)
  : Save user settings to ~/.codeagent/settings.json
- [`migrate_config_dir()`](https://kaipingyang.github.io/codeagent/reference/migrate_config_dir.md)
  : Migrate the codeagent config directory to the OS-standard location

## Harness internals

R6 controllers and content/permission types (advanced).

- [`BudgetTracker`](https://kaipingyang.github.io/codeagent/reference/BudgetTracker.md)
  : Token budget tracker
- [`CompactionController`](https://kaipingyang.github.io/codeagent/reference/CompactionController.md)
  : Context compaction controller
- [`ContentReplacementState`](https://kaipingyang.github.io/codeagent/reference/ContentReplacementState.md)
  : Global context budget manager (Layer 3)
- [`DenialTracker`](https://kaipingyang.github.io/codeagent/reference/DenialTracker.md)
  : Track permission denials and emit warnings at thresholds
- [`StreamingToolExecutor`](https://kaipingyang.github.io/codeagent/reference/StreamingToolExecutor.md)
  : Concurrent tool execution scheduler
- [`PreToolHook()`](https://kaipingyang.github.io/codeagent/reference/PreToolHook.md)
  : Pre-tool hook definition
- [`PostToolHook()`](https://kaipingyang.github.io/codeagent/reference/PostToolHook.md)
  : Post-tool hook definition
- [`PermissionResultAllow()`](https://kaipingyang.github.io/codeagent/reference/PermissionResultAllow.md)
  : Allow a tool call
- [`PermissionResultDeny()`](https://kaipingyang.github.io/codeagent/reference/PermissionResultDeny.md)
  : Deny a tool call
- [`TextBlock()`](https://kaipingyang.github.io/codeagent/reference/TextBlock.md)
  : Create a TextBlock
- [`ThinkingBlock()`](https://kaipingyang.github.io/codeagent/reference/ThinkingBlock.md)
  : Create a ThinkingBlock
- [`ToolResultBlock()`](https://kaipingyang.github.io/codeagent/reference/ToolResultBlock.md)
  : Create a ToolResultBlock
- [`ToolUseBlock()`](https://kaipingyang.github.io/codeagent/reference/ToolUseBlock.md)
  : Create a ToolUseBlock

## Streaming

Per-turn streaming primitives with typed content callbacks.

- [`codeagent_stream()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream.md)
  : Stream one agent turn synchronously (CLI / ink)
- [`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md)
  : Stream one agent turn asynchronously

## Guided tasks

One-shot guided workflows (reuse btw tasks).

- [`codeagent_task()`](https://kaipingyang.github.io/codeagent/reference/codeagent_task.md)
  : Run a btw task with a codeagent client (reuse, not reinvent)
- [`codeagent_create_skill()`](https://kaipingyang.github.io/codeagent/reference/codeagent_create_skill.md)
  : Create a skill via btw's guided task (reuse)
- [`codeagent_create_readme()`](https://kaipingyang.github.io/codeagent/reference/codeagent_create_readme.md)
  : Create a polished README via btw's guided task (reuse)
- [`codeagent_init_context()`](https://kaipingyang.github.io/codeagent/reference/codeagent_init_context.md)
  : Initialise a project-context file (btw.md) via btw's guided task
  (reuse)
