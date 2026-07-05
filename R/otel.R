# ---------------------------------------------------------------------------
# OpenTelemetry observability (task 12C)
#
# ellmer (>= 0.4.1) auto-instruments chat + tool calls with OTel spans when a
# tracer is active (internal chat_perform / invoke_tool span helpers). codeagent
# therefore *inherits* chat + tool spans for free. Here we add one thin thing on
# top: a top-level `codeagent.query` span so ellmer's chat/tool spans nest under
# a codeagent-owned parent (mirrors Claude Code's invoke_agent -> chat -> tool
# hierarchy), plus a status/enable helper. Everything is a no-op unless the user
# has installed the SDK (otel + otelsdk) and configured a tracer, so there is no
# hard dependency and no cost on the common path.
# ---------------------------------------------------------------------------

# TRUE only when the otel API is installed AND a tracer is actually active.
.otel_tracing_active <- function() {
  requireNamespace("otel", quietly = TRUE) &&
    isTRUE(tryCatch(otel::is_tracing_enabled(), error = function(e) FALSE))
}

# Run `thunk()` inside a codeagent span when tracing is active; otherwise run it
# directly (fast no-op path). The span ends when this function returns, so any
# ellmer chat/tool spans created during thunk() nest underneath it.
.with_codeagent_span <- function(name, attributes = list(), thunk) {
  if (!.otel_tracing_active()) return(thunk())
  otel::start_local_active_span(name, attributes = attributes)
  thunk()
}

#' Report OpenTelemetry observability status for codeagent
#'
#' codeagent inherits ellmer's chat + tool spans and adds a top-level
#' `codeagent.query` span. Tracing only emits when the OTel SDK is installed and
#' a tracer/exporter is configured. This helper reports whether that is the case
#' and how to enable it.
#'
#' @return An object of class `codeagent_otel_status` (a list with `otel`,
#'   `otelsdk`, `tracing_active`, and a human-readable `message`). Printed as a
#'   short guidance message.
#' @examples
#' \dontrun{
#' codeagent_otel_status()
#' }
#' @export
codeagent_otel_status <- function() {
  has_api <- requireNamespace("otel",    quietly = TRUE)
  has_sdk <- requireNamespace("otelsdk", quietly = TRUE)
  active  <- .otel_tracing_active()

  msg <- if (active) {
    paste0("OpenTelemetry tracing is ACTIVE. codeagent emits a 'codeagent.query' ",
           "span; ellmer nests chat + tool spans under it.")
  } else if (has_api && has_sdk) {
    paste0("otel + otelsdk are installed but no tracer is active. Configure an ",
           "exporter before starting R, e.g. Sys.setenv(OTEL_TRACES_EXPORTER = ",
           "\"stdout\"), or set an OTLP endpoint (OTEL_EXPORTER_OTLP_ENDPOINT). ",
           "See the otelsdk docs.")
  } else {
    paste0("Install the SDK to enable tracing: install.packages(c(\"otel\", ",
           "\"otelsdk\")). otelsdk needs system Protobuf. Then set ",
           "OTEL_TRACES_EXPORTER / an OTLP endpoint before launching codeagent.")
  }

  structure(
    list(otel = has_api, otelsdk = has_sdk, tracing_active = active, message = msg),
    class = "codeagent_otel_status")
}

#' @export
print.codeagent_otel_status <- function(x, ...) {
  cat(x$message, "\n")
  invisible(x)
}
