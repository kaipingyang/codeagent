# Path A – btw File Tools with Permission Gate (EXPERIMENTAL)

Wraps btw's file tools with codeagent's permission system.

**Design rationale – two parallel edit paths:**

|                             |                                                  |                   |                                   |
| --------------------------- | ------------------------------------------------ | ----------------- | --------------------------------- |
| Path                        | Tools                                            | Scope             | Strength                          |
| **Default** (codeagent)     | Read/Write/Edit/MultiEdit/Glob/Grep/LS           | Any absolute path | Full filesystem access            |
| **Path A** (btw, this file) | files\_read/write/edit/replace/patch/list/search | Project cwd only  | Hash-anchored edits, atomic patch |

The cwd restriction in Path A is **intentional and desirable** for
security-conscious environments: the agent cannot accidentally (or
maliciously) modify files outside the project directory. The default
path is more powerful but riskier; use it when you need to read system
paths, other projects, `/tmp`, etc.

Use both: Path A is opt-in via `enable_btw_file_tools()`, and coexists
with the default tools. The LLM chooses the right tool for each task:
btw tools for project-local edits (safer, hash-verified), default tools
for absolute paths.

**Not loaded by default.** Opt in with:

    enable_btw_file_tools()          # sets options(codeagent.use_btw_files = TRUE)
    client <- codeagent_client(chat) # both tool sets registered
