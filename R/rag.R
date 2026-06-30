#' @title Codebase RAG (semantic retrieval)
#' @description Optional retrieval-augmented context for the agent, built on the
#'   `ragnar` package (CRAN). Indexes project files into a vector store and
#'   exposes a retrieval tool so the model can semantically search the codebase
#'   (vector + BM25 hybrid), mirroring Claude Code's codebase context. This is
#'   entirely optional: if `ragnar` is not installed, the tool is simply not
#'   registered and the agent works as before.
#'
#'   Embedding backend is chosen from the environment: a Databricks gateway
#'   (`CODEAGENT_BASE_URL`) uses `embed_databricks()`, otherwise Ollama via
#'   `embed_ollama()`. Both are ragnar built-ins -- we do not reimplement
#'   embedding or vector search.
#' @name rag
#' @keywords internal
NULL

# Pick an embedding function for ragnar based on the environment.
# Returns a partially-applied embed function, or NULL if no backend is usable.
.rag_embed_fn <- function() {
  if (!requireNamespace("ragnar", quietly = TRUE)) return(NULL)
  base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  if (nzchar(base_url)) {
    # Databricks serving endpoint: use a hosted embedding model.
    model <- Sys.getenv("CODEAGENT_EMBED_MODEL", "databricks-bge-large-en")
    return(function(x) ragnar::embed_databricks(x, model = model))
  }
  # Fallback: local Ollama (must be running).
  function(x) ragnar::embed_ollama(
    x, model = Sys.getenv("CODEAGENT_EMBED_MODEL", "all-minilm"))
}

# Default file patterns to index for a codebase store.
.RAG_DEFAULT_GLOBS <- c("R/*.R", "*.R", "*.md", "*.Rmd", "*.qmd",
                        "tests/testthat/*.R", "inst/**/*.R")

#' Build (or rebuild) a codebase vector store
#'
#' Reads matching project files, chunks them, embeds, and writes a ragnar store
#' with a vector + BM25 index. Returns the connected store, or NULL if ragnar is
#' unavailable or no files matched.
#'
#' @param cwd Character. Project root.
#' @param location Character. Store path (default `.codeagent/rag.duckdb`).
#' @param globs Character vector of file globs to index.
#' @param overwrite Logical. Recreate the store if it exists.
#' @return A ragnar store object, or NULL.
#' @export
build_codebase_store <- function(cwd = getwd(),
                                 location = NULL,
                                 globs = .RAG_DEFAULT_GLOBS,
                                 overwrite = TRUE) {
  if (!requireNamespace("ragnar", quietly = TRUE)) {
    message("ragnar not installed; skipping codebase RAG store.")
    return(NULL)
  }
  embed <- .rag_embed_fn()
  if (is.null(embed)) return(NULL)

  location <- location %||% file.path(cwd, ".codeagent", "rag.duckdb")
  dir.create(dirname(location), showWarnings = FALSE, recursive = TRUE)

  files <- unique(unlist(lapply(globs, function(g)
    Sys.glob(file.path(cwd, g)))))
  files <- files[file.exists(files) & !dir.exists(files)]
  if (!length(files)) return(NULL)

  store <- tryCatch(
    ragnar::ragnar_store_create(location = location, embed = embed,
                                overwrite = overwrite),
    error = function(e) { message("RAG store create failed: ",
                                  conditionMessage(e)); NULL })
  if (is.null(store)) return(NULL)

  # Read -> chunk -> insert each file. Errors on a single file are skipped.
  for (f in files) {
    tryCatch({
      doc    <- ragnar::ragnar_read(f)
      chunks <- ragnar::ragnar_chunk(doc, max_size = 1600L)
      ragnar::ragnar_store_insert(store, chunks)
    }, error = function(e) NULL)
  }
  tryCatch(ragnar::ragnar_store_build_index(store),
           error = function(e) NULL)
  store
}

#' Register a codebase retrieval tool on a chat
#'
#' Builds (or reuses) a codebase store and attaches ragnar's retrieval tool so
#' the model can semantically search the project. No-op when ragnar is missing
#' or indexing yields nothing.
#'
#' @param chat An `ellmer::Chat` object.
#' @param cwd Character. Project root.
#' @param store Optional pre-built ragnar store (skips rebuilding).
#' @return Invisibly `chat`.
#' @keywords internal
register_rag_tool <- function(chat, cwd = getwd(), store = NULL) {
  if (!requireNamespace("ragnar", quietly = TRUE)) return(invisible(chat))
  st <- store %||% tryCatch(build_codebase_store(cwd), error = function(e) NULL)
  if (is.null(st)) return(invisible(chat))
  tryCatch(
    ragnar::ragnar_register_tool_retrieve(
      chat, st,
      store_description = paste0(
        "Semantic + keyword search over this project's source files. Use to ",
        "find where something is defined or how a subsystem works before ",
        "editing.")),
    error = function(e) NULL)
  invisible(chat)
}
