# Workspace layout engine

Pure functions over the right-panel workspace layout: each returns a new
layout, none reads the clock or the session. A layout is
`list(tabs, active, seen, next_id)`: `tabs` in strip order (pinned
first), `active` the shown tab id or `NULL`, `seen` tab ids from least
to most recently viewed (eviction order), `next_id` the counter for tab
ids. A tab is `list(id, kind, content_id, title, pinned)`;
`(kind, content_id)` is its content identity.
