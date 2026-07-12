# Streaming Tool Executor

Concurrent tool execution scheduler for codeagent. Concurrent-safe tools
run in parallel via promises/futures; non-concurrent-safe tools run
serially (one at a time).
