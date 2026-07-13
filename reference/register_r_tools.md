# Register btw R-environment tools to an ellmer Chat object

Wraps
[`btw::btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html)
and registers each returned tool to `chat`. If `btw` is not installed a
warning is emitted and nothing is registered.

## Usage

``` r
register_r_tools(chat, groups = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- groups:

  Character vector of group names to include, or `NULL` for all. Valid
  groups: `"agent"`, `"cran"`, `"docs"`, `"env"`, `"files"`, `"git"`,
  `"github"`, `"ide"`, `"pkg"`, `"sessioninfo"`, `"web"`. `"files"` is
  included in the default `NULL` (all groups).

## Value

Invisibly returns the number of tools registered.

## Details

The `files` group (`btw_tool_files_*`) is included by default and
provides hashline-validated precise editing – superior to codeagent's
own file tools for read/write/edit operations. codeagent's built-in
tools remain for permission-gated Bash and legacy compatibility.

The `skill` group is intentionally excluded here; it is registered via
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
using
[`.make_skill_tool()`](https://kaipingyang.github.io/codeagent/reference/dot-make_skill_tool.md)
which merges btw skills with codeagent's own skill discovery.
