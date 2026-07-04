---
name: no-secrets
description: Hard rule — never commit, push, or print secrets (API keys, tokens, passwords) or concrete infrastructure endpoints (real base_urls, Databricks/serving-endpoint hosts, workspace IDs, internal hostnames). Use placeholders + env vars. Triggers when about to git add/commit/push, write config/examples/docs, or handle credentials.
---

# Never upload or print sensitive data

This is a **hard rule**, not a preference.

## Never put these in tracked files (source, tests, examples, docs, configs)
- API keys / tokens / passwords (`CODEAGENT_API_KEY`, `GITHUB_TOKEN`, `ghp_*`,
  `sk-*`, `dapi*`, bearer tokens, OAuth secrets).
- Concrete infrastructure endpoints: real `base_url` values, Databricks /
  serving-endpoint hosts, **workspace IDs/hosts** (e.g. `adb-<id>.azuredatabricks.net`),
  internal hostnames, private IPs.
- `.Renviron`, `.env`, `credentials.json`, `*.pem`, `*.key`.

## Always
- Use **placeholders** in examples/templates: `YOUR-WORKSPACE.cloud.databricks.net`,
  `sk-...`, `your-endpoint-name`, `<workspace-id>`.
- Read real values only from **environment variables** (`Sys.getenv(...)`) or the
  **OS keyring**; keep them in `.Renviron`/keyring, which stay git-ignored.
- Before `git add`/`commit`/`push`, **scan the diff** for the patterns above
  (`git diff --cached | grep -iE 'api[_-]?key|token|secret|password|sk-|ghp_|dapi|azuredatabricks\.net|serving-endpoints'`).
- **Never echo a full token/key** in command output or logs. Mask with
  `sed -E 's#//[^@]*@#//***@#g'` when printing remote URLs.

## If a secret was already committed
1. It is compromised the moment it hits a remote — **rotate/revoke it** first
   (rotating the credential matters more than scrubbing history).
2. Purge from history with `git filter-repo --replace-text` (or BFG), then
   force-push. History rewrite does not un-expose an already-public value.
3. Prefer placeholders over deletion so examples still read clearly.
4. Scrub **every variant** of the value, not just one form. A workspace ID can
   appear in several hosts (`adb-<id>.azuredatabricks.net`,
   `<id>.ai-gateway.azuredatabricks.net`, ...). Replace the **bare id/number**
   so all forms are caught, then re-scan the whole history
   (`for c in $(git rev-list --all); do git grep -q '<id>' "$c" && echo "$c"; done`).

## Tooling caveat: git-filter-repo prints the removed remote URL
`git filter-repo` echoes the removed `origin` URL, e.g.
`(was https://user:ghp_XXXX@github.com/...)` — that **leaks the token in your
HTTPS remote** into the terminal/logs. Mitigate:
- Pipe its output through a mask: `2>&1 | sed -E 's#//[^@]*@#//***@#g; s#ghp_[A-Za-z0-9]+#ghp_***#g'`.
- Better: use a **tokenless** remote during the rewrite (SSH, or
  `git remote remove origin` first), and re-add the token remote only for the
  final push.
- If a token was printed anyway, **rotate it** (github.com/settings/tokens) and
  update `~/.Renviron`.

## Test fixtures
Fake, obviously-non-real values in tests (e.g. `"SECRET_LEAK_TOKEN_abc"`) are
fine and expected — they must never be real credentials.
