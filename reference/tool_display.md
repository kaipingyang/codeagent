# Typed Tool-Result Display Contract + Render Dispatcher

Rich, interactive tool-card rendering for both the in-chat bubble and
the right Output panel. Defines a typed artifact contract stored under
`extra$codeagent$artifact` (a private key ellmer only transports, so
shinychat never warns about it), a render dispatcher that branches on
the artifact kind (code/image/table/diff/text/error), and a generalized
adapter that normalizes any native `ContentToolResult` – raw
[`btw::btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html)
results included – into the typed contract.

Design: the artifact lives on `extra$codeagent`, never under
`extra$display`, so `display` carries ONLY shinychat-official fields
(title/icon/markdown/ html/full_screen/open). The in-chat card keeps
rendering natively while codeagent owns the right-panel rendering.
