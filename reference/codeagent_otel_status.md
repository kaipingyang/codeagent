# Report OpenTelemetry observability status for codeagent

codeagent inherits ellmer's chat + tool spans and adds a top-level
`codeagent.query` span. Tracing only emits when the OTel SDK is
installed and a tracer/exporter is configured. This helper reports
whether that is the case and how to enable it.

## Usage

``` r
codeagent_otel_status()
```

## Value

An object of class `codeagent_otel_status` (a list with `otel`,
`otelsdk`, `tracing_active`, and a human-readable `message`). Printed as
a short guidance message.

## Examples

``` r
if (FALSE) { # \dontrun{
codeagent_otel_status()
} # }
```
