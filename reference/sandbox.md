# Bash Sandbox (lightweight, in-process)

Optional, best-effort sandboxing for the Bash tool. This is NOT a
security boundary on its own – the permission gate (`permissions.R`) and
hooks (`hooks.R`) are the primary controls. The sandbox adds defence in
depth for the common cases:

- **env scrubbing** – run the command with a minimal environment so
  secrets in the parent process env (API keys, tokens) are not visible
  to arbitrary shell commands.

- **network deny** – refuse commands that match known network utilities
  when network access is disabled.

- **cwd confinement** – run inside a declared working directory.

True OS-level isolation (filesystem namespaces, seccomp, containers) is
a host-layer responsibility (Docker / nsjail / firejail) and is
intentionally out of scope here – see
`references/sandbox-limitations.md`.
