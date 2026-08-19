#' Explicitly update ellmer model pricing data
#'
#' Downloads ellmer's current public pricing snapshot on demand. codeagent never
#' calls this function during startup or a model request. A network failure is
#' returned as a fixed, non-sensitive status instead of interrupting the app.
#' Custom/private provider endpoints may remain unpriced after an update.
#'
#' @return Invisibly, a list with logical `ok`, logical `updated`, and a
#'   human-readable `message`.
#'
#' @examples
#' \dontrun{
#' status <- update_model_prices()
#' status$message
#' }
#' @export
update_model_prices <- function() {
  result <- tryCatch(.ellmer_price_updater(), error = function(e) NULL)
  if (is.null(result)) {
    return(invisible(list(
      ok = FALSE, updated = FALSE,
      message = "Model pricing data could not be updated; the existing cache remains active.")))
  }
  updated <- isTRUE(result)
  invisible(list(
    ok = TRUE,
    updated = updated,
    message = if (updated) "Model pricing data updated." else
      "Model pricing data is already up to date."))
}

.ellmer_price_updater <- function() {
  if (!"models_update_prices" %in% getNamespaceExports("ellmer"))
    stop("Installed ellmer does not provide models_update_prices().", call. = FALSE)
  ellmer::models_update_prices()
}
