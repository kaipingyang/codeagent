# Configure universal tool-call ingress scanning

Scan every tool's arguments in the central permission gate before
execution. Default rules target high-confidence data serialization,
encoded output, network exfiltration, shell display of data files, and
direct previews of registered protected dataset names. This is
defense-in-depth; egress remains the primary model-data boundary.

## Usage

``` r
shield_ingress(
  langs = c("r", "python", "bash"),
  patterns = NULL,
  include_defaults = TRUE,
  on_fail = c("block", "ask"),
  ignore_case = TRUE
)
```

## Arguments

- langs:

  Any of `"r"`, `"python"`, and `"bash"`; controls which
  language-specific default rules are included.

- patterns:

  Optional named regular expressions using PCRE (Perl-Compatible Regular
  Expression) syntax. A name matching a built-in rule (e.g.
  `py_pandas_export`) replaces that rule; a new name is added. Hosts
  wanting file-managed blacklists read their own file (e.g.
  [`yaml::read_yaml()`](https://yaml.r-lib.org/reference/read_yaml.html))
  into a named vector and pass it here.

- include_defaults:

  Include built-in serialization/encoding, network transfer, shell
  data-file display, and protected-name preview rules.

- on_fail:

  `"block"` rejects the tool call; `"ask"` forces the existing
  permission approval callback/UI (including the tool-call id).

- ignore_case:

  Apply case-insensitive matching.

## Value

A Data Shield ingress strategy specification.

## Examples

``` r
strict_calls <- shield_ingress(on_fail = "block")
supervised <- shield_ingress(langs = c("r", "python", "bash"), on_fail = "ask")
```
