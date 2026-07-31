# =============================================================================
# codeagent as a backend --- minimal reference integration
# =============================================================================
# Self-contained demo of embedding codeagent as a backend engine in a host app.
# Everything here is generic: FAKE data, a TOY tool, an env-var-driven provider.
# No business logic, no secrets. Copy the shape into your own app.
#
# What it shows:
#   1. Build any ellmer Chat (your own provider / model / key).
#   2. codeagent_client(chat, register_tools = FALSE)  -> harness only,
#      NONE of codeagent's coding tools (Bash/Write/Edit/git/...) attached.
#   3. Define + register YOUR OWN tool; return a rich result via tool_result().
#   4. Declare its capability with register_tool_meta() so the permission gate
#      governs it.
#   5. Drive a turn with codeagent_stream() and render via the typed callbacks.
#
# Run:  CODEAGENT_BASE_URL / _MODEL / _API_KEY set, then `Rscript this_file.R`.
# =============================================================================

library(codeagent)

# --- 0. Fake data the toy tool will operate on (stands in for host data) -----
fake_sales <- data.frame(
  region = c("N", "S", "E", "W", "N", "S"),
  units  = c(10L, 22L, 7L, 15L, 12L, 30L),
  revenue = c(100, 240, 63, 150, 130, 300)
)

# --- 1. Your own ellmer Chat (provider-agnostic; host owns creds) ------------
chat <- ellmer::chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
  echo        = "none"
)

# --- 2. Harness-only client: no coding tools attached ------------------------
client <- codeagent_client(
  chat            = chat,
  register_tools  = FALSE,     # <- the key: only harness/skill/compaction/gate
  permission_mode = "default",
  cwd             = getwd()
)

# --- 3. A TOY host tool: summarise a data.frame, return a rich `table` card ---
summarise_frame <- ellmer::tool(
  function(group_by = "region") {
    df <- aggregate(cbind(units, revenue) ~ get(group_by), data = fake_sales, FUN = sum)
    names(df)[1] <- group_by
    # tool_result() -> the model sees `value`; the host UI gets a typed table
    # via on_tool_result$display (kind = "table", payload$df = df).
    tool_result(
      sprintf("Summary by %s (%d rows).", group_by, nrow(df)),
      kind    = "table",
      payload = list(df = df),
      title   = paste("Sales by", group_by)
    )
  },
  name        = "SummariseSales",
  description = "Summarise fake sales by a grouping column (region).",
  arguments   = list(
    group_by = ellmer::type_string("Column to group by.", required = FALSE)
  )
)
chat$register_tool(summarise_frame)

# --- 4. Declare its capability so the central gate governs it ----------------
# Read-only here -> allowed without prompting. Use "exec"/"write"/"net" for
# tools that run code, modify files, or hit the network.
register_tool_meta("SummariseSales", "read")

# --- (optional) 5. Point codeagent at YOUR skill directory -------------------
# codeagent scans `<cwd>/<subdir>` for `<name>/SKILL.md`. Drop your skills there
# and load their prompts yourself, or let the harness surface them.
#   skills <- list_skills_meta(cwd = getwd())
#   prompt <- load_skill_prompt("my_skill", cwd = getwd())

# --- 6. Drive one turn; render via the typed streaming callbacks -------------
if (nzchar(Sys.getenv("CODEAGENT_BASE_URL"))) {
  codeagent_stream(
    client,
    "Summarise the sales by region using the SummariseSales tool, then comment.",
    on_delta        = function(txt) cat(txt),
    on_tool_request = function(tr) cat(sprintf("\n[tool > %s(%s)]\n", tr$name,
                                               paste(names(tr$arguments), collapse = ","))),
    on_tool_result  = function(tr) {
      k <- tryCatch(tr$display$toolcard$kind, error = function(e) NULL)
      if (is.null(k)) k <- "text"
      cat(sprintf("\n[tool < %s : kind=%s]\n", tr$name, k))
      # A non-Shiny host renders the structured artifact itself:
      if (identical(k, "table")) print(tr$display$toolcard$payload$df)
    }
  )
  cat("\n")
} else {
  message("Set CODEAGENT_BASE_URL / _MODEL / _API_KEY to run the live turn.")
}
