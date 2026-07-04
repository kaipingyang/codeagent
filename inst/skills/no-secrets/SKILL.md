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

## Test fixtures
Fake, obviously-non-real values in tests (e.g. `"SECRET_LEAK_TOKEN_abc"`) are
fine and expected — they must never be real credentials.
