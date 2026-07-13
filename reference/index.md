# Package index

## Core Client

Create and run the agent.

<!-- end list -->

  - `codeagent_client()` : Create a codeagent client from any ellmer
    Chat

  - `codeagent_client_config()` :
    
    Reads `codeagent.md` or `.codeagent/config.md` in the project
    directory and constructs a `codeagent_client()` from the declared
    settings. Supports multi-client aliases (pick interactively or by
    name).

  - `codeagent()` : Run a one-shot codeagent query

  - `agent_loop()` : Main agentic query loop

  - `use_codeagent_settings()` : Create a codeagent settings.json file

  - `use_codeagent_setup()` : Interactive setup wizard for codeagent

## Shiny App

Interactive chat interface.

<!-- end list -->

  - `codeagent_app()` : Launch the codeagent Shiny application

## IDE Addins

RStudio / Positron keyboard-shortcut integration.

<!-- end list -->

  - `codeagent_addin()` : Open the codeagent Shiny app from an IDE addin
  - `codeagent_addin_selection()` : Open codeagent with the current
    editor selection as context

## CLI

Terminal REPL and command-line interface.

<!-- end list -->

  - `codeagent_console()` : Run the interactive REPL
  - `install_codeagent_cli()` : Install the codeagent CLI

## Core tools

Built-in tool factories registered on the Chat.

<!-- end list -->

  - `bash_tool()` : Create the Bash tool
  - `read_tool()` : Create the Read tool
  - `write_tool()` : Create the Write tool
  - `edit_tool()` : Create the Edit tool
  - `multi_edit_tool()` : Create the MultiEdit tool
  - `glob_tool()` : Create the Glob tool
  - `grep_tool()` : Create the Grep tool
  - `ls_tool()` : Create the LS tool
  - `run_r_tool()` : Create the RunR tool
  - `explore_data_tool()` : Create the ExploreData tool
  - `register_builtin_tools()` : Register all built-in codeagent tools
    to a Chat
  - `register_explore_data_tool()` : Register the ExploreData tool on a
    Chat

## Permissions

Seven-mode permission gate and rule system.

<!-- end list -->

  - `check_permission()` : Check whether a tool call is permitted
  - `PermissionMode` : Permission modes for codeagent
  - `PermissionRule()` : Create a permission rule

## Session Management

Save, load, and navigate conversation history.

<!-- end list -->

  - `list_sessions()` : List codeagent sessions
  - `save_session()` : Save an ellmer Chat session to disk
  - `restore_session_into_chat()` : Restore a saved session's messages
    into a Chat object
  - `get_session_messages()` : Get messages from a session
  - `fork_session()` : Fork a session
  - `rename_session()` : Rename a session
  - `tag_session()` : Tag a session
  - `truncate_chat_turns()` : Rewind a chat to an earlier point in the
    conversation

## Memory

Persistent cross-session memory.

<!-- end list -->

  - `write_memory()` : Write a memory to disk
  - `list_memories()` : List stored memories (parsed front-matter +
    body)
  - `recall_memories()` : Recall memories as a compact block for
    system-reminder injection
  - `recall_memories_relevant()` : Recall only the memories relevant to
    a query (haiku-selected)
  - `delete_memory()` : Delete a memory by slug
  - `read_todos()` : Read the current todo list for a session

## Multi-Agent Teams

Parallel agent coordination.

<!-- end list -->

  - `team_run()` : Run a set of independent tasks as a parallel agent
    team
  - `team_coordinate()` : Coordinate a team of agents over a shared task
    board
  - `board_create()` : Create a new shared task board
  - `board_add_task()` : Add a task to the board
  - `board_claim()` : Atomically claim the next claimable task
    (dependency-aware)
  - `board_complete()` : Mark a claimed task complete with its result
  - `board_status()` : Read the full board state
  - `board_send_message()` : Post a message to the team message log
  - `board_messages()` : Read messages from the team message log
  - `team_lead()` : LLM-lead autonomous coordinator
  - `team_dashboard()` : Live team-board dashboard
  - `board_reclaim_stale()` : Reclaim tasks whose worker died mid-flight
  - `board_watch()` : Watch a task board for changes (event-driven
    coordinator engine)

## Skills

Skill discovery and loading.

<!-- end list -->

  - `list_skills_meta()` : List skill metadata from all skill
    directories
  - `load_skill_prompt()` : Load a skill's full prompt
  - `build_skill_hint()` : Build skill hint for system prompt
  - `install_ds_skills()` : Install Posit's data-science skill
    collection (posit-dev/skills)

## MCP

Model Context Protocol client and server.

<!-- end list -->

  - `codeagent_mcp_server()` :
    
    Exposes codeagent's tool set as an MCP server. By default uses btw's
    `btw_mcp_server()` over stdio (for Claude Desktop / VS Code MCP
    config). With `transport = "http"` it serves over HTTP via
    `mcptools::mcp_server()` (\>= 0.2.1), enabling remote MCP clients.
    The server runs in a blocking loop.

  - `register_mcp_client()` : Register external MCP server tools onto a
    Chat

  - `r_mcp_server()` : Create an R-based MCP server entry

## RAG

Codebase semantic retrieval.

<!-- end list -->

  - `build_codebase_store()` : Build (or rebuild) a codebase vector
    store
  - `register_rag_tool()` : Register a codebase retrieval tool on a chat

## Hooks

Lifecycle event hooks.

<!-- end list -->

  - `HookRegistry` : Tool hook registry
  - `HookEvent` : Hook event types

## Utilities

Miscellaneous helpers.

<!-- end list -->

  - `switch_model()` : Switch the active model on a CodeagentClient,
    preserving history
  - `verify_r_tests()` : R package test verification function
  - `verify_r_lints()` : Lint-based verification function
  - `codeagent_otel_status()` : Report OpenTelemetry observability
    status for codeagent
  - `use_codeagent_md()` : Create a codeagent.md configuration file

## Additional tools & registration

Tool factories and registration.

<!-- end list -->

  - `agent_tool()` : Create the Agent tool
  - `ask_user_tool()` : Create the AskUserQuestion tool
  - `notebook_edit_tool()` : Create the NotebookEdit tool
  - `notebook_read_tool()` : Create the NotebookRead tool
  - `todo_write_tool()` : Create the TodoWrite tool
  - `web_fetch_tool()` : Create the WebFetch tool
  - `web_search_tool()` : Create the WebSearch tool
  - `register_agent_tool()` : Register the Agent tool and any btw custom
    agent tools
  - `register_ask_user_tool()` : Register the AskUserQuestion tool on a
    Chat
  - `register_btw_file_tools()` : Register btw file tools with
    permission control
  - `register_notebook_tools()` : Register notebook tools to an ellmer
    Chat object
  - `register_r_tools()` : Register btw R-environment tools to an ellmer
    Chat object
  - `register_task_tools()` : Register task management tools to an
    ellmer Chat object
  - `register_web_tools()` : Register web tools to an ellmer Chat object
  - `enable_btw_file_tools()` : Patch codeagent\_client() to use btw
    file tools (Path A)

## Data exploration (WEAR)

Interactive data exploration and reporting.

<!-- end list -->

  - `wear_explore()` : Start a WEAR loop data exploration session
  - `generate_wear_report()` : Export the current WEAR exploration
    session to a Quarto document

## Sessions & settings

Session storage and settings helpers.

<!-- end list -->

  - `delete_session()` : Delete a session
  - `get_session_info()` : Get metadata for a single session
  - `migrate_sessions()` : Migrate legacy session files to the current
    format version
  - `load_settings()` : Load codeagent settings
  - `save_user_settings()` : Save user settings to
    \~/.codeagent/settings.json
  - `migrate_config_dir()` : Migrate the codeagent config directory to
    the OS-standard location

## Harness internals

R6 controllers and content/permission types (advanced).

<!-- end list -->

  - `BudgetTracker` : Token budget tracker
  - `CompactionController` : Context compaction controller
  - `ContentReplacementState` : Global context budget manager (Layer 3)
  - `DenialTracker` : Track permission denials and emit warnings at
    thresholds
  - `StreamingToolExecutor` : Concurrent tool execution scheduler
  - `PreToolHook()` : Pre-tool hook definition
  - `PostToolHook()` : Post-tool hook definition
  - `PermissionResultAllow()` : Allow a tool call
  - `PermissionResultDeny()` : Deny a tool call
  - `TextBlock()` : Create a TextBlock
  - `ThinkingBlock()` : Create a ThinkingBlock
  - `ToolResultBlock()` : Create a ToolResultBlock
  - `ToolUseBlock()` : Create a ToolUseBlock

## Streaming

Per-turn streaming primitives with typed content callbacks.

<!-- end list -->

  - `codeagent_stream()` : Stream one agent turn synchronously (CLI /
    ink)
  - `codeagent_stream_async()` : Stream one agent turn asynchronously

## Guided tasks

One-shot guided workflows (reuse btw tasks).

<!-- end list -->

  - `codeagent_task()` : Run a btw task with a codeagent client (reuse,
    not reinvent)
  - `codeagent_create_skill()` : Create a skill via btw's guided task
    (reuse)
  - `codeagent_create_readme()` : Create a polished README via btw's
    guided task (reuse)
  - `codeagent_init_context()` : Initialise a project-context file
    (btw.md) via btw's guided task (reuse)
