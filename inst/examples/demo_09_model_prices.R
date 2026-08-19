#!/usr/bin/env Rscript
# inst/examples/demo_09_model_prices.R
#
# Demo: explicitly refresh ellmer's public model-pricing snapshot.
# codeagent never performs this network request automatically during startup or
# a model request. Custom or private provider endpoints may remain unpriced.
#
# Run from the package root after installing codeagent:
#   Rscript inst/examples/demo_09_model_prices.R

library(codeagent)

status <- update_model_prices()
cat(status$message, "\n")

if (!status$ok) {
  cat("The existing ellmer pricing cache remains active.\n")
}
