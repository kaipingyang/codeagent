# Configure regex-based egress scanning

Detect and redact/block common unregistered PII and secrets in tool
output. Default rules cover email, phone-like numbers, common API-token
prefixes, and 18-character identity-number shapes. Custom named PCRE
patterns may be added without introducing another state engine.

## Usage

``` r
shield_regex(
  patterns = NULL,
  include_defaults = TRUE,
  replacement = "[REDACTED]",
  on_fail = c("redact", "block"),
  ignore_case = TRUE
)
```

## Arguments

- patterns:

  Optional named character vector of custom regular expressions using
  PCRE (Perl-Compatible Regular Expression) syntax. Example:
  `c(study_id = "STUDY-[0-9]+")`, where `study_id` names the rule and
  `[0-9]+` means one or more digits. With `include_defaults = TRUE`,
  custom rules are appended after the built-ins.

- include_defaults:

  Include built-in email, phone-like, common-token-prefix, and
  18-character identity-number rules.

- replacement:

  Marker inserted once per merged matching span when
  `on_fail = "redact"`.

- on_fail:

  `"redact"` replaces only matching spans and preserves the rest of the
  tool result; `"block"` replaces the entire model-facing result.

- ignore_case:

  Apply case-insensitive PCRE matching to all rules.

## Value

A Data Shield scanner strategy specification.

## Examples

``` r
pii <- shield_regex(on_fail = "redact")
study_ids <- shield_regex(
  patterns = c(study_id = "STUDY-[0-9]+"),
  include_defaults = FALSE,
  on_fail = "block"
)
```
