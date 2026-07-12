# Typed Tool-Result Display Contract + Render Dispatcher

Rich, interactive tool-card rendering for the right Output panel.
Defines a typed display contract (`extra$display$toolcard`) layered on
top of the existing `{title, markdown, right_output}` keys, a render
dispatcher that branches on result kind
(code/image/table/diff/text/error), and a generalized adapter that
normalizes any native `ContentToolResult` – raw
[`btw::btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html)
results included – into the typed contract.

Design: the private `card` sub-list never collides with shinychat's
reserved display keys (title/icon/markdown/html/text), so the in-chat
card keeps rendering natively while codeagent owns the right-panel
rendering.
