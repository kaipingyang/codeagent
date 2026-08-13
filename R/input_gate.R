#' @title Input Gate --- the edge-1 counterpart of the tool gate
#' @description The tool gate (`R/tools_gate.R`) guards edge 2 (tool traffic) by
#'   wrapping ellmer's `on_tool_request` / tool functions. The **input gate**
#'   guards edge 1: everything the user sends *before it reaches the model* ---
#'   typed text AND attachments (text-bearing content, images). Unlike the tool
#'   gate it has no ellmer chat-level hook to attach to (user input is handled
#'   inside `agent_loop` / the Shiny stream, not inside the Chat object), so the
#'   input gate is a function those entry points call at the UserPromptSubmit
#'   point.
#'
#'   Two consumers run at this edge, in order (mirroring the tool gate's
#'   hooks-then-shield layering), kept as SEPARATE systems:
#'   1. **hooks** `run_user_prompt_submit()` -- aligns with Claude Code's
#'      `UserPromptSubmit`; may `block` or append context, NEVER redacts
#'      (handled in `agent_loop` directly).
#'   2. **Data Shield** `scan_prompt()` -- the shield's own confidentiality
#'      scan; MAY redact (protected values / PII the user pasted in). This file
#'      wires that second consumer.
#'
#'   Input types and how each is handled (see `.input_gate_scan`):
#'   * **text** (typed message)        -> `scan_prompt`; redact/block/ask.
#'   * **text-bearing attachment**     -> extract text, scan; cannot be redacted
#'                                        in place (Content is immutable) so a
#'                                        hit fails safe to **block**.
#'   * **image attachment**            -> optional `image_scanner` hook
#'                                        (default `NULL` = blind spot, passed
#'                                        through). Host may inject a scanner
#'                                        (OCR / VLM) returning a decision.
#' @name input_gate
#' @keywords internal
NULL

# Resolve the active shield the same way the tool gate does: settings engine
# first, then the chat attribute.
#' @keywords internal
.input_gate_shield <- function(settings = list(), chat = NULL) {
  shield <- settings$data_shield_engine %||%
    tryCatch(attr(chat, "codeagent_data_shield"), error = function(e) NULL)
  if (is.null(shield) || !inherits(shield, "DataShield")) return(NULL)
  shield
}

# Scan one text scalar via the shield. Returns list(action, text). "ask" without
# a wired approval path fails safe to redact-and-continue: we never send the
# un-scanned text to the model on an unresolved ask.
#
# FAIL-CLOSED (kiro round-2 #3): a scan exception must NOT return raw text with
# action="pass" (that silently disables edge 1 on any scanner bug / misconfig).
# On error we fail safe by on_fail: "block" -> block, anything else -> redact the
# WHOLE text (drop it) rather than forward unscanned content to the model. This
# mirrors the tool-side scan_ingress (catch -> block), which was already
# fail-closed; edge 1 now matches.
#' @keywords internal
.input_gate_scan_text <- function(shield, text, on_fail = "redact",
                                  on_progress = NULL,
                                  scanners = c("regex", "value_match")) {
  if (!is.character(text) || length(text) != 1L || !nzchar(text))
    return(list(action = "pass", text = text))
  fail_closed <- function(e) {
    if (identical(on_fail, "block"))
      return(list(action = "block",
                  text = "[data_shield] input blocked: scan failed (fail-closed)."))
    # redact-mode fallback: drop the unverifiable text entirely.
    list(action = "redact", text = "[data_shield] input redacted: scan failed (fail-closed).")
  }
  res <- tryCatch(
    shield$scan_prompt(text, on_fail = on_fail, on_progress = on_progress,
                       scanners = scanners),
    error = fail_closed)
  if (identical(res$action, "ask")) {
    redacted <- tryCatch(
      shield$scan_prompt(text, on_fail = "redact", on_progress = NULL,
                         scanners = scanners),
      error = fail_closed)
    return(list(action = "redact", text = redacted$text %||% text))
  }
  list(action = res$action %||% "pass", text = res$text %||% text)
}

# Best-effort text extraction from an ellmer Content object (ContentPDF, etc.).
#' @keywords internal
.input_gate_content_text <- function(el) {
  txt <- tryCatch(el@text, error = function(e) NULL)
  if (is.character(txt) && length(txt) == 1L && nzchar(txt)) return(txt)
  ""
}

#' Run the Data Shield input gate on a user turn's input.
#'
#' Call this in the agent loop / Shiny stream AFTER the UserPromptSubmit hook,
#' BEFORE the input is sent to the model. Handles both a bare character scalar
#' (CLI) and a contents list (Shiny: typed text + attachments).
#'
#' @param input Character scalar OR a list whose first element is the typed text
#'   and whose remaining elements are ellmer Content attachments.
#' @param settings The agent settings list (`data_shield_engine`,
#'   `data_shield_prompt_on_fail`, `data_shield_image_scanner`).
#' @param chat The ellmer Chat (fallback shield source via attribute).
#' @param on_progress Optional progress callback forwarded to `scan_prompt()`.
#' @param image_scanner Optional `function(content_image) -> list(action, ...)`
#'   for image attachments (default resolves from
#'   `settings$data_shield_image_scanner`; `NULL` = images not scanned).
#' @return A list: `action` (`"pass"`/`"redact"`/`"block"`), `input` (the
#'   possibly-redacted input, same shape as the argument), and `text` (a message
#'   when `action == "block"`). When no shield is active, returns
#'   `list(action = "pass", input = input)`.
#' @keywords internal
.input_gate_scan <- function(input, settings = list(), chat = NULL,
                             on_progress = NULL, image_scanner = NULL) {
  shield <- .input_gate_shield(settings, chat)
  if (is.null(shield)) return(list(action = "pass", input = input))
  on_fail       <- settings$data_shield_prompt_on_fail %||% "redact"
  image_scanner <- image_scanner %||% settings$data_shield_image_scanner
  scanners      <- settings$data_shield_input_scanners %||% c("value_match", "regex")
  # Reject an unknown scanner name up front (typo in settings would otherwise
  # silently skip scanning -- fail-closed, kiro round-2 #3).
  scanners      <- .data_shield_validate_scanners(scanners)

  # --- bare character scalar (CLI / ink) ---------------------------------
  if (is.character(input) && length(input) == 1L) {
    if (!nzchar(input)) return(list(action = "pass", input = input))
    r <- .input_gate_scan_text(shield, input, on_fail, on_progress, scanners)
    if (identical(r$action, "block"))
      return(list(action = "block", input = input, text = r$text))
    return(list(action = r$action, input = r$text %||% input))
  }

  # --- contents list (Shiny: text + Content attachments) -----------------
  if (is.list(input)) {
    out <- input
    agg <- "pass"
    for (i in seq_along(input)) {
      el <- input[[i]]
      is_image <- tryCatch(S7::S7_inherits(el, ellmer::ContentImage),
                           error = function(e) FALSE)
      if (is.character(el) && length(el) == 1L && nzchar(el)) {
        # Typed text element: full scan, may redact in place.
        r <- .input_gate_scan_text(shield, el, on_fail, on_progress, scanners)
        if (identical(r$action, "block"))
          return(list(action = "block", input = input, text = r$text))
        if (!identical(r$action, "pass")) { out[[i]] <- r$text; agg <- "redact" }
      } else if (isTRUE(is_image)) {
        # Image attachment: optional host scanner (OCR/VLM). Default NULL = skip
        # (an explicitly-accepted blind spot). But once a scanner IS configured,
        # its failure or an invalid return contract must FAIL CLOSED to block
        # (kiro round-3): a host that wired an OCR scanner expects the image
        # boundary enforced, so a stop()/malformed result cannot silently pass.
        if (is.function(image_scanner)) {
          ir  <- tryCatch(image_scanner(el),
                          error = function(e) list(action = "block",
                                                   text = "[data_shield] image blocked: scanner failed (fail-closed)."))
          if (!is.list(ir) || is.null(ir$action) ||
              !ir$action %in% c("pass", "redact", "block"))
            return(list(action = "block", input = input,
                        text = "[data_shield] image blocked: scanner returned an invalid result (fail-closed)."))
          act <- ir$action
          if (identical(act, "block"))
            return(list(action = "block", input = input,
                        text = ir$text %||% "[data_shield] image blocked."))
          if (!identical(act, "pass")) {
            # redact (or any non-pass): an image is IMMUTABLE content -- it cannot
            # be redacted in place. If the scanner supplied replacement content,
            # swap it; otherwise a "redact" with no content must ESCALATE TO BLOCK
            # (kiro round-4 #6), never leave the original image through.
            if (!is.null(ir$content)) {
              out[[i]] <- ir$content; agg <- "redact"
            } else {
              return(list(action = "block", input = input,
                          text = ir$text %||% "[data_shield] image blocked: scanner flagged it but supplied no replacement (fail-closed)."))
            }
          }
        }
      } else {
        # Other Content (ContentPDF, ...): scan extracted text. Immutable, so a
        # hit fails safe to block rather than sending unredacted content.
        # FAIL-CLOSED (kiro round-2 #3): if the text cannot be extracted at all
        # (empty @text -- e.g. an image-only / dynamically built ContentPDF), the
        # content is UNVERIFIABLE. Do not silently pass it through; block, since
        # it may carry protected content the scanner never saw. (Genuine image
        # attachments are handled by the image_scanner branch above; this branch
        # is for text-bearing Content whose text we failed to read.)
        txt <- .input_gate_content_text(el)
        if (nzchar(txt)) {
          r <- .input_gate_scan_text(shield, txt, "block", on_progress, scanners)
          if (identical(r$action, "block"))
            return(list(action = "block", input = input,
                        text = "[data_shield] attachment blocked: contains protected content."))
        } else {
          return(list(action = "block", input = input,
                      text = "[data_shield] attachment blocked: text could not be extracted (fail-closed; content unverifiable)."))
        }
      }
    }
    return(list(action = agg, input = out))
  }

  list(action = "pass", input = input)
}

# Extract a local file path for OCR from an ellmer ContentImage, decoding an
# inline base64 image to a temp file when needed. Returns "" when the image
# cannot be resolved to a path (e.g. a remote URL tesseract can still fetch is
# handled separately by the caller).
#' @keywords internal
.input_gate_image_source <- function(content_image) {
  # Inline (base64): decode to a temp file tesseract can read.
  data <- tryCatch(content_image@data, error = function(e) NULL)
  type <- tryCatch(content_image@type, error = function(e) NULL)
  if (is.character(data) && length(data) == 1L && nzchar(data)) {
    ext <- if (is.character(type) && grepl("/", type, fixed = TRUE))
      sub(".*/", "", type) else "png"
    tmp <- tempfile(fileext = paste0(".", ext))
    ok <- tryCatch({ writeBin(base64enc::base64decode(data), tmp); TRUE },
                   error = function(e) FALSE)
    if (isTRUE(ok)) return(list(path = tmp, cleanup = TRUE))
  }
  # Remote URL: tesseract::ocr() accepts a URL directly.
  url <- tryCatch(content_image@url, error = function(e) NULL)
  if (is.character(url) && length(url) == 1L && nzchar(url))
    return(list(path = url, cleanup = FALSE))
  list(path = "", cleanup = FALSE)
}

#' Build an OCR-backed image scanner for the Data Shield input gate.
#'
#' Returns a `function(content_image) -> list(action, ...)` suitable for the
#' `image_scanner` slot of [.input_gate_scan()] (or `settings$data_shield_image_scanner`).
#' It OCRs the image with the optional \pkg{tesseract} package, then runs the
#' extracted text through the shield's `scan_prompt()`. Images are otherwise a
#' blind spot at edge 1 (the model sees pixels, not the redactable text inside
#' them); this closes the gap for text baked into screenshots.
#'
#' This is **opt-in** (scheme A): the default `data_shield_image_scanner` stays
#' `NULL`, so the host must wire this in explicitly. Reasons: OCR is a real
#' per-image cost, it can false-positive, and \pkg{tesseract} is a `Suggests`
#' dependency (a C library + language data, not installed by default). When
#' \pkg{tesseract} is missing the scanner degrades to `pass` (never blocks on a
#' missing optional dep) --- so the image is treated as an accepted blind spot,
#' matching the no-scanner default.
#'
#' @param shield A `DataShield` engine (its `scan_prompt()` backs the scan).
#' @param on_fail How an OCR hit is handled: `"block"` (default --- immutable
#'   image cannot be redacted in place, so the whole turn is blocked) or
#'   `"pass"` (audit-only; log but let it through).
#' @param engine Optional pre-built `tesseract::tesseract()` engine (language,
#'   whitelist, etc.). `NULL` uses tesseract's default English engine.
#' @return A scanner function returning `list(action = "block"/"pass", text=)`.
#' @export
data_shield_ocr_scanner <- function(shield, on_fail = c("block", "pass"),
                                    engine = NULL) {
  force(shield)
  on_fail <- match.arg(on_fail)
  force(engine)
  function(content_image) {
    if (!requireNamespace("tesseract", quietly = TRUE))
      return(list(action = "pass"))          # optional dep absent -> blind spot
    if (is.null(shield) || !inherits(shield, "DataShield"))
      return(list(action = "pass"))
    src <- .input_gate_image_source(content_image)
    if (!nzchar(src$path))
      return(list(action = "block",                       # configured but cannot obtain image -> unverifiable
                  text = "[data_shield] image blocked: could not read image for OCR (fail-closed)."))
    on.exit(if (isTRUE(src$cleanup)) unlink(src$path), add = TRUE)
    # OCR execution failure (tesseract present but errored) fails CLOSED -- the
    # host wired OCR expecting the boundary enforced (kiro round-3). An empty
    # OCR result (image genuinely has no text) is a legitimate pass.
    ocr_failed <- FALSE
    txt <- tryCatch(tesseract::ocr(src$path, engine = engine),
                    error = function(e) { ocr_failed <<- TRUE; "" })
    if (isTRUE(ocr_failed))
      return(list(action = "block",
                  text = "[data_shield] image blocked: OCR failed (fail-closed)."))
    if (!is.character(txt) || length(txt) != 1L || !nzchar(trimws(txt)))
      return(list(action = "pass"))                        # no text in image -> genuine pass
    scan_failed <- FALSE
    r <- tryCatch(shield$scan_prompt(txt, on_fail = "block"),
                  error = function(e) { scan_failed <<- TRUE; list(action = "block") })
    if (isTRUE(scan_failed))
      return(list(action = "block",
                  text = "[data_shield] image blocked: OCR text scan failed (fail-closed)."))
    if (!identical(r$action, "pass") && identical(on_fail, "block"))
      return(list(action = "block",
                  text = "[data_shield] image blocked: OCR found protected content."))
    list(action = "pass")
  }
}

# Entry-point wrapper (kiro round-3): call the input gate and FAIL CLOSED on any
# exception. The gate helper is fail-closed internally, but callers previously
# wrapped it in `tryCatch(error -> action="pass", raw input)`, which re-opened
# every failure (a stop() from an unknown scanner name, or any detector bug,
# silently forwarded the raw prompt). Here an exception becomes a BLOCK -- but
# ONLY when a shield is active, so projects with no Data Shield are unaffected.
#' @keywords internal
.input_gate_guarded <- function(input, settings = list(), chat = NULL,
                                on_progress = NULL, image_scanner = NULL) {
  if (is.null(.input_gate_shield(settings, chat)))
    return(list(action = "pass", input = input))          # no shield -> no-op
  tryCatch(
    .input_gate_scan(input, settings, chat, on_progress, image_scanner),
    error = function(e)
      list(action = "block", input = input,
           text = "[data_shield] input blocked: gate failed (fail-closed)."))
}

