# Changelog

## codeagent (development version)

- `codeagent_server(on_user_prompt =)` may return a promise of its
  context when the host is still preparing it (e.g. a project index
  being built): the turn’s first model request waits for it, at most
  `prompt_wait` seconds (new argument, default 30), and goes on without
  it after that.

- Data Shield registers datasets much faster: a newly registered dataset
  is merged into the live value index instead of the index being rebuilt
  from every dataset each time (a replaced or cleared dataset still
  rebuilds), and value labels are added in bulk. 32 ADaM datasets: 15.6
  s -\> 1.2 s, with an identical index (values, labels, deny values,
  identifier variants).

- Upstream packages updated: ellmer (with S7 1.0.0) and shiny
  1.15.0.9000 are pinned to their current GitHub HEADs; btw, shinychat,
  bslib, shinyglass, shinygenui, mcptools, Rapp and coro were already
  current. httr2 stays at its pinned commit because its current HEAD
  needs an unreleased curl change. ellmer’s new
  `Chat$get_max_context_length()` is not used for compaction: its first
  call requests the provider’s model listing, and token accounting makes
  no implicit network requests.

- [`build_codebase_store()`](https://kaipingyang.github.io/codeagent/reference/build_codebase_store.md)
  no longer uses `ragnar_read()` / `ragnar_chunk()`, which ragnar 0.4.0
  deprecates. R, Markdown, R Markdown and Quarto files are read directly
  instead of going through Python MarkItDown, so indexing a codebase no
  longer installs Python packages on first use. Other formats still use
  [`ragnar::read_as_markdown()`](https://ragnar.tidyverse.org/reference/read_as_markdown.html).
  Requires ragnar \>= 0.2.0.

- The full-compaction system prompt has been rewritten in codeagent’s
  own words. It keeps the same contract – text only, an `<analysis>`
  pass that is discarded, then a `<summary>` with the same nine numbered
  sections – so summaries and the code that reads them are unchanged in
  shape. Comments and documentation around context and compaction now
  describe behaviour instead of referring to implementation files.

- `coro` is now pinned to its GitHub development version
  (r-lib/coro#72). CRAN coro 1.1.0 made R byte-compile every generator
  again on each call, which added about 0.9 s to every model request –
  once per tool round, in the chat app as well as in
  [`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md).
  A local A/B test against plain shinychat + ellmer went from 1.4 s to
  0.5 s to first token.

- Fixed: a streamed turn released its async-turn ownership before an
  asynchronous iterator `close` had finished.
  [`promises::finally()`](https://rstudio.github.io/promises/reference/then.html)
  does not wait for a promise returned by its callback; the slow
  coroutine start-up of CRAN coro happened to hide the gap. The close is
  now chained explicitly and the turn settles with its original result
  or error once it completes.

- Fixed (review of the Data Shield display work): with
  `display = "hide"` a tool card stayed when the shield matched an
  identifier variant or an unregistered identifier shape (no column to
  ask) – it is hidden now. Hit labels are no longer named by the matched
  value. A pasted-table question that goes away unanswered is recorded
  in the audit log as not sent. `audit()` has its own documentation
  again.

- Interaction cards (questions, forms, approvals) have a handle on the
  top edge: drag it up – as far as the top of the chat – or down, like a
  phone’s bottom sheet; double-click or Enter toggles full height /
  default, arrow keys step it. The default cap is 60% of the chat (was
  half). The browser keeps the chosen height for later cards (capped by
  it, they still shrink to their content). In the composer’s place
  (theme `"dsh"`), forms get the same handle.

- A long form keeps its buttons in view: the fields scroll, Cancel /
  Submit stay at the bottom (with `theme = "dsh"` they were cut off).

- New
  [`codeagent_theme_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_theme_ui.md) +
  `codeagent_server(themes =, on_theme =)`: the user switches the page’s
  theme (e.g. the default look and `codeagent_theme("dsh")`) while the
  session runs; the page structure, chat and tabs stay. `on_theme` lets
  the host remember the choice.

- Fixed: after a runtime theme swap (`session$setCurrentTheme()`), the
  theme’s stylesheets were re-added at the end of `<head>` and overrode
  the component and host CSS (the chat composer got Bootstrap’s input
  box and its send button wrapped). Stylesheets that followed the theme
  move back behind it; the sheets Shiny re-adds stay where it put them,
  so each is replaced, not duplicated.

- `theme = "dsh"`: the empty composer’s placeholder stays on one line
  (it wrapped and showed a scrollbar).

- `theme = "dsh"`: the shinychat history drawer of a host page
  (`codeagent_chat_ui(history = TRUE)`) has the DSH sidebar surface; it
  was transparent, so the chat showed through the list. Only the history
  column of the DSH page sidebar stays transparent.

- Data Shield says what the user still sees. Every notice the model gets
  ends with one of “The user sees the full result in the tool card; only
  you cannot see it.”, “The result was not shown to the user either.” or
  “The tool did not run, so the user saw no result either.” (tool
  errors, rejected arguments, sandbox / policy denials included), so the
  model can tell the user.

- `register_data(display =)` and `column_access(display =)`: whether the
  user may see a dataset’s / column’s protected values in the tool’s own
  card when they are kept from the model. Default unchanged: `"show"`,
  except `egress = "none"` columns, which are `"hide"`. With `"show"`
  only the model-facing value is replaced; with `"hide"` the card is
  dropped too.

- New `shield_prompt(on_fail)` strategy: the input gate’s policy set on
  the shield itself (a client’s `settings$data_shield_prompt_on_fail`
  still wins); `DataShield$prompt_on_fail()` reads it.

- Prompt gate `data_shield_prompt_on_fail = "ask"` is now tiered:
  subject identifiers block the message (with the source columns, never
  the values); a pasted table of numbers (5+ lines with numbers, or 8+
  tab / \|-separated cells with digits – shinychat joins the lines of a
  paste – or 3+ “n (%)” results) asks the user in the question card
  before it is sent; other protected values are redacted and the chat
  says which columns. Before, “ask” silently redacted. Without a way to
  ask (CLI) the input goes on redacted, as before. Prompt /
  tool-argument / reply audit reasons name the source columns too.

- Data Shield notices pair each dataset with a column it really has: a
  value in several datasets keeps all of them; the notice names the
  dataset the tool was asked about (a registered dataset name in its
  arguments, e.g. `dataset = "ADSL"`) when the value is in it, else
  every dataset that has it, per column (“SUBJID (identifier) in ADAE,
  ADSL, ADCM and 4 more datasets”). Was: the first dataset registered,
  so an ADSL query was reported as ADAE.

- Data Shield notices say why output was withheld or denied: the dataset
  columns the protected values come from and their class, e.g. “contains
  2 protected data value(s). Source: ADSL.COUNTRY (quasi).” or “an
  identifier written in another format” – never a value, its position or
  context (column names are the schema `DescribeData` already shows).
  The audit log records the same, so false positives can be collected.
  `shield_egress(explain = FALSE)` keeps the bare notice.

- AskUserForm `grouping` fields: the open drop-down list spans the whole
  row (the name column included) instead of only the drop-down’s width,
  so long arm names are readable in a narrow chat column.

- New `codeagent_ask_form(title, fields, submit_label)`: a host tool
  asks the user a form itself – the AskUserForm card, with the same
  field types (including `grouping`), queue and “Answered” record – and
  gets a promise of `list(submitted, values)`. Use it when the host
  knows what to ask (e.g. the arms to combine, taken from the data) so
  the user always gets the right controls, whatever field types the
  model would have chosen.

- Workspace tabs can float: drag a tab down off the strip, double-click
  it, or use “Pop out” in its menu. The tab becomes a window over the
  page (drag its bar, resize its corner) while the chat stays usable;
  several can be open to compare results. “Dock” (or double-click the
  tab again) puts it back; its content is not reloaded either way.
  Floating is per page, not saved.

- AskUserForm `grouping` fields are rows of an editable group name and a
  drop-down checklist of the choices, with “+ Add group” and remove
  buttons (was: a group-name box per choice). A choice checked in one
  row shows as taken in the others and cannot be picked there; on submit
  the first row keeps a choice named twice and choices in no group stay
  on their own. The value is unchanged: `list(group = choices)`.

- `form_widgets =` on
  [`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
  and
  [`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md):
  how AskUserForm fields are drawn – Shiny’s controls by default,
  presets `"shiny.element"` and `"shinyWidgets"` in priority order, host
  presets and per-type widgets, mixed. New field attributes
  `placeholder`, `min`/`max`/`step`, `allow_other`, `pattern` +
  `pattern_hint` and `section`; the form lays itself out to the
  available width (`width = "full"` keeps a field on its own row). Long
  forms scroll their fields while Cancel / Submit stay in view (they
  were cut off), and a refused submit says why next to the buttons,
  marks the fields and focuses the first instead of a toast over the
  buttons.

- Fixed: a floating interaction card could be see-through. A form whose
  controls bring new dependencies (the date picker) was inserted after
  the card was placed, so it stayed in the footer below the composer; it
  is now placed when its content lands. Every kind is the same opaque
  card with a border as the question card, and the gap to the composer
  is painted so the conversation does not show through.

- `ui_layout = "dsh"` / `theme = "dsh"`: messages, the composer and the
  interaction cards use the whole width of the chat column instead of
  DSH’s `clamp(680px, 64%, 880px)` cap; user bubbles are at most 70% of
  it.

- New `codeagent_progress(label, step, typical, delay)`: a host tool
  reports what it is doing while it runs. The chat shows one line per
  running tool above the input (label, step, seconds elapsed, “usually
  ~N s”), from `delay` seconds (default 3) until `done()` or the end of
  the turn. It is in every chat (codeagent_app() layouts too) and sits
  in the same seat as the interaction cards, floating just above the
  composer (above a card when one is shown).

- AskUserQuestion with several questions shows a tab per question at the
  top of the card (its header, else “Question i”): the current one
  marked, answered ones ticked, skipped ones dashed; a click or the
  arrow keys go to that question. The small header above the title now
  follows the question shown. A single question has no tabs.

- Interaction cards (approval, questions, form, Data Shield) float right
  above the composer, same width, at most half the chat’s height and
  scrolling inside, and follow it when the sidebar or window is resized;
  the “N more requests waiting” line sits above the card. With
  `theme = "dsh"` the card still takes the composer’s seat. Forms submit
  with Enter (Ctrl/Cmd+Enter in multi-line fields). Answers leave a
  short record in the reply (“Answered: … -\> …” / “Submitted: …”), next
  to “Tool allowed.” / “Tool denied.”.

- Tool rows no longer show their title twice (“Read a.R: Read a.R”): the
  display label is left to shinychat, which falls back to the call’s
  title or arguments, unless a tool sets one.

- The slash-command palette takes the composer’s width and left edge and
  sits just above it (shinychat floats it at the caret, at most 400px
  wide).

- Context a UserPromptSubmit hook adds (`additional_context`, and
  `codeagent_server(on_user_prompt =)`) goes to the model in its own
  `<system-reminder>` block. Before, it followed the reminder outside
  the tags, so stripping the reminder left it glued to the user’s text
  in the visible transcript, the history record and conversation titles
  (“Generate t_dmStudy keys …”).

- The approval and AskUserQuestion cards follow the DSH design.
  Approval: amber “Waiting for approval” strip, the full command in the
  code font, Reject / Always allow / Allow once; Enter allows once and a
  click locks the card. Questions: one question per page with numbered
  option rows (checkbox rows for `multiSelect`), a “Recommended” badge
  for labels ending in “(Recommended)”, a free-text row, a pager and
  Skip / Next\|Submit, minimise and dismiss; answers are kept in the
  page and sent together. The “Tool allowed.” / “Tool denied.” chat
  messages stay.

- New workspace tabs for the right panel:
  [`codeagent_workspace_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_workspace_ui.md),
  [`workspace_options()`](https://kaipingyang.github.io/codeagent/reference/workspace_options.md),
  [`codeagent_workspace_kind()`](https://kaipingyang.github.io/codeagent/reference/codeagent_workspace_kind.md)
  and `codeagent_server(workspace =)`, which returns a `ws` object
  (`open`, `close`, `focus`, `pin`, `active`, `tabs`). One tab per
  opened tool result, file or host content, keyed by
  `(kind, content_id)`; close, close others, pin; least recently viewed
  eviction past `max_tabs`; contents stay mounted while hidden. The
  layout is saved with the conversation and restored with it.
  `ui_layout = "dsh"` uses it in its drawer, and like DSH no longer
  opens the panel by itself when a tool call finishes.

- After an interrupt or an error, tool requests left without a result
  are closed with an error result before the turn is saved, so the next
  request and a restored conversation stay valid.

- New `codeagent_history_options(cwd, user, max_store_mb = NULL)`:
  shinychat’s history selector over codeagent’s session log, for
  personal use. Every earlier session of the project is listed, no
  second copy of a conversation is written (the store appends only the
  shinychat record id and titles to the log), and conversations are
  partitioned by user (the owner is written into each new log; logs from
  before belong to the account running the app). `max_store_mb` defaults
  to `NULL` because shinychat’s size limit deletes conversations.
  `ui_layout = "dsh"` uses it; deployed host apps keep
  [`shinychat::history_options()`](https://posit-dev.github.io/shinychat/r/reference/history_options.html)
  with their own store.

- New `codeagent_app(ui_layout = "dsh")`: the page_chat page with a
  DeepSeek-Harness-like structure – shinychat’s conversation history in
  the left column (the model context still comes from codeagent’s
  session log), permission mode and model in the composer row,
  customizations and tool groups in a Settings dialog, and the workspace
  drawer closed until a tool result or file opens it. Pairs with
  `theme = "dsh"`; works with any theme.

- Fixed: with shinychat history active, a streamed reply ended with a
  stray `TRUE` (the presentation-record call was the stream generator’s
  last value).

- Built-in theme rules are files (`inst/themes/{ios,aurora,dsh}.scss`)
  and the Prism setup and voice input load from `inst/www` instead of
  inline strings.

- New theme `codeagent_theme("dsh")` / `codeagent_app(theme = "dsh")`:
  flat layered surfaces after the DeepSeek Harness Web UI design system
  – semantic tokens with dark-mode rebinding, 0.5px hairlines,
  role-based radii, bubble-free assistant replies, a card composer,
  one-line tool rows, and approval / question cards seated where the
  composer is. Not affiliated with DeepSeek; no DeepSeek name, logo or
  brand colour. The interaction bars (approval, question, form, Data
  Shield) are now built from one class-based shell (`ca-interaction*`)
  with the same default look.

- `codeagent_server(on_user_prompt =)`: a host `function(text)` called
  before each turn reaches the model – the host side of the
  `UserPromptSubmit` hook. It returns `NULL`, context to add to the turn
  (the user’s text is never changed), or
  `list(action = "block", message =)`. E.g. facts the host already
  knows, sent with the first turn, that save the model a lookup.

- Fixed: Data Shield replaced every omitted optional attribute of an
  array of objects in tool arguments (NA after ellmer’s conversion) with
  “tool arg redacted: scan failed (fail-closed)” – e.g. AskUserQuestion
  option descriptions after the first. NA leaves are left as they are.

- `AskUserQuestion` follows Claude Code’s public interface as well:
  `questions` asks 1-4 questions at once, each with a `header` chip, 2-4
  `options` (label and description) and `multiSelect`; every question
  offers “Other” with free text. The answers come back as
  `"question"="answer"` pairs. The single `question` / `choices` form is
  unchanged.

- `AskUserForm` has a `grouping` field type: each of its `choices` gets
  a group name the user can edit (preset with
  `default = "A: x, y; B: z"`), and the value is `{group: [choices]}` –
  e.g. combining treatment arms into the columns of a table.

- [`codeagent_chat_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_chat_ui.md)
  fills the width of its container (`width = "100%"`). shinychat’s own
  default caps the chat at 760px, so a host that widened its chat
  sidebar still got a 760px input. `codeagent_chat_ui(width = ...)` caps
  it again.

- Fixed: with a large registered identifier column (e.g. 1e5 subject
  ids), every Data Shield scan of a prompt or tool result took seconds:
  an emptiness check listed the whole value index with
  [`ls()`](https://rdrr.io/r/base/ls.html). It now uses the
  environment’s length; a short scan takes milliseconds again.

- Fixed: with `theme = "glass"` in the classic layout, the chat column
  was squeezed to a narrow strip: shinyglass reserves room on the main
  of a right-side sidebar layout for a sidebar that floats over it, but
  the Workspace has its own column, so that width was taken twice. The
  model picker also no longer gives the left sidebar a horizontal
  scrollbar when a model name is long (all themes and layouts); it
  shrinks and truncates.

- Development pins moved to the 2026-11-15 upstream heads: ellmer
  0.5.2.9000, btw, shinychat (exchange-history fixes; tool-card code
  highlighting), shiny (`MockShinySession` drops a destroyed module’s
  outputs), httr2, shinyglass 0.6.0.9000 and shinygenui (dispatch
  validates raw tool arguments). bslib, mcptools and Rapp are unchanged.

- Fixed: with `CODEAGENT_HOME` set, the one-time migration of a legacy
  `~/.codeagent` still ran and copied the account’s personal sessions,
  settings and skills into it – e.g. a developer’s data into a host
  app’s shared history directory. An explicit `CODEAGENT_HOME` is now
  used as is.

- `codeagent_client(skills =)` lets a host choose the skills it offers
  (the `use_skill` tool, `/name` commands and the prompt’s skill list):
  `NULL` (default) keeps every discovered skill; `FALSE` offers none; a
  character vector names skill directories (every `<name>/SKILL.md`
  inside, relative to `cwd`) and/or discovered skills,
  e.g. `c("skills", "compact")`. An entry that is neither is an error at
  client creation. Before, an embedding app offered the model every
  built-in and user skill, unrelated to its domain.
  [`list_skills_meta()`](https://kaipingyang.github.io/codeagent/reference/list_skills_meta.md),
  [`load_skill_prompt()`](https://kaipingyang.github.io/codeagent/reference/load_skill_prompt.md)
  and
  [`build_skill_hint()`](https://kaipingyang.github.io/codeagent/reference/build_skill_hint.md)
  take the same `skills` argument.

- Fixed: `UserPromptSubmit` hooks ran only in
  [`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md).
  The Shiny chat
  ([`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md),
  [`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)),
  [`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md)
  and the REPL skipped them, so a hook could neither block a turn nor
  add context there. They now run on every entry point, on the text the
  user typed and before the Data Shield input gate, as in
  [`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md):
  a block ends the turn with the hook’s message, and
  `additional_context` is sent with the turn’s system-reminder (the chat
  still shows only what the user typed).

- Host apps: `codeagent_server(on_tool_open =)` is called with a tool
  card’s `ContentToolResult` when the user opens (expands) that card in
  the chat, live or in a restored conversation, e.g. to show it in the
  host’s own panel. Tool results with an HTML display carry a result id
  (`data-ca-result`, recorded with the conversation); the chat reports
  it as `input$ca_tool_open`.

- Fixed: a host tool card built from components with render hooks
  ([`bslib::card()`](https://rstudio.github.io/bslib/reference/card.html),
  `tagFunction()`, widgets) could not be recorded – every later save of
  the conversation failed (“Could not save conversation”, and the
  session log stopped at that turn). Such objects in a tool result’s
  `extra` are rendered to static HTML (dependencies kept) when the tool
  returns; plain tags are left as they are.

- The approval bar has “Always allow” (this tool, this session): allows
  the request, the same tool’s requests already waiting, and every later
  one in the session.

- Host apps:
  [`codeagent_mode_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mode_ui.md) +
  `codeagent_server(modes =)` let the user switch the session’s
  permission mode (e.g. ask before changes / run without asking);
  `codeagent_server(on_restore =)` is called with the Chat after a saved
  conversation is opened from either history backend.

- Fixed: with Data Shield on, `scan_tool_args()` turned a data frame
  argument into a list of its columns and dropped the names of character
  vectors. ellmer passes array-of-objects arguments as data frames, so
  tools saw a different shape – `AskUserForm` rejected every form
  (“Field 1: `name` must start with a letter …”). Argument structure is
  now kept; string values are still scanned and redacted.

- Session files are append-only logs (format version 2), matching the
  public shape of Claude Code’s session log: one entry per new turn
  (display text + lossless record, `uuid`/`parentUuid` chain); a context
  change – compaction, `/rewind`, `/clear` – appends a
  `compact_boundary` entry with a snapshot of the new context. Fixes:
  compaction no longer erases the earlier turns from the file, a
  restored conversation shows all of them (with a note where the context
  was compacted) while the model resumes from the last boundary, and
  [`rename_session()`](https://kaipingyang.github.io/codeagent/reference/rename_session.md)
  /
  [`tag_session()`](https://kaipingyang.github.io/codeagent/reference/tag_session.md)
  entries survive later saves. Version 1 files are read as before and
  migrated on their next save.

- `codeagent_server(history = shinychat::history_options(...))` with
  `codeagent_chat_ui(history = TRUE)`: shinychat’s conversation history
  in a host app. The record holds what the user saw (output gate
  applied, no injected context) and is not shortened by compaction;
  opening a conversation restores the model context from codeagent’s
  session log and the canvas. `history = "codeagent"` is codeagent’s own
  list; `sessions = TRUE` is kept as its alias.

- Host apps can offer saved conversations:
  [`codeagent_sessions_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_sessions_ui.md)
  (the list with New / Delete) and `codeagent_server(sessions = TRUE)`.
  A click restores the conversation with its tool cards and canvas; New
  and restore keep the host’s greeting. The list is the client’s `cwd`
  under `CODEAGENT_HOME`, so a fixed per-user `cwd` gives each user
  their own history across restarts.

- Fixed: a restored conversation showed a host tool’s result as its raw
  value instead of the card the tool returned in `extra$display`
  (title + html / markdown); replay now keeps that card, as the live
  chat does.

- Fixed: with
  [`shield_sandbox()`](https://kaipingyang.github.io/codeagent/reference/shield_sandbox.md)
  whose project root is read-only, every write-capability tool was
  blocked (“sandbox root lacks ‘w’ capability”), even tools with no path
  argument: the sandbox treated the session cwd the permission gate adds
  to each request (`.permission_cwd`) as a path the tool writes. That
  internal argument is no longer checked; real path arguments are.

- Fixed: the canvas Content Security Policy
  (`canvas_options(csp = TRUE)`, the default) had `frame-src 'none'`. It
  applies to the whole host page, so a host that shows its own output in
  an iframe (a report preview, a tool card with an iframe) got a blocked
  frame as soon as the Canvas tab was on the page. Frames from the app
  itself are now allowed (`frame-src 'self'`), as documented; frames,
  images and media from other origins stay blocked.

- Fixed: approval, question, form and Data Shield requests that arrived
  while another one was open (parallel tool calls, a form during an
  approval) replaced it, and the replaced tool – and the turn – waited
  forever. They now queue and are shown one at a time; the bar says how
  many are waiting, an egress request still times out to “redact” while
  queued, and restoring a session resolves every open or queued request
  with its cancel value.

- Fixed: with Data Shield or web citations active, the Shiny app
  buffered the whole stream and showed no tool cards, so results that a
  host tool shows only in its card (`extra$display`) never reached the
  user. Tool requests and results are now shown as the turn runs; only
  the model’s text is held for the output gate. Card arguments pass the
  same gate and are dropped if it would change them.

- Data Shield value matching catches identifiers written differently
  from how they were registered (`register_data(id_variants = TRUE)`,
  the default). For identifier columns only: ids that contain a letter
  also match with separators changed or dropped and leading zeros
  dropped (`BGB 001 0007`, `BGB0010007`, `BGB-1-7`, en dash or no-break
  space for `BGB-001-0007`), and a column with a dominant character
  shape and a literal letter prefix contributes a pattern such as
  `BGB-[0-9]{3}-[0-9]{4}` that also catches ids that were never
  registered (another study, an unloaded subject). Purely numeric ids
  keep exact matching only – their variants cannot be told apart from
  decimals and counts. Variant keys count toward `max_index_values`,
  [`close()`](https://rdrr.io/r/base/connections.html) drops them, and
  the reviewer text path redacts them too. The segment-run cap adapts to
  the longest indexed id (at most 12 parts). `USUBJID` / `SUBJID`
  columns are classified as identifiers by name.

- Fixed: the default `phone` regex redacted ISO dates (`2024-01-15`) and
  clinical count-percent cells (`40 (100.0%)`) in tool results and
  replies. It now matches written phone forms only (`+<country>`
  followed by three or four groups, `+<10-15 digits>`, `555-123-4567`,
  `555.123.4567`, `(555) 123-4567`, 11-digit mainland-China mobiles), so
  count rows (`100 200 3000`) and signed changes (`+10 25 30`) also stay
  clear.

- Fixed: value_match tokenized text with `strsplit(perl = TRUE)`, which
  is quadratic on long input – a 0.5 MB tool result took ~40 s per scan.
  Scans now grow with the length of the text: under a second for that
  result, and variant lookups use a hashed table, so a large index (10^5
  ids) does not slow them down.

- New
  [`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md),
  [`codeagent_chat_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_chat_ui.md),
  [`codeagent_canvas_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_canvas_ui.md)
  and
  [`codeagent_head_assets()`](https://kaipingyang.github.io/codeagent/reference/codeagent_head_assets.md)
  embed codeagent’s chat engine in a host Shiny app that has its own
  page and tools: streaming with compaction and interrupt, `/skill`
  commands, hooks, the approval / question bar, the generative UI
  canvas, Data Shield and per-turn session saving. Host tools are passed
  with a declared capability and are registered inside the normal tool
  setup, so result normalization, input hooks, `disallowed_tools`, the
  permission gate and the shield cover them exactly like built-ins. A
  tool-setup failure now fails closed (no tools, input stays disabled).
  One client serves one open session.
  [`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
  now runs on the same per-session core.

- New `AskUserForm` tool
  ([`ask_user_form_tool()`](https://kaipingyang.github.io/codeagent/reference/ask_user_form_tool.md),
  [`register_ask_user_form_tool()`](https://kaipingyang.github.io/codeagent/reference/register_ask_user_form_tool.md),
  capability group `interact`): the model shows a small form – text,
  textarea, number, select, multiselect, checkbox and date fields with
  defaults, required flags and hints – and gets back
  `{submitted, values}`. In Shiny it opens in the chat’s interaction
  area; Cancel and ESC report `submitted = false`. The CLI asks field by
  field.

- `codeagent_client(setting_sources =)` /
  `load_settings(setting_sources =)`, named after the Claude Agent SDK
  option, pick which filesystem sources are loaded: `"user"`
  (`~/.codeagent/settings.json` and the user-level `CLAUDE.md` files)
  and `"project"` (`.codeagent/settings.json` and the `CLAUDE.md` /
  `AGENTS.md` files from `cwd` up). The default loads both. An app that
  ships its own instructions passes `"project"`, so it never picks up a
  developer’s personal `settings.json` or `CLAUDE.md` when it runs under
  their account – also not after `/model`. `CODEAGENT_*` variables in
  `~/.Renviron`, auto-memory and user-level skill directories are not
  covered (point `CODEAGENT_HOME` elsewhere for those).

- Fixed: Data Shield value matching missed compound identifiers. Text
  was split on every non-alphanumeric character, so a CDISC `USUBJID`
  such as `BGB-001-0007` became `BGB` / `001` / `0007` and never matched
  the indexed value; such ids passed tool-result egress and reply
  scanning untouched. Every contiguous run of
  hyphen/underscore/slash-joined segments is now a candidate, so an id
  is caught whole even when joined to other words
  (`BGB-001-0007_AE.csv`, `subject/BGB-001-0007`), and replies redact it
  whole.

- A tool’s `ContentToolResult` value that JSON cannot encode (an R
  `table`, an S4 object) is now sent as its printed text instead of as a
  list, so it no longer bypasses Data Shield’s egress scan.

- Fixed: a tool returning
  `ContentToolResult(value = <list or data frame>)` made
  OpenAI-compatible providers answer HTTP 400 under ellmer 0.5
  (“expected one of a string or array of objects, but got an object”).
  Result normalization now encodes such a value to one JSON string and
  keeps `extra`.

## codeagent 0.2.3

- `theme = "glass"` now needs shinyglass 0.5.0 or later and leaves all
  of its look to shinyglass, which styles shinychat’s page, drawer and
  composer and follows the dark-mode toggle itself. codeagent’s own
  shinychat surface rules and dark-mode bridge are gone: under 0.5.0
  they doubled the composer and greyed the workspace. The workspace and
  chat cards opt out of shinyglass’s refraction lens
  (`data-glass-no-refract`), and the composer’s footer row stays with
  the composer when an empty chat centres it.

- The Data Shield input gate reads text attachments sent as ellmer
  `ContentDocument`, the form shinychat uses since its
  [\#419](https://github.com/kaipingyang/codeagent/issues/419). Before,
  such a document had no readable text, so with a shield active every
  text attachment was blocked as unverifiable; now its content is
  decoded and scanned like any other attachment – a protected value
  still blocks the turn.

- New
  [`canvas_options()`](https://kaipingyang.github.io/codeagent/reference/canvas_options.md),
  [`canvas_component_output()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_output.md)
  and
  [`canvas_component_widget()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_widget.md),
  and `codeagent_app(canvas = )`. The host picks which of shinygenui’s
  components the canvas offers (`starter = TRUE`, `FALSE` or a subset)
  and adds its own, built from any Shiny output/render pair or any
  htmlwidget or HTML. Host components get the same canvas tooling as the
  built-in ones – read-only registration by exact name, the
  transactional executor, Data Shield, strict restore whose identity now
  follows closures into the builder’s render function – and decide for
  themselves what they render. `csp` and `validate_text` loosen the
  page’s Content Security Policy and the model-text check when
  components need it. Without shinygenui’s own components, ggplot2 and
  DT are no longer required.

- Fixed: restoring a canvas could hand a component the arguments or data
  of the last component restored. Data accessors were created inside the
  restore loop, and arguments that a component’s UI never touched stayed
  lazy until its render function ran; both are now fixed when a
  component is mounted.

- Canvas components can now be redrawn from current data. Each component
  remembers a fingerprint of the data frame it was drawn from; after a
  turn that changed it, the component shows a “Data changed” badge and
  the per-turn reminder marks it. The model refreshes with the new
  `canvas_refresh` tool (one id or all), the user with the Canvas tab’s
  **Refresh data** button. A refresh re-runs shinygenui’s checks against
  the new data first, so a vanished column keeps the old view instead of
  breaking it, and it never enters the trace. Restoring a session whose
  data changed since the save draws the current data and says which
  components changed.

- The generative UI canvas now takes every component shinygenui
  provides: `canvas_markdown_card` (plain markdown; links, images and
  URLs are refused before rendering) and the `canvas_card_row`
  container, whose children go in through `parent_id`, nest at most two
  levels deep, and are re-mounted when the container is updated.
  Components are admitted only when every argument type is one
  shinygenui re-validates on replay, and a saved canvas is bound to the
  components’ ui/server/check implementations and the shinygenui
  version, so an upgraded implementation fails closed on restore instead
  of replaying silently. Plots follow dark mode, the workspace tab strip
  no longer shrinks under a tall canvas, and canvas tool cards label the
  instance rather than repeating their title.

- [`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
  gains a generative UI canvas built on
  [shinygenui](https://nanx.me/shinygenui/) (Suggests, with
  [ggplot2](https://ggplot2.tidyverse.org) and
  [DT](https://github.com/rstudio/DT) for its starter components). The
  model draws value boxes, tables, scatter plots and histograms from
  data frames in the R session onto a new Canvas tab in the Output
  workspace, through eight `canvas_*` tools in the `genui` group.
  codeagent consumes only shinygenui’s pure functions and owns
  everything else: the tools pass the central gate (declared `read` by
  exact name, never by prefix), Data Shield, shinygenui’s validation, a
  canvas-output check (no markup, links, URL schemes or control
  characters) and quotas before the DOM changes; create and update are
  transactional, and each mount runs in a Shiny module scope destroyed
  on removal. The canvas is persisted in the same session file write as
  the chat, restored strictly (fail closed on catalog drift, unbound
  requests or failed replay), rolled back with `/rewind` and `/clear`,
  and closed to changes after a cancel. Per-session apps enable it by
  default when the packages are installed; a shared pre-built client
  only with `tools = "genui"`; `disallowed_tools = "genui"` turns it
  off. The CLI never registers canvas tools, and naming `genui` there is
  not reported as unfulfilled.
  [`save_session()`](https://kaipingyang.github.io/codeagent/reference/save_session.md)
  gains `genui_state=`.

- A `tools=` entry that registers nothing now warns and names the entry.
  btw drops a tool group whose optional dependency is missing (`git`
  without [gert](https://docs.ropensci.org/gert/), `github` without
  [gh](https://gh.r-lib.org/)) and reports it only as a once-per-session
  note that does not say which request it defeated, so naming a group
  could quietly yield zero tools. Requesting a group and also passing it
  to `disallowed_tools` is reported the same way, since the
  contradiction is worth surfacing. This warns rather than errors – a
  missing optional dependency should not stop a client from being built
  – and is skipped on worker rebuilds, which have no user to tell.

- Sub-agents and team workers now inherit the parent’s `tools=` /
  `disallowed_tools=` selection through the worker security snapshot.
  Before, a parent restricted to a few tools still had its workers
  register the full set and then filter back down against
  `allowed_tools`, which produced the right final tool set but built
  everything first – including the skill scan. The selection is now a
  cheap first layer applied at registration; `allowed_tools` (the
  parent’s actual tool names plus signatures) remains the authority a
  worker can never exceed. A snapshot written before this field existed
  decodes to “register everything”, so old contexts are unchanged.

- Fixed `register_tool_meta(capability = "read")` being ignored by the
  permission system. A host tool declared read-only was denied in `plan`
  mode and prompted for in `default` mode, contradicting the function’s
  own documentation. Three independent defects were in that path:
  [`check_permission()`](https://kaipingyang.github.io/codeagent/reference/check_permission.md)
  decided read-only from a hard-coded list of native tool names and
  never consulted the resolved capability; `.gate_decide()` discarded
  the capability the gate had resolved from the live tool object; and
  [`register_tool_meta()`](https://kaipingyang.github.io/codeagent/reference/register_tool_meta.md)
  defaults to set `"C"` while the default policy enabled only
  `c("A", "B")`, so a declared host tool was denied in **every** mode
  including `bypass`, with no diagnostic. Default tool sets are now
  `c("A", "B", "C")` – that registry is populated only by an explicit
  host call, and an undeclared tool is still denied on `known = FALSE`
  before any set check. Built-in metadata remains authoritative, so a
  host still cannot downgrade `Bash` by claiming `"read"`.

- btw tools are now classified from the `read_only_hint` each tool
  declares, instead of only a prefix scan that had drifted. Eight tools
  were misjudged as needing a permission prompt – `git_status`,
  `git_diff`, `git_log`, `git_branch_list`, `ide_read_current_editor`,
  `pkg_coverage` and `skill` were treated as `exec`. Only `exec` is
  relaxed: `web_read_url` declares itself read-only but keeps its `net`
  capability, because reaching the network is an independent dimension
  from not mutating state. A missing or false hint keeps the
  conservative result, so a new btw release can only ever be classified
  correctly or conservatively, never dangerously.

- Added `codeagent_client(tools=)`, one capability namespace that
  selects what gets registered: `NULL` for everything (the historical
  default), `FALSE` for nothing (tools the host registered on the Chat
  are kept), or a mix of capability groups, individual tool names, and
  btw group names. The two capabilities with parallel implementations
  take an `@` suffix – `files@core` / `files@btw` / `files@both` and the
  same for `web` – which folds the `file_tools` switch and btw’s Path A
  into the same selection. Unknown names are an error listing the valid
  groups rather than a silent drop. `btw_groups=` is superseded by it;
  supplying both is an error.

- Added `codeagent_client(disallowed_tools=)`, which carries the same
  two meanings as the Claude Agent SDK’s public argument: a bare name
  (tool or capability group) removes the tool definitions so the model
  never sees them, while a scoped entry such as `"Bash(rm *)"` keeps the
  tool and becomes an ordinary deny rule, absolute in every permission
  mode including `bypass`.

- Added drift guards for the btw integration: `.BTW_GROUPS` must cover
  every group the installed btw ships, and every codeagent-native tool
  must declare a capability group. This caught `.BTW_GROUPS` still
  describing btw 1.2.1 while btw 1.5.0 was installed – `run` and
  `skills` were missing, so passing either name reported “unknown group”
  instead of naming the codeagent tool that owns the capability (`RunR`,
  `use_skill`). When btw next adds a tool or group, these tests fail on
  purpose so the classification is a decision rather than a fall-through
  to the “unknown -\> exec” default.

- Reduced streaming startup and finalization overhead by reusing a small
  async driver and moving synchronous event dispatch outside the
  coroutine state machine. A callback-driven iterator keeps one
  completion promise and waits for asynchronous iterator cleanup before
  releasing ownership. Text is accumulated in chunks. Async-turn
  ownership now unwinds even when stream creation and error notification
  both fail. JIT, Shiny deep stacks, callback ordering, Data Shield, and
  citation buffering remain enabled. This does not eliminate ellmer’s
  internal high-rate streaming overhead.

This patch release adds optional Liquid Glass theming, fixes tool-card
behavior, and closes security/integration blockers found during PR
review. It includes one intentional safe-default change:
[`team_lead()`](https://kaipingyang.github.io/codeagent/reference/team_lead.md)
now defaults to `"dont_ask"`.

### Security and reliability

- Made matching explicit deny rules absolute across capability allows,
  per-tool overrides, modes, and read fast paths; initial plan sessions
  can no longer invoke `ExitPlanMode` without a trusted in-session
  `EnterPlanMode` transition.
- Replaced sandboxed Bash
  [`system2()`](https://rdrr.io/r/base/system2.html) execution with
  `processx` argv execution and a full replacement environment, confined
  Glob patterns and symlink results, and made the Data Shield portable
  policy block every non-delegated exec tool—including path-declared
  `Lint`, whose project `.lintr` may execute R code—until a real OS
  sandbox is available.
- Made PreToolUse installation and runtime exceptions fail closed, and
  rebuilt delegation guidance from the final live tool registry so
  missing/failed Agent or TeamRun registration is never advertised.
- Preserved dynamic plan-mode state when a Shiny permission/tool refresh
  rolls back.

### Behavior changes

- Changed
  [`team_lead()`](https://kaipingyang.github.io/codeagent/reference/team_lead.md)’s
  default `permission_mode` from `"bypass"` to `"dont_ask"`. Existing
  trusted write workflows must now opt in explicitly to a more
  permissive mode; read-only review workflows continue to work with the
  safer default.

### Shiny UI

- Replaced the built-in glassmorphism imitation with optional,
  exact-pinned `shinyglass` material rendering.
  `codeagent_theme("glass", ...)` now forwards Liquid Glass controls
  such as `preset`, `intensity`, `tint`, and `specular` to shinyglass,
  while codeagent owns only a thin shinychat
  header/sidebar/drawer/composer token adapter and dark-mode bridge.
- Changed artifact-backed tool cards to stay collapsed after successful
  completion regardless of output length; error cards still open by
  default. This prevents normal long Read, Grep, and `use_skill` results
  from making the interface appear permanently expanded.

### Documentation

- Added a bilingual pkgdown Shiny theme gallery with real Chromium
  screenshots of the Liquid Glass light and dark modes.

## codeagent 0.2.2

This backward-compatible release adds adaptive request-boundary
compaction, adopts ellmer’s request lifecycle hooks, and expands the
Shiny theme system while preserving public interfaces.

### Core

- Reworked request-boundary compaction into an adaptive, model-aware
  pipeline: cheap result replacement and micro snip run before
  structured fresh recount; incremental/full summaries run only when
  still needed and are post-validated. Summary input now preserves tool
  request/result structure, PTL recovery drops pair-safe complete
  rounds, and compaction lifecycle hooks expose metadata only.

- Updated the pinned ellmer development build to official `main` SHA
  `2e96ac58a33d74bea585727daf8cd1535c67d7f1`, which includes the merged
  `Chat$on_request_start()` / `Chat$on_request_end()` callbacks from
  tidyverse/ellmer#1052.

- Migrated mid-loop compaction from the per-tool `on_tool_result`
  workaround to `on_request_start`, so context is checked before every
  model request. Threshold accounting now includes the complete outgoing
  turns, including a pending tool-result turn, while history rewrites
  continue to use ellmer’s supported `get_turns()` / `set_turns()`
  contract.

- Adapted verified name-only model switching to ellmer’s new `Model`
  ownership: deprecated Provider model fields are excluded from provider
  identity checks, while `Model` params and extra arguments remain
  strictly compared before an in-place switch.

### Shiny UI

- Fixed the runnable theme/page-chat examples for Workbench and RStudio:
  they now preserve the `shiny.launch.browser` proxy launcher and bind
  to `0.0.0.0` when Workbench URL environment markers are present, while
  ordinary environments remain loopback-only. Previously the proxy could
  open a blank page because the app listened only on `127.0.0.1`.
- Added the independently selectable `theme = "aurora"`: static
  blue-indigo-purple ambient light with selective frosted sidebars,
  drawers, and composer controls, while chat, code, tool-result, table,
  and artifact surfaces remain high-opacity for sustained readability.
  Includes dark-mode, reduced-transparency, reduced-motion, and
  no-`backdrop-filter` fallbacks.
- Unified the classic and `page_chat` layouts on shinychat’s official
  `page_chat_theme()` foundation. Added exported
  [`codeagent_theme()`](https://kaipingyang.github.io/codeagent/reference/codeagent_theme.md),
  built-in `theme = "ios"`, and direct pass-through of custom bslib
  themes (including `shinychat::page_chat_theme(...)`).
- Refined the iOS preset with a Young Voice-style grouped canvas,
  compact 14px white cards, lightweight borders and shadows, white
  sidebars, and a bottom-anchored composer beside the voice/file footer
  actions.
- Refreshed artifact/tool-result cards with bslib white surfaces and
  shinychat-aligned Atom One syntax colors, replacing Prism’s legacy
  gray code background and text shadow.

## codeagent 0.2.1

This is a backward-compatible release focused on portable tool results,
current upstream integrations, Shiny presentation, safety, and
documentation.

### Portable tool results

- Added a versioned, UI-neutral tool-result artifact v1 contract
  (`codeagent.tool-artifact`) with public
  [`tool_result_artifact()`](https://kaipingyang.github.io/codeagent/reference/tool_result_artifact.md)
  and
  [`tool_result_value()`](https://kaipingyang.github.io/codeagent/reference/tool_result_value.md)
  accessors. Streaming callbacks now expose `artifact`, the optional
  official shinychat `display` adapter, and the portable `value`
  fallback, allowing non-shinychat hosts to render native components
  without parsing shinychat HTML.
- Preserved the official shinychat presentation path, including framed
  rich cards, while making malformed or unsupported artifact metadata
  fail soft. See
  [`vignette("tool-artifacts")`](https://kaipingyang.github.io/codeagent/articles/tool-artifacts.md)
  for the schema, version negotiation, security boundary, and migration
  guide.

### Shiny and upstream integration

- Added the opt-in full-window `page_chat` layout with a 100%-width main
  chat, official `page_chat_theme()` baseline, persistent dark-mode and
  Workspace toolbar, resizable Output / Files / File drawer, attachment
  staging, and official shinychat tool displays. The classic layout
  retains its embedded width and disables unused native drawer/history
  presentation.
- Improved greeting, slash-command, tool-display, session replay, file
  preview, and atomic settings/tool-group behavior while preserving
  codeagent ownership of streaming, permissions, sessions, and Data
  Shield.
- Added opt-in support for ellmer provider-native `ContentCitation` /
  `WebSource` content. Native citations are converted to opaque
  current-turn server references and rebuilt through the same fixed
  `<shiny-aside>` allowlist as custom WebSearch/WebFetch citations;
  provider and model markup is never trusted directly.
- Citation claims, grounded spans, titles, quotes, and URLs pass through
  Data Shield and the public-URL policy. Citation mode remains
  buffer-then-show, rejects unsafe or prior-turn references, supports
  multiple sources per grounded span, and safely rebuilds lossless
  session replay.
- Re-pinned ellmer to GitHub HEAD
  `a64f94e644718c0598b01b0cd50a3c21c2646435`, including refreshed
  bundled model/pricing data and Bedrock API mappings, without upgrading
  unrelated CRAN packages.
- Unified the MCP client, server, child-process guard, tests, and
  documentation on `mcptools >= 1.0.2.9000`; the architecture
  documentation now reflects Streamable HTTP, static headers, and OAuth
  discovery, PKCE, and token-refresh support.

### Safety and compatibility

- Hardened Data Shield input, tool, and output boundaries, fail-closed
  handling, sandbox and network policy, reviewer isolation, audit
  metadata, and protected-data schema/context behavior.
- Shiny Agents discovery now supports project and user
  `.btw/agents/*.md` directories alongside Claude and legacy
  `.btw/agent-*.md` locations, excludes `.btw/btw.md`, and honors YAML
  `name` metadata.
- Fixed the WEAR report tool to register under the stable
  `GenerateReport` name expected by the built-in `/report` skill.
- Updated CLI, session, and tooling behavior for compatibility with the
  pinned ellmer, btw, shinychat, bslib, and Shiny development builds.

### Documentation

- Audited every pkgdown article against the current implementation,
  corrected stale API, default, and behavior descriptions, and added
  complete Simplified Chinese counterparts with reciprocal language
  links and a dedicated Chinese documentation group.

## codeagent 0.2.0

- **Data Shield security hardening (second-round audit): 16 boundary
  fixes, all fail-closed.** A follow-up security review found several
  paths where the shield could silently fail *open*; every one is now
  closed:

  - **Input/output gates fail closed.** A scan exception, an unknown
    (typo’d) scanner name, an already-closed shield, or an unextractable
    attachment no longer passes the raw text through — the gates now
    block/redact, matching the tool-side ingress (which was already
    fail-closed).
  - **Full turn-boundary coverage.** The one-shot
    [`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
    and the non-streaming REPL path now run both the input and output
    gates; `agent_loop` falls back to the settings hook registry when
    none is passed.
  - **Streaming output gate really redacts.** When a shield is active,
    the Shiny and CLI streaming paths **buffer** the reply, scan it,
    then show the (possibly redacted) text once — instead of streaming
    plaintext to the screen and appending a warning after the fact.
    Without a shield, streaming is unchanged.
  - **Tool boundary sees nested args and async results.**
    `scan_tool_args` recurses into nested list string leaves; the egress
    wrapper awaits a promise-returning tool and scans the *resolved*
    value.
  - **`egress = "none"` is a real deny**, not a silent pass; the
    reviewer rail is reachable (`review_code_public()`);
    [`refresh_data_shield_context()`](https://kaipingyang.github.io/codeagent/reference/refresh_data_shield_context.md)
    works for a bare `Chat`; tool re-registration re-installs the shield
    wrapper; a rewritten PreToolUse input is re-checked against the gate
    authority.
  - **Code audit precision + read safety.** The static source-reference
    audit only treats a *literal* path argument as static (nested
    [`file.path()`](https://rdrr.io/r/base/file.path.html) /
    [`paste0()`](https://rdrr.io/r/base/paste.html) / a variable are
    flagged dynamic); binary R-data blobs are not text-audited; files
    are read with a byte cap and a TOCTOU re-check.
  - **Lifecycle & isolation.** Reviewer isolation is verified (not
    best-effort); [`close()`](https://rdrr.io/r/base/connections.html)
    clears strategies, both pipelines, and custom-scanner closures, with
    an R6 finalizer backstop and a Shiny session-end close; the
    no-network sandbox marks (and warns once) when OS isolation is
    unavailable.
  - **Compatibility shims.** `HookEvent$USER_MESSAGE` and
    `run_user_message()` are restored as deprecated aliases;
    `register_data()` errors clearly if `column_access` is passed in an
    old positional slot.

- **Bash sandbox gains OS-level no-network isolation via unprivileged
  namespaces.** When the Bash sandbox runs with `allow_network = FALSE`
  and `unshare` is available, commands are wrapped in `unshare -Urn` (a
  user+network namespace with no interface), so any
  `connect()`/`socket()` fails at the kernel level regardless of how the
  command is written — a bounded syscall boundary, not a bypassable
  command blacklist (e.g. `/dev/tcp/...`, which the `curl`/`wget`
  blacklist never catches, is now blocked). The blacklist is kept as a
  cheap first line; when `unshare` is unavailable the sandbox degrades
  to it. Network-allowed sandboxes and RunR are unchanged (RunR keeps
  callr + blacklist for now — wrapping callr’s internal fork in
  `unshare` is deferred).

- **PreToolUse hooks can now rewrite a tool’s arguments before it runs**
  (aligns with the Claude Agent SDK’s `updatedInput`). A `PreToolUse`
  hook that returns `list(action = "updated_input", input = <new args>)`
  changes what the tool executes with; `list(action = "deny", ...)`
  rejects the call. Because ellmer’s `on_tool_request` is
  rejectable-only (a callback cannot rewrite the request), the rewrite
  happens one layer in: each tool is wrapped (`.wrap_tool_pre_hook`) so
  the hook runs inside the tool function, after the permission gate.
  Ordering is `gate -> wrapper -> original`, so a rewrite can never
  bypass permission checks (the gate always sees the original args), and
  the tool’s JSON schema is unaffected (ellmer derives it from the
  `@arguments` slot, not the wrapped function’s formals). Zero ellmer
  patching.

- **Data Shield redacts protected values inside tool arguments**
  (ingress rewrite, symmetric to the existing egress scan).
  `DataShield$scan_tool_args()` scrubs registered values / PII from each
  string argument using the same detectors as `scan_prompt`; a value
  pasted into a tool argument is redacted rather than the whole call
  being blocked. Runs in `.data_shield_wrap_tool` after the permission
  gate.

- **Data Shield now injects protected-dataset schemas into the system
  prompt** (querychat-style ambient visibility). When a shield is
  active, every registered dataset’s *filtered* schema (the same output
  `DescribeData` produces – identifier values suppressed, rare
  categories hidden) is placed in a `<protected-data>` block in the
  system prompt, so the model knows what protected data exists and its
  column structure without having to call `DescribeData` first
  (previously it would fabricate column names/dims when it didn’t call
  the tool). The `DescribeData` tool is retained as the live, on-demand
  fallback. **Behavior change**: existing shielded clients now get a
  longer system prompt. Data registered *before* the client is built is
  in the initial prompt automatically; for data registered/uploaded at
  runtime, call the new exported `refresh_data_shield_context(client)`
  after `register_data()` (e.g. in a Shiny upload handler) to rebuild
  the system prompt with the new dataset – this preserves conversation
  history and only costs a one-time prompt-cache miss. `register_data()`
  deliberately does **not** auto-refresh, keeping the shield decoupled
  from the Chat. Scope note: this is edge-1 *visibility* only; switching
  a dataset’s security mode mid-conversation is a non-goal (the context
  window is immutable – the correct reset is a fresh conversation).

- **Output gate (edge 3): Data Shield now scans the model’s final reply
  before it reaches the user.** Data Shield previously guarded the two
  edges *into* the model (edge 1 input gate, edge 2 tool gate) but not
  the reply *out* to the user – so a model that reproduced a protected
  value it inferred from tool output (an aggregate edge 2 let through)
  leaked it even when the user’s own input was clean. The output gate
  (`R/output_gate.R`
  [`.output_gate_scan()`](https://kaipingyang.github.io/codeagent/reference/dot-output_gate_scan.md) +
  `DataShield$scan_response()`) closes this, reusing the same
  value_match + PII detectors as the input gate (audited under
  `edge = "response"`). CLI (`agent_loop`) is non-streaming and
  **redacts the reply in place**; when a shield is active the Shiny and
  CLI streaming paths now **buffer the reply, scan it, then show the
  (possibly redacted) text once** – nothing reaches the browser until
  the output gate has run (no plaintext-then-warning). Configurable via
  `settings$data_shield_response_on_fail` (`redact`/`block`/`ask`) and
  `settings$data_shield_output_scanners`. This brings Data Shield to the
  canonical three-edge coverage (input / tool / output), matching the
  output rail of NeMo Guardrails / the Output Guard of Guardrails AI.

- **Input and output gates take a configurable scanner list.**
  `settings$data_shield_input_scanners` / `data_shield_output_scanners`
  (default `c("value_match", "regex")` – secure-by-default) let a host
  drop a detector, e.g. `c("value_match")` to keep registered-value
  matching but skip PII regex. Backed by a new `scanners=` argument on
  `DataShield$scan_prompt()` (default runs both, fully backward
  compatible).

- **Input gate (edge 1): Data Shield now scans all user input before it
  reaches the model.** Previously Data Shield only guarded tool traffic
  (edge 2: `scan_ingress`/`scan_egress`); the user’s own message went to
  the model unscanned. The input gate (`R/input_gate.R`
  [`.input_gate_scan()`](https://kaipingyang.github.io/codeagent/reference/dot-input_gate_scan.md))
  adds edge-1 protection over **all input**: typed text and text-bearing
  attachments are scanned via `DataShield$scan_prompt()` (registered
  protected value pasted in via value_match O(1) hash lookup + PII/token
  shapes via regex), and by default it **redacts only the matched spans
  while keeping the rest of the user’s text**
  (`on_fail = "redact"`/`"block"`/`"ask"`). Image attachments are a
  blind spot by default; an optional `data_shield_image_scanner` hook
  (default `NULL`) lets a host inject an OCR/VLM scanner. A
  `on_progress` callback lets a UI show “scanning data safety…”. Wired
  at the UserPromptSubmit point of **both** entry paths — the agent
  loop (CLI) and the Shiny stream. Two systems stay separate: the
  UserPromptSubmit **hook** may block/append but never redacts (CC
  parity); the Data Shield **input gate** may redact (its
  confidentiality job).

- **[`data_shield_ocr_scanner()`](https://kaipingyang.github.io/codeagent/reference/data_shield_ocr_scanner.md):
  an opt-in OCR image scanner for the input gate.** Closes the image
  blind spot for text baked into screenshots: it OCRs the attachment
  with the optional package (a `Suggests` dep), then runs the extracted
  text through `scan_prompt()`, blocking the turn on a protected-value
  hit. Opt-in (scheme A) — the default `data_shield_image_scanner` stays
  `NULL`; wire it explicitly via
  `settings$data_shield_image_scanner = data_shield_ocr_scanner(shield)`.
  When is not installed the scanner degrades to `pass` (never blocks on
  a missing optional dep).

- **The input gate now also runs on the Shiny app’s real stream path**
  (`server_chat.R` `stream_task`), not only the standalone
  [`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md).
  Uploaded attachments and typed text in the app are scanned at edge 1
  before reaching the model; a block ends the turn with a chat message,
  a redact continues with the sanitized input.

- **`UserPromptSubmit` hook can now block or add context** (was
  notify-only). Renamed `UserMessage` -\> `UserPromptSubmit` to align
  with Claude Code’s public hook event name. A hook may return
  `action = "block"` (the prompt never reaches the model) or
  `"add_context"` (append text to what is sent) – never rewrites the
  user’s original wording, matching CC’s contract. `run_user_message`
  -\> `run_user_prompt_submit`.

- **Hooks aligned with Claude Code’s 27 lifecycle events** (was 12).
  Events with a real trigger fire live: `SessionEnd`, `PostCompact`,
  `StopFailure`, `Notification`, `TaskCreated`/`TaskCompleted` (through
  the TaskCreate/TaskUpdate tools), and `InstructionsLoaded` (replayed
  from the loaded CLAUDE.md files). `FileChanged`/`ConfigChange` are
  driven by the `watcher` package and work in BOTH the Shiny app and the
  CLI REPL – the prompt reads keys non-blockingly so an idle session
  still dispatches filesystem-watch callbacks (needs `watcher`
  installed; no-op otherwise). Remaining CC events are defined for a
  complete allowlist but have no live trigger yet
  (`Elicitation`/`ElicitationResult` need MCP elicitation;
  `TeammateIdle`/`Setup`/`CwdChanged` have no matching phase;
  `WorktreeCreate`/`WorktreeRemove` deferred until cross-process team
  events). `AssistantMessage` stays notify-only (Claude Code has no such
  event).

- **Bounded value-match index**: `register_data(max_index_values=)` caps
  the value-match hash index (default 500000 values, ~65MB of keys).
  Benchmarked on open-source CDISC-ADaM-format example data from the
  {pharmaverse} project (`inst/bench/value_match_benchmark.R`): index
  memory grows linearly and unbounded (~130MB / 1M values), so on
  overflow `register_data()` now **errors and refuses the dataset** (a
  partial index that silently drops tail values would fail open) – raise
  `max_index_values`, register in smaller pieces, or set it to `Inf`.
  Zero false positives on ordinary clinical prose and pharmaverse-format
  USUBJID/SUBJID caught, so the min_len/min_card thresholds are
  unchanged.

- **Column-level raw access**: `register_data(column_access=)` grants
  per-column raw access on a protected data.frame (e.g. a public
  `TESTCD` codelist beside protected columns), reusing the asset
  `none`/`schema`/`scan`/`raw` levels split into `prompt`/`egress`.
  `prompt="raw"` makes `DescribeData` enumerate the real values (no
  k-anonymity suppression); `egress="raw"` drops the column from the
  value-match index. A raw edge requires a non-empty `reason`; an
  override missing it now **errors** (registration is refused) rather
  than being silently dropped, so a mis-typed raw grant cannot pass
  unnoticed. `coverage()$raw_access_columns` counts overrides.

- **Extensible ingress blacklist**: built-in
  [`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md)
  rules moved to a grouped `.DATA_SHIELD_INGRESS_RULES` constant and
  expanded (pandas `to_*`, more R writers, `urllib`/`httpx`/`aiohttp`,
  `nc`/`scp`/`rsync`/`/dev/tcp`, inline `-e`/`-c` eval). A `patterns=`
  name matching a built-in now **replaces** that rule (was append-only);
  new names are added. Hosts wanting file-managed blacklists read their
  own file into a named vector and pass it via `patterns=`.

- **Small-model semantic code reviewer**: new
  [`shield_reviewer()`](https://kaipingyang.github.io/codeagent/reference/shield_reviewer.md)
  is an optional internal ingress rail (never a model-callable tool). It
  reviews only deterministic PII/value-sanitized tool code/arguments
  with a fresh, tool-less, history-free ellmer Chat. Explicit
  `client_factory` wins; otherwise the parent provider is reused with
  `CODEAGENT_FAST_MODEL` (never silently the main model). Scope defaults
  to exec/write/net; risk/error independently choose ask/block; async
  turns await a timed promise. Structured JSON parsing and reviewer
  failures fail closed. Remote mode never receives raw data/output; raw
  review is reserved for an explicit future local-only egress mode.

- **Data Shield egress approval**: `shield_egress(on_fail="ask")` pauses
  after a local tool executes but before its result reaches the LLM.
  Default choices are Redact/Block; dangerous `ALLOW RAW ONCE` appears
  only with explicit `allow_raw_approval=TRUE` and never changes future
  policy. CLI uses synchronous selection; Shiny uses a promise-backed
  three-button interaction. Missing callbacks, invalid choices, errors
  and timeouts default to redact. Approval payloads/audit contain
  metadata only, never the raw result.

- **Portable sandbox policy**: new
  [`shield_sandbox()`](https://kaipingyang.github.io/codeagent/reference/shield_sandbox.md)
  keeps project/session-temp path capabilities at `rwx` while the
  central gate validates explicit path arguments against
  project/protected/temp roots, follows real paths to reject symlink
  escape, and enforces per-root `r/rw/rwx`. Because portable path policy
  is not process isolation, every non-delegated exec tool fails closed
  until a full OS adapter is available; this includes path-declared
  tools that can run project configuration. `backend="auto"` honestly
  falls back to policy (or blocks in required mode); coverage/audit
  report the fallback. btw file tools are also covered, and btw RunR is
  not treated as an OS sandbox.

- **Per-tool/agent Shield policy**: new
  [`shield_tool_policy()`](https://kaipingyang.github.io/codeagent/reference/shield_tool_policy.md)
  supports exact or `*`-glob rules with `scan` (default), explicit
  audited `bypass`, and `deny` independently for execution, ingress and
  egress. Trusted tools such as KMPlot may bypass only egress while
  retaining ingress scans; deny blocks execution. Shield bypass never
  bypasses the separate central permission gate.

- **Data Asset Policy** separates what an asset is (`kind`:
  dataset/spec/ document/synthetic) from what the LLM may see
  (`llm_access`: prompt/egress none/schema/scan/raw). Kind-specific
  defaults keep datasets schema-only while allowing specs/synthetic
  prompt content; egress never defaults raw. Raw access requires a
  reason, is session-scoped with optional expiry, is audited, and
  requires explicit provenance via `$trusted_result()`. Synthetic/raw
  always runs baseline PII/secret regex; spec/raw may explicitly disable
  it.

- **Non-sensitive Data Shield audit log**: every blocked/asked ingress
  decision and redacted/blocked egress event records timestamp, edge,
  tool name/call id, strategy, action, reason label, match count and
  score in the owning R6 instance. Raw tool arguments/results, matched
  values, span text, rows and hashes are never stored. Use
  `$audit(limit=)`, `$clear_audit()`, and `$coverage()$audit_events`;
  `audit_max` bounds memory with oldest-first eviction.

- **Universal Data Shield ingress scanning**: new
  [`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md)
  scans the arguments of every native/btw/MCP/host tool inside the
  single central permission gate before execution. High-confidence
  R/Python/Bash serialization, encoded output, network exfiltration,
  shell data-file display, registered-data preview calls, and custom
  PCRE rules may `block` or force the existing `ask_fn` approval UI.
  Read-only/unknown tools no longer bypass a Shield-forced ask; without
  a Shield, permission behaviour is unchanged.

- **Composable egress scanners**: `DataShield` now executes an ordered
  scanner pipeline (list order = execution order) and supports runtime
  `$add_scanner(name, fn)`. New
  [`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md)
  redacts or blocks unregistered email, phone-like values, common
  API-token prefixes, 18-character identity numbers, and custom named
  PCRE patterns. Scanner contracts are validated and fail closed; no
  custom S7 or Python dependency is introduced.

- **Data Shield recursively covers foreground sub-agents**: synchronous
  and concurrent `Agent` sub-chats inherit the parent `DataShield`
  before their first model request, and uninstrumented btw/custom-agent
  delegation is skipped. `BackgroundAgent` and `/bg` fail closed while a
  shield is active because a separate mirai process cannot safely
  inherit the session’s R6/index yet.

- **Multi-user Shiny isolation**:
  `codeagent_app(client_factory = function(session) ...)` now creates a
  fresh `CodeagentClient`/Chat inside every Shiny session; the no-client
  default uses this safe path automatically. Passing a pre-built
  `client` remains the explicitly single-user compatibility path. Data
  Shield protected values live in a session/thread-owned `DataShield` R6
  that may be shared deliberately without any package-global index.

- **Data Shield P0/P0.5/P1 (opt-in, default OFF)** is now a single
  stateful `DataShield` R6 engine. The easy
  `data_shield=list(shield_*())` form creates a private R6; pass an
  explicit `DataShield$new()` to register uploads or share a policy
  across selected chats. `shield$install(chat)` wraps tool results;
  `shield$register_data()` builds high-entropy value indexes;
  `shield$describe()` powers the automatically installed strict
  `DescribeData` tool. Bulk rows and targeted protected values are
  withheld; metadata exposes no distributions, counts, raw rows, or
  free-text examples. Scanner specs remain plain R functions/lists (no
  custom S7).

- **Backend permission gate for host tools**: new exported
  `install_permission_gate(chat, permission_mode, rules, tools, ask_fn, tool_meta)`
  lets a harness-only client (`register_tools = FALSE`) put the central
  permission gate over host-attached tools (the gate is otherwise only
  installed by
  [`.register_all_tools()`](https://kaipingyang.github.io/codeagent/reference/dot-register_all_tools.md)).
  The gate now also passes the tool-call `id` to `ask_fn`s that accept
  it (`ask_fn(name, input, id = NULL)`), so hosts can match an approval
  prompt to the `on_tool_request` preview; legacy `(name, input)`
  `ask_fn`s are unchanged.

- **Backend embedding (Contract v1)**: documented, stable surface for
  hosting codeagent as a backend engine. New exported
  `register_tool_meta(name, capability)` lets host apps declare a custom
  tool’s capability (`read`/`write`/`exec`/`net`) so the central
  permission gate governs it (an undeclared tool previously defaulted to
  `read` and was allowed ungated). New exported
  `tool_result(value, kind, payload)` builds a typed display card
  (`text`/`table`/`image`/`code`/`diff`/`error`) that reaches the
  `on_tool_result$display` callback and the Shiny app. Adds the
  `backend-integration` vignette + a reference example
  (`inst/examples/backend_integration_demo.R`) + a contract guard test.

- **Concurrent sub-agents (opt-in via `settings$async_subagents`,
  default OFF)**: the `Agent` tool can run asynchronously so multiple
  sub-agent delegations requested in a single turn execute concurrently
  (via ellmer’s `tool_mode = "concurrent"`) on the async streaming paths
  (CLI REPL / Shiny app). Sync one-shot
  [`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
  transparently falls back to sequential sub-agents, since async
  (promise-returning) tools are invalid under `Chat$chat()`. Also adopts
  ellmer 0.4.2 (`set_model()`, `chat_posit()`).

- **Background sub-agents (opt-in via `settings$background_agents`,
  default OFF; requires `mirai`)**: a new `BackgroundAgent` tool
  delegates a task to a fire-and-forget sub-agent running in a `mirai`
  daemon and returns immediately (non-blocking). Its result is polled
  and surfaced back to the model on a later turn via the system
  reminder, mirroring Claude Code’s async agents. Users can also spawn
  and inspect background agents directly with the `/bg <task>` and
  `/bgstatus` slash commands (REPL and Shiny).

## codeagent 0.1.0

First public release. `codeagent` is an R-native reimplementation of a
command-line coding agent, built on `ellmer` and `btw`. It provides the
agent harness (loop, tools, permissions, compaction, hooks, skills) plus
a CLI REPL and a `shiny` user interface.

### Model tier env var rename — breaking changes

Three environment variables have been renamed to remove vendor-specific
names. Update your `.Renviron` / `settings.json` env block accordingly:

| Old | New | Meaning |
|----|----|----|
| `CODEAGENT_DEFAULT_SONNET_MODEL` | `CODEAGENT_MODEL` | Everyday main model |
| `CODEAGENT_DEFAULT_OPUS_MODEL` | `CODEAGENT_HEAVY_MODEL` | High-capability model |
| `CODEAGENT_SMALL_FAST_MODEL` | `CODEAGENT_FAST_MODEL` | Cheap/fast model |

Tier aliases used in `/model` and `codeagent.md` also changed:
`"sonnet"` → `"main"`, `"opus"` → `"heavy"`, `"haiku"` → `"fast"`.

`CODEAGENT_MODEL` now serves dual purpose: it sets both the default
model and the `"main"` tier alias (previously `CODEAGENT_MODEL` and
`CODEAGENT_DEFAULT_SONNET_MODEL` were separate; they are now merged).

### CLI/ink unified entry point — breaking changes (plan [\#20](https://github.com/kaipingyang/codeagent/issues/20))

- **Default permission mode is now `"default"`** across all entry points
  (CLI, Shiny, ink). Previously all CLI subcommands defaulted to
  `"bypass"`. Write operations (file edits, shell commands) now prompt
  for approval unless you explicitly opt into bypass mode.

- **`-y` / `--yolo`** — new global flag for the CLI that enables bypass
  mode (skips all permission prompts). Equivalent to Claude Code’s
  `--dangerously-skip-permissions`. Short-hand: `-y`.

      codeagent -y           # bypass REPL
      codeagent app -y       # bypass Shiny app
      codeagent run "q" -y   # bypass one-shot query

- **`codeagent` without a subcommand** now starts the interactive REPL
  directly (equivalent to `codeagent chat`). Previously a subcommand was
  required.

- **`-p` / `--print-mode`** — new flag for one-shot non-interactive
  output. `codeagent "query"` or `codeagent -p "query"` runs a single
  query and exits.

- **`-m` now means `--model`** (breaking). The old `-m`/`--mode` alias
  has been removed. Use `-y`/`--yolo` for bypass mode instead.

- **`ink_ui()` gains `yolo = FALSE`** parameter. When `TRUE`, sets
  `INK_YOLO=1` so the codeagent backend runs in bypass mode. The `inkai`
  terminal command also accepts `-y`/`--yolo`.

      ink_ui("codeagent", yolo = TRUE)   # bypass
      # or from terminal:
      inkai codeagent -y                 # bypass

- **`INK_YOLO` env var** — set to `"1"` to enable bypass mode in ink
  when launching the `inkai` command directly:
  `INK_YOLO=1 inkai codeagent`.

- **`codeagent_app(permission_mode = "default")` unchanged** — Shiny was
  already correct; pass `permission_mode = "bypass"` explicitly when
  needed.

- **`R/cli_dispatch.R`** — new internal helpers
  [`.ca_resolve_mode()`](https://kaipingyang.github.io/codeagent/reference/dot-ca_resolve_mode.md)
  and
  [`.ca_dispatch()`](https://kaipingyang.github.io/codeagent/reference/dot-ca_dispatch.md)
  expose CLI dispatch logic as testable pure functions.

#### Migration guide

| Old | New |
|----|----|
| `codeagent chat` | `codeagent` |
| `codeagent chat -m bypass` | `codeagent -y` |
| `codeagent -m bypass` | `codeagent -y` |
| `ink_ui("codeagent")` (was bypass) | `ink_ui("codeagent", yolo = TRUE)` for bypass |
| `inkai codeagent` (was bypass) | `inkai codeagent -y` for bypass |

### Unified agent streaming API (plan [\#19](https://github.com/kaipingyang/codeagent/issues/19))

- **[`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md)**
  — new exported function. Streams one agent turn asynchronously
  ([`coro::async`](https://coro.r-lib.org/reference/async.html)
  promise). Runs the full turn pipeline (compaction, system-reminder
  injection, session save, cost tracking via
  `get_cost(include="last")`). Fires typed callbacks: `on_delta`,
  `on_thinking`, `on_tool_request` (pre-gate, from stream chunk),
  `on_tool_result` (with typed `display` contract from
  [`.adapt_tool_result()`](https://kaipingyang.github.io/codeagent/reference/dot-adapt_tool_result.md)),
  `on_error`, `on_usage`. Supports `stream_controller` for cancellation
  and `tool_mode` for concurrent tool execution.

- **[`codeagent_stream()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream.md)**
  — synchronous wrapper around
  [`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md)
  using
  [`later::run_now()`](https://later.r-lib.org/reference/run_now.html)
  to pump the event loop. Handles Ctrl+C gracefully (cancels the stream
  via `stream_controller`, does not re-throw the interrupt condition).
  Intended for CLI and ink frontends.

- **Turn pipeline helpers** (`R/turn_pipeline.R`, internal):
  [`.turn_setup()`](https://kaipingyang.github.io/codeagent/reference/dot-turn_setup.md)
  consolidates compaction + resource replacement + system-reminder
  injection into one call.
  [`.turn_teardown()`](https://kaipingyang.github.io/codeagent/reference/dot-turn_teardown.md)
  consolidates session save + usage + `cost_last`. Both are now shared
  by console, Shiny, and ink.

- **Shiny system-reminder injection fixed.** `server_chat.R`’s
  `stream_task` now injects the `<system-reminder>` block
  (date/iteration/cwd/memory) on every turn, matching the behaviour of
  the console REPL and
  [`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md).

- **Console Ctrl+C repair.**
  [`codeagent_console()`](https://kaipingyang.github.io/codeagent/reference/codeagent_console.md)
  now creates a `stream_controller` per turn and catches `interrupt`
  conditions, cancelling the stream gracefully. Previously Ctrl+C could
  corrupt the chat state.

- **Callback deduplication.** `.register_repl_tool_callbacks()` is now
  guarded by `.chat_once()` to prevent stacking display callbacks if
  [`codeagent_console()`](https://kaipingyang.github.io/codeagent/reference/codeagent_console.md)
  is called more than once on the same chat object.

- **`.patch_interrupted_chat()` retired.** Removed from all call sites.
  ellmer 0.4.0+
  ([\#840](https://github.com/kaipingyang/codeagent/issues/840)) and
  0.4.1+ ([\#643](https://github.com/kaipingyang/codeagent/issues/643))
  handle orphaned tool requests and `AssistantPartialTurn`
  automatically.

- **`inkAssistantUI` tool cards upgraded.** `ink_reply_stream()` now
  calls
  [`codeagent_stream()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream.md)
  when available (full turn pipeline + display contract).
  `on_tool_result` receives a rich `display` field (title/kind/payload)
  instead of a plain string. The `ink_server()` initialises per-session
  `CompactionController` / `ContentReplacementState` / `session_id` so
  turns are properly managed.

### Multi-agent teams (post-0.1.0 additions)

- **Task DAG.**
  [`team_coordinate()`](https://kaipingyang.github.io/codeagent/reference/team_coordinate.md)
  gains `blocked_by` — task dependencies given by 1-based index. A task
  is only claimed once all its blockers are `done`, so workers respect
  ordering while still parallelising independent tasks. Cyclic graphs
  are rejected up front. The shared board’s claim is now
  dependency-aware and atomic (`BEGIN IMMEDIATE`).
- **Worktree isolation + crash recovery.** `worktree = TRUE` runs each
  worker in its own git worktree;
  [`board_reclaim_stale()`](https://kaipingyang.github.io/codeagent/reference/board_reclaim_stale.md)
  (wired into the worker loop) resets a crashed worker’s timed-out task
  back to pending so its dependents are never blocked forever.
- **Event-driven board.**
  [`board_watch()`](https://kaipingyang.github.io/codeagent/reference/board_watch.md)
  (built on the `watcher` package) reacts to board changes without
  polling, powering an event-driven coordinator / live board view (falls
  back to polling when watcher is unavailable).
- **LLM-lead coordinator.** `team_lead(goal, max_rounds =)` faithfully
  ports Claude Code’s COORDINATOR_MODE: a lead model decomposes the goal
  into a task DAG, the work-stealing team runs it, then the lead reviews
  results and either finishes or adds a follow-up round (bounded loop;
  decompose/review/coordinate steps are injectable for testing).
- **Live dashboard.** `team_dashboard(db_path)` is a standalone Shiny
  app that monitors a running team’s board in real time — task table
  (coloured by status), a progress bar, and the inter-agent message log.

### Shiny app UX (post-0.1.0 additions)

- **Instant startup.** The UI shell now renders immediately; the slower
  tool + skill registration runs in the background behind a prominent
  “Initializing codeagent…” overlay, with the chat input gated until it
  completes. Pass a bare
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html) to
  [`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
  for this lazy path.

- **Skill metadata disk cache.**
  [`list_skills_meta()`](https://kaipingyang.github.io/codeagent/reference/list_skills_meta.md)
  now caches parsed skill metadata on disk (`<config>/cache/skills/`,
  keyed by cwd + a `SKILL.md` mtime/count signature), so the slash
  typeahead and skill tool are near-instant on every launch after the
  first (a disk hit skips the ~20s directory scan). The cache
  self-invalidates when any `SKILL.md` changes or a skill is
  added/removed.

- **Single-file viewer.** Clicking a file in the Files tree now opens it
  in one static, scrollable “File” tab (code / Markdown / image / CSV)
  with a filename header and close button, replacing the old per-file
  tabs that could overflow and cover the tab strip.

### Security & testing improvements (post-0.1.0 additions)

- **keyring integration** (`R/keyring.R`): Optional API key storage via
  the OS credential store (`keyring` package). `setup.R` offers the
  keyring as an alternative to `~/.Renviron` when the backend is
  available. Includes
  [`.keyring_available()`](https://kaipingyang.github.io/codeagent/reference/dot-keyring_available.md)
  (session-cached probe),
  [`.keyring_store_key()`](https://kaipingyang.github.io/codeagent/reference/dot-keyring_store_key.md)
  with graceful fallback to `~/.Renviron`, and
  [`.keyring_get_key()`](https://kaipingyang.github.io/codeagent/reference/dot-keyring_get_key.md).
  On headless/server environments the keyring backend probe returns
  `FALSE` and all functions degrade silently to the existing
  `~/.Renviron` path.

- **webfakes agent integration tests**
  (`tests/testthat/test-webfakes-agent.R`): 12 tests that mock the LLM
  API endpoint with `webfakes`, exercising the full agent loop — tool
  dispatch (Read, Write, Bash), permission gate (bypass vs plan), error
  recovery (HTTP 500), and skill invocation — without hitting a real
  LLM.

- **Explicit tool names**:
  [`bash_tool()`](https://kaipingyang.github.io/codeagent/reference/bash_tool.md),
  [`read_tool()`](https://kaipingyang.github.io/codeagent/reference/read_tool.md),
  [`write_tool()`](https://kaipingyang.github.io/codeagent/reference/write_tool.md),
  [`edit_tool()`](https://kaipingyang.github.io/codeagent/reference/edit_tool.md),
  [`multi_edit_tool()`](https://kaipingyang.github.io/codeagent/reference/multi_edit_tool.md),
  [`glob_tool()`](https://kaipingyang.github.io/codeagent/reference/glob_tool.md),
  [`grep_tool()`](https://kaipingyang.github.io/codeagent/reference/grep_tool.md),
  [`ls_tool()`](https://kaipingyang.github.io/codeagent/reference/ls_tool.md)
  now pass `name=` to
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  so the model can refer to tools by their canonical names (Bash, Read,
  Write, Edit, MultiEdit, Glob, Grep, LS).

### Agent harness

- Agentic loop
  ([`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md))
  with max-turns, token budget, verification, and error recovery
  (prompt-too-long, rate-limit, network, and auth handling).
- Seven-mode permission system: `default`, `plan`, `accept_edits`,
  `bypass`, `dont_ask`, `auto`, and `bubble` (sub-agent decisions bubble
  to the parent). Fine-grained rules match on tool arguments
  (e.g. `Bash(npm run test *)`).
- Twelve-event hook system covering tool, permission, message, and
  lifecycle events, configurable declaratively from `settings.json`.
- Five-level context compaction (snip, session memory, full summary,
  prompt fallback, context collapse).
- System prompt with tone, task, convention, tool-use, and R-specific
  guidance.

### Tools

- Core tools: `Bash`, `Read`, `Write`, `Edit`, `MultiEdit`, `Glob`,
  `Grep`, `LS`.
- `RunR` executes R code behind the permission gate; with sandboxing
  enabled it runs in an isolated `callr` subprocess with a scrubbed
  environment (secrets hidden), no `.Renviron` reload, and a wall-clock
  timeout.
- `btw` tool groups (docs, git, pkg, env, etc.), web fetch and search,
  notebook tools, task and persistent-todo tools.
- Optional codebase retrieval via `ragnar` (vector + keyword search).

### Coordination

- Sub-agents via
  [`agent_tool()`](https://kaipingyang.github.io/codeagent/reference/agent_tool.md),
  with optional git-worktree isolation and persistent “sidechain”
  sessions.
- Parallel teams:
  [`team_run()`](https://kaipingyang.github.io/codeagent/reference/team_run.md)
  (fixed fan-out) and
  [`team_coordinate()`](https://kaipingyang.github.io/codeagent/reference/team_coordinate.md)
  (work-stealing over a shared SQLite board with inter-agent messaging),
  both capped to the container’s CPU quota via `parallelly`.
- Plan-mode tools let the model enter and exit read-only planning
  mid-turn.

### State and configuration

- Sessions saved as JSONL with lossless tool-call preservation; fork,
  rename, tag, resume, and rewind
  ([`truncate_chat_turns()`](https://kaipingyang.github.io/codeagent/reference/truncate_chat_turns.md)
  / `/rewind`).
- Auto-memory persisted across sessions, with relevance selection by a
  small fast model.
- `settings.json` configuration mirroring command-line agents: `env`
  block, model tiers, permissions, hooks, MCP servers, sandbox, effort
  level, and more.
- Model switching mid-conversation
  ([`switch_model()`](https://kaipingyang.github.io/codeagent/reference/switch_model.md)),
  lossless where possible.

### Interfaces

- CLI: `codeagent` executable with `run`, `chat`/`repl`, `app`,
  `skills`, `mcp`, and `info` sub-commands; the REPL streams output,
  shows tool activity, and renders reasoning blocks.
- `shiny` app
  ([`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md))
  with tool cards, session management, and theme options.
- MCP server
  ([`codeagent_mcp_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mcp_server.md),
  stdio and HTTP) and MCP client
  ([`register_mcp_client()`](https://kaipingyang.github.io/codeagent/reference/register_mcp_client.md),
  stdio) for external tool interoperability.
