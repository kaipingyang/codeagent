#!/usr/bin/env bash
# Install the working tree into the local R library, then refresh CodeGraph.
#
# Why the CodeGraph daemon must stop first
# ----------------------------------------
# While the daemon runs it listens on a Unix domain socket at
# `.codegraph/daemon.sock`. That single node breaks BOTH R packaging paths,
# and `.Rbuildignore` cannot save either of them:
#
#   * pak  — `pkgdepends:::download_remote_local()` copies the whole source
#     tree with `file.copy(recursive = TRUE)` BEFORE any `.Rbuildignore`
#     filtering happens. `file.copy()` cannot copy a socket, returns FALSE,
#     and pak reports the misleading
#     "Failed to download <pkg> from file:///...". Nothing about the message
#     points at the socket, and it is unrelated to the network or the cache.
#
#   * R CMD build — DOES enumerate `.codegraph` (dir(include.dirs = TRUE)) and
#     DOES match it against `^\.codegraph`, then removes matches with
#     `unlink(recursive = TRUE, force = TRUE)`. That call returns 1 (failure)
#     on a directory holding a socket, and the return value is never checked,
#     so `.codegraph/` silently survives into the tarball.
#
# Verified on an isolated minimal package: identical tree, socket present ->
# pak fails and `.codegraph/` lands in the tarball; socket removed -> pak
# installs cleanly and the tarball contains only the five expected entries.
# So `.Rbuildignore` is correct as written; the socket is the whole problem.
#
# Stopping the daemon removes the socket and `pak::local_install()` then
# behaves exactly as documented. The daemon only backs the SHARED MCP mode:
# `codegraph sync` / `explore` and the other CLI commands do not need it (they
# were verified to keep working with the daemon down), and an MCP host respawns
# it -- or falls back to direct mode -- on its next connection. So the cost of
# stopping it here is close to zero. Set CODEGRAPH_NO_DAEMON=1 in your shell to
# never run it for this project at all (official opt-out; MCP goes direct).
set -euo pipefail

pkg_dir=${1:-.}
pkg_dir=$(cd -- "$pkg_dir" && pwd -P)
cd -- "$pkg_dir"

cg_dir=${CODEGRAPH_DIR:-.codegraph}
pid_file="$cg_dir/daemon.pid"
sock_file="$cg_dir/daemon.sock"

stop_daemon() {
  [[ -e $pid_file || -e $sock_file ]] || return 0

  local pid=""
  if [[ -f $pid_file ]]; then
    pid=$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$pid_file" | head -1)
    [[ -n $pid ]] || pid=$(tr -cd '0-9' < "$pid_file")   # legacy plain-pid file
  fi

  if [[ -n ${pid:-} ]] && kill -0 "$pid" 2>/dev/null; then
    echo "==> stopping codegraph daemon (pid $pid)"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi

  # The daemon has no chance to clean up after a signal, and a leftover socket
  # is exactly what breaks packaging -- remove both rendezvous files.
  rm -f -- "$sock_file" "$pid_file"
}

stop_daemon

echo "==> installing into the local R library"
Rscript -e 'pak::local_install(".", ask = FALSE, upgrade = FALSE)'

echo "==> syncing codegraph"
if command -v codegraph >/dev/null 2>&1; then
  codegraph sync
else
  echo "    codegraph not on PATH; skipped"
fi

echo "==> done"
