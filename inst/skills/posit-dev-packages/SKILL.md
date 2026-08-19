---
name: posit-dev-packages
description: 更新 ellmer/btw/shinychat 到最新开发版，并显示开发版相比 CRAN 的新功能。当用户提到"更新开发包"、"dev version"、"开发版包"、"更新 ellmer btw shinychat"、"posit dev packages"时触发。
metadata:
  argument-hint: "[package names, default: all three]"
---

# 更新 Posit 开发版包

## 安装最新开发版

```r
# 全部更新
pak::pak(c(
  "tidyverse/ellmer",
  "posit-dev/btw",
  "posit-dev/shinychat/pkg-r"  # monorepo，路径必须是 pkg-r
), ask = FALSE)

# 验证版本和 GitHub SHA
for (pkg in c("ellmer", "btw", "shinychat")) {
  desc <- packageDescription(pkg)
  subdir <- desc[["RemoteSubdir"]]
  if (is.null(subdir)) subdir <- ""
  cat(pkg, desc[["Version"]], desc[["RemoteSha"]], subdir, "\n")
}
```

**注意：** shinychat 是 monorepo，必须用 `posit-dev/shinychat/pkg-r`，不能用 `posit-dev/shinychat`。

## 当前安装基线

最后验证：2026-08-19。

| 包 | CRAN | 当前开发版 | GitHub SHA |
|---|---|---|---|
| ellmer | 0.4.2 | 0.4.2.9000 | `19be478ebf1a2e5d2db96a8aeaca71592c8d3f26` |
| btw | 1.4.0 | 1.4.0.9000 | `d11591b09d9127b05d673e8c96569d2bbae2ec44` |
| shinychat | 0.4.0 | 0.4.0.9000 | `aa35a0988319103c35637e6d467ebc02a3180e3c` |

Plan 37 另外冻结：Shiny `1.14.0.9000@d19095f4b3dd`、bslib
`0.12.0.9000@97aa1abc262b`、mcptools `1.0.1`、httr2 `1.3.0`。这些 SHA 是兼容验证基线，
不要写进 DESCRIPTION 形成瞬时 HEAD 强锁。开发版经常只更新 Git SHA、不改变 `Version`；检查更新时必须
比较 `RemoteSha`，不能只比较 `packageVersion()`。

模型价格从不自动联网刷新；需要时显式调用 `codeagent::update_model_prices()`。失败会保留现有 cache，
custom/private endpoint 即使刷新后也可能仍无价格。

## 各包开发版新功能

详见 skill 目录下的 references 文件：

- `references/ellmer-dev.md` — ellmer 开发版新功能
- `references/btw-dev.md` — btw 开发版新功能
- `references/shinychat-dev.md` — shinychat 开发版新功能

## codeagent 已使用的开发版功能

| 功能 | 包 | 用在哪 |
|------|-----|--------|
| `set_model()` / `get_model_object()` | ellmer | `R/model_switch.R` 严格 name-only Route A；其它变化重建/拒绝 |
| `Chat$token_count()` / usage | ellmer | `R/compaction.R` 默认零隐式网络，并包含 cached input |
| `models_update_prices()` | ellmer | `update_model_prices()` 显式调用；从不启动时自动执行 |
| `ContentCitation` / content stream | ellmer | 自定义 web 使用当前-turn marker bridge，不信任 raw model aside |
| `btw_tool_files_patch` | btw | `R/tools_btw_files_pathA.R` Path A |
| `btw_tools()` groups | btw | 唯一 Agent owner + Settings 原子组替换 |
| `tool_result_display()` | shinychat | 官方 display、label/value preview；artifact/sources 留在私有 metadata |
| `chat_greeting(persistent=TRUE)` | shinychat | New/Delete/Restore 后 greeting 不丢失、不重复 |
| `allow_attachments=` / `user_input_contents()` | shinychat | `R/ui_panels.R` / `R/server_chat.R` |
| `contents_shinychat()` | shinychat | presentation-only legacy replay migration |
