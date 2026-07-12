# Codebase RAG (semantic retrieval)

Optional retrieval-augmented context for the agent, built on the
`ragnar` package (CRAN). Indexes project files into a vector store and
exposes a retrieval tool so the model can semantically search the
codebase (vector + BM25 hybrid), mirroring Claude Code's codebase
context. This is entirely optional: if `ragnar` is not installed, the
tool is simply not registered and the agent works as before.

Embedding backend is chosen from the environment: a Databricks gateway
(`CODEAGENT_BASE_URL`) uses `embed_databricks()`, otherwise Ollama via
`embed_ollama()`. Both are ragnar built-ins – we do not reimplement
embedding or vector search.
