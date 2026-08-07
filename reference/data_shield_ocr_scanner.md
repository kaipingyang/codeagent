# Build an OCR-backed image scanner for the Data Shield input gate.

Returns a `function(content_image) -> list(action, ...)` suitable for
the `image_scanner` slot of
[`.input_gate_scan()`](https://kaipingyang.github.io/codeagent/reference/dot-input_gate_scan.md)
(or `settings$data_shield_image_scanner`). It OCRs the image with the
optional tesseract package, then runs the extracted text through the
shield's `scan_prompt()`. Images are otherwise a blind spot at edge 1
(the model sees pixels, not the redactable text inside them); this
closes the gap for text baked into screenshots.

## Usage

``` r
data_shield_ocr_scanner(shield, on_fail = c("block", "pass"), engine = NULL)
```

## Arguments

- shield:

  A `DataShield` engine (its `scan_prompt()` backs the scan).

- on_fail:

  How an OCR hit is handled: `"block"` (default — immutable image cannot
  be redacted in place, so the whole turn is blocked) or `"pass"`
  (audit-only; log but let it through).

- engine:

  Optional pre-built
  [`tesseract::tesseract()`](https://docs.ropensci.org/tesseract/reference/tesseract.html)
  engine (language, whitelist, etc.). `NULL` uses tesseract's default
  English engine.

## Value

A scanner function returning `list(action = "block"/"pass", text=)`.

## Details

This is **opt-in** (scheme A): the default `data_shield_image_scanner`
stays `NULL`, so the host must wire this in explicitly. Reasons: OCR is
a real per-image cost, it can false-positive, and tesseract is a
`Suggests` dependency (a C library + language data, not installed by
default). When tesseract is missing the scanner degrades to `pass`
(never blocks on a missing optional dep) — so the image is treated as an
accepted blind spot, matching the no-scanner default.
