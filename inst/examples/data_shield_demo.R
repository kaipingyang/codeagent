# =============================================================================
# Data Shield P0 --- self-test / demo
# =============================================================================
# Shows the shape-based egress row-cap: a tool that returns bulk row-level data
# has its RESULT truncated to a shape summary before it reaches the model. The
# tool still RUNS locally (data never leaves your R session); only what is fed
# back to the LLM is filtered. Off by default (`data_shield = NULL`).
#
# Part 1 needs no LLM (deterministic). Part 2 runs a real round-trip if
# CODEAGENT_BASE_URL / _MODEL / _API_KEY are set.
# =============================================================================

library(codeagent)
# NOTE: Data Shield R6 is a dev feature. If `DataShield` is not found, load the
# dev version first (`devtools::load_all(".")`) or reinstall + restart R.
stopifnot("DataShield" = exists("DataShield"))

# Helper: fetch a tool from a chat by name (get_tools() naming can vary).
get_tool <- function(chat, nm) {
  tl <- chat$get_tools()
  if (!is.null(tl[[nm]])) return(tl[[nm]])
  for (t in tl)
    if (identical(tryCatch(S7::prop(t, "name"), error = function(e) ""), nm)) return(t)
  NULL
}

# A tool that leaks: returns the full mtcars data.frame (32 rows).
dump <- ellmer::tool(function() mtcars, name = "DumpData",
                     description = "Return the full mtcars data.frame.",
                     arguments = list())

# --- Part 1: deterministic before/after (no LLM needed) ---------------------
chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL", "http://x"),
  model    = Sys.getenv("CODEAGENT_MODEL", "m"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY", "k"))
chat$register_tool(dump)

before <- get_tool(chat, "DumpData")()
cat("WITHOUT shield -> class:", class(before)[1],
    "| rows the model would see:", tryCatch(nrow(before), error = function(e) NA), "\n")

shield <- DataShield$new(max_rows = 0)
shield$install(chat)                              # <- turn the shield on
after <- get_tool(chat, "DumpData")()
cat("WITH shield    ->", substr(as.character(after), 1, 90), "\n")

# --- Part 2: real end-to-end (the model calls the tool) ---------------------
if (nzchar(Sys.getenv("CODEAGENT_BASE_URL"))) {
  chat2 <- ellmer::chat_openai_compatible(
    base_url = Sys.getenv("CODEAGENT_BASE_URL"),
    model    = Sys.getenv("CODEAGENT_MODEL"),
    credentials = function() Sys.getenv("CODEAGENT_API_KEY"), echo = "none")
  # Backend/harness pattern: harness-only client, attach your tool, install shield.
  client <- codeagent_client(
    chat2, register_tools = FALSE,
    data_shield = list(shield_egress(max_rows = 0)),
    permission_mode = "bypass")
  chat2$register_tool(dump)
  client$data_shield$install(chat2)

  codeagent_stream(
    client, "Call the DumpData tool, then report only how many rows it has.",
    on_delta        = function(t) cat(t),
    on_tool_result  = function(x)
      if (identical(x$name, "DumpData"))
        cat("\n[what the model actually received]:\n  ", substr(x$value, 1, 100), "\n"))
  cat("\n")
} else {
  message("Set CODEAGENT_BASE_URL / _MODEL / _API_KEY to run the live round-trip.")
}
