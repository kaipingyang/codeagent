#' @title Bash Sandbox (lightweight, in-process)
#' @description Optional, best-effort sandboxing for the Bash tool. This is NOT
#'   a security boundary on its own -- the permission gate (`permissions.R`) and
#'   hooks (`hooks.R`) are the primary controls. The sandbox adds defence in
#'   depth for the common cases:
#'
#'   * **env scrubbing** -- run the command with a minimal environment so
#'     secrets in the parent process env (API keys, tokens) are not visible to
#'     arbitrary shell commands.
#'   * **network deny** -- refuse commands that match known network utilities
#'     when network access is disabled.
#'   * **cwd confinement** -- run inside a declared working directory.
#'
#'   True OS-level isolation (filesystem namespaces, seccomp, containers) is a
#'   host-layer responsibility (Docker / nsjail / firejail) and is intentionally
#'   out of scope here -- see `references/sandbox-limitations.md`.
#' @name sandbox
#' @keywords internal
NULL

# Network-capable utilities blocked when network access is disabled.
.SANDBOX_NETWORK_CMDS <- c(
  "curl", "wget", "nc", "ncat", "netcat", "ssh", "scp", "sftp", "telnet",
  "ftp", "rsync", "git clone", "git fetch", "git pull", "git push",
  "pip install", "npm install", "npm i", "yarn add", "apt-get", "apt ",
  "brew install", "wget", "aria2c"
)

# ---------------------------------------------------------------------------
# OS-level no-network isolation via unprivileged user+net namespace (unshare).
#
# Unlike the .SANDBOX_NETWORK_CMDS / .SANDBOX_R_NETWORK_FNS blacklists (which
# match code text and can be bypassed by obfuscation, e.g.
# get(paste0("down","load.file"))), wrapping a command in `unshare -Urn` puts it
# in a network namespace with NO network interface. Any connect()/socket()
# syscall then fails at the kernel level regardless of how the code is written.
# This is bounded (a finite kernel boundary), not an endless blacklist.
#
# Requires unprivileged user namespaces to be enabled (default on many kernels;
# some hardened deployments set kernel.unprivileged_userns_clone=0). Probed at
# runtime and cached; when unavailable we fall back to the blacklist.
# ---------------------------------------------------------------------------

.sandbox_unshare_cache <- new.env(parent = emptyenv())

#' Probe whether `unshare -Urn` (unprivileged user+net namespace) works here.
#'
#' Runs `unshare -Urn true` once and caches the result. Returns FALSE when
#' `unshare` is missing, unprivileged userns is disabled, or the probe errors.
#' @keywords internal
.sandbox_unshare_available <- function() {
  if (!is.null(.sandbox_unshare_cache$ok)) return(.sandbox_unshare_cache$ok)
  ok <- tryCatch({
    if (nzchar(Sys.which("unshare")) == FALSE) FALSE
    else {
      status <- suppressWarnings(system2(
        "unshare", c("-Urn", "true"),
        stdout = FALSE, stderr = FALSE))
      identical(as.integer(status), 0L)
    }
  }, error = function(e) FALSE)
  .sandbox_unshare_cache$ok <- isTRUE(ok)
  .sandbox_unshare_cache$ok
}

#' Wrap an argv vector to run inside a no-network user+net namespace.
#'
#' @param argv Character vector: the command + args to run (e.g.
#'   `c("Rscript", "-e", "...")`).
#' @param no_network Logical. Request kernel-level network isolation.
#' @return A character vector prefixed with `unshare -Urn` when available and
#'   requested; otherwise `argv` unchanged. When no-network was requested but
#'   `unshare` is unavailable, the returned vector carries
#'   `attr(x, "network_isolation") = "unavailable"` and a one-time session
#'   warning is emitted -- the OS-level boundary has silently degraded to the
#'   command-name blacklist, which is bypassable (kiro round-2 #12). Callers
#'   should surface this in audit/UI rather than treat `allow_network=FALSE` as a
#'   hard guarantee.
#' @keywords internal
.sandbox_unshare_wrap <- function(argv, no_network = TRUE) {
  if (!isTRUE(no_network)) return(argv)
  if (.sandbox_unshare_available()) {
    out <- c("unshare", "-Urn", "--", argv)
    attr(out, "network_isolation") <- "kernel"
    return(out)
  }
  # Degraded: no OS network namespace. Mark it and warn ONCE per session so a
  # caller cannot mistake allow_network=FALSE for a hard isolation guarantee.
  if (!isTRUE(.sandbox_unshare_cache$fallback_warned)) {
    warning("Data Shield sandbox: OS network isolation unavailable (`unshare ",
            "-Urn` failed); allow_network=FALSE has degraded to a bypassable ",
            "command-name blacklist. Enable unprivileged user namespaces, or ",
            "treat this environment as network-capable.", call. = FALSE)
    .sandbox_unshare_cache$fallback_warned <- TRUE
  }
  attr(argv, "network_isolation") <- "unavailable"
  argv
}

#' Build a sandbox profile from settings
#'
#' @param settings List or NULL. Reads `settings$sandbox` (a list with optional
#'   `enabled`, `allow_network`, `keep_env`).
#' @return A normalised profile list: `enabled`, `allow_network`, `keep_env`
#'   (character vector of env var names to preserve).
#' @keywords internal
.sandbox_profile <- function(settings = NULL) {
  sb <- tryCatch(settings$sandbox, error = function(e) NULL)
  list(
    enabled       = isTRUE(sb$enabled),
    allow_network = if (is.null(sb$allow_network)) TRUE else isTRUE(sb$allow_network),
    keep_env      = sb$keep_env %||% c("PATH", "HOME", "LANG", "LC_ALL", "TMPDIR",
                                       "TERM", "USER", "SHELL")
  )
}

#' Decide whether a command is blocked by the sandbox
#'
#' @param command Character. The shell command.
#' @param profile List from [.sandbox_profile()].
#' @return NULL if allowed, or a character reason string if blocked.
#' @keywords internal
.sandbox_block_reason <- function(command, profile) {
  if (!isTRUE(profile$enabled)) return(NULL)
  if (isTRUE(profile$allow_network)) return(NULL)
  cmd <- tolower(trimws(command %||% ""))
  for (pat in .SANDBOX_NETWORK_CMDS) {
    # word-boundary-ish match: the utility at a token boundary
    if (grepl(paste0("(^|[;&|[:space:]])", gsub(" ", "[[:space:]]+", pat)),
              cmd, perl = TRUE))
      return(paste0("network access disabled by sandbox (matched '", pat, "')"))
  }
  NULL
}

#' Compute the environment for a sandboxed command
#'
#' When the sandbox is enabled, returns a minimal `character()` env vector
#' (NAME=VALUE) limited to `keep_env`. When disabled, returns NULL (inherit the
#' parent environment, the legacy behaviour).
#'
#' @param profile List from [.sandbox_profile()].
#' @return Character vector of `NAME=VALUE` strings, or NULL.
#' @keywords internal
.sandbox_env <- function(profile) {
  if (!isTRUE(profile$enabled)) return(NULL)
  keep <- profile$keep_env
  vals <- Sys.getenv(keep, unset = NA)
  vals <- vals[!is.na(vals)]
  if (!length(vals)) return(character(0))
  paste0(names(vals), "=", vals)
}

# R functions that reach the network or otherwise escape the sandbox. RunR runs
# IN-PROCESS, so we cannot scrub the environment (the eval shares this R
# session); the practical control is to refuse code that calls network /
# process-spawning / env-mutating functions when the sandbox forbids them.
.SANDBOX_R_NETWORK_FNS <- c(
  "httr2::request", "httr::GET", "httr::POST", "download.file", "url\\(",
  "curl::curl", "curl::curl_fetch", "RCurl::getURL", "readLines\\(url",
  "socketConnection", "install.packages", "remotes::install",
  "devtools::install", "pak::pak", "utils::download.file"
)

# R functions that spawn shells / processes (would bypass Bash sandboxing).
.SANDBOX_R_SHELL_FNS <- c(
  "system\\(", "system2\\(", "shell\\(", "processx::", "callr::",
  "Sys.setenv\\("
)

#' Decide whether RunR code is blocked by the sandbox
#'
#' RunR executes in-process, so environment scrubbing is impossible. Instead,
#' when the sandbox is enabled we refuse code that calls network functions (if
#' `allow_network` is FALSE) or that spawns shells / mutates the environment
#' (always, since those would sidestep the Bash sandbox).
#'
#' @param code Character. The R code to run.
#' @param profile List from [.sandbox_profile()].
#' @return NULL if allowed, or a character reason string if blocked.
#' @keywords internal
.sandbox_block_r_code <- function(code, profile) {
  if (!isTRUE(profile$enabled)) return(NULL)
  src <- paste(code, collapse = "\n")

  # Shell / process spawning + env mutation always blocked under sandbox:
  # these would defeat the Bash-level controls.
  for (pat in .SANDBOX_R_SHELL_FNS) {
    if (grepl(pat, src, perl = TRUE))
      return(paste0("sandbox blocks shell/process/env calls in RunR (matched '",
                    gsub("\\\\", "", pat), "')"))
  }

  # Network functions blocked only when network is disabled.
  if (!isTRUE(profile$allow_network)) {
    for (pat in .SANDBOX_R_NETWORK_FNS) {
      if (grepl(pat, src, perl = TRUE))
        return(paste0("network access disabled by sandbox (matched '",
                      gsub("\\\\.*", "", pat), "')"))
    }
  }
  NULL
}
