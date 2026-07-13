# Decide whether a command is blocked by the sandbox

Decide whether a command is blocked by the sandbox

## Usage

``` r
.sandbox_block_reason(command, profile)
```

## Arguments

- command:

  Character. The shell command.

- profile:

  List from
  [`.sandbox_profile()`](https://kaipingyang.github.io/codeagent/reference/dot-sandbox_profile.md).

## Value

NULL if allowed, or a character reason string if blocked.
