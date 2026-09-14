# Permission modes for codeagent

A named list of the seven permission modes, mirroring Claude Code's
design.

## Usage

``` r
PermissionMode
```

## Format

An object of class `list` of length 7.

## Details

- `default` – Reads auto-allow; writes and shell execution require user
  confirmation.

- `plan` – Read-only mode; all non-read tools are rejected.

- `accept_edits` – File edits auto-allow; Bash still requires
  confirmation.

- `bypass` – Almost all operations auto-approved.

- `dont_ask` – Operations that would ask are auto-rejected (CI/CD).

- `auto` – AI classifier (haiku model) decides automatically.

- `bubble` – Sub-agent mode: permission decisions bubble up to the
  parent agent rather than being resolved locally.
