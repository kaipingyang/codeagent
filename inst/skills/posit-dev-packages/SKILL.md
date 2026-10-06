---
name: posit-dev-packages
description: 更新 codeagent 的八个核心 GitHub 包到最新开发版，并显示开发版相比 CRAN 的新功能。当用户提到"更新开发包"、"dev version"、"开发版包"、"更新 ellmer btw shinychat"、"posit dev packages"时触发。
metadata:
  argument-hint: "[package names, default: all eight core packages]"
---

# 更新 Posit 开发版包

## 安装当前已验收GitHub HEAD

先重新查询各仓库HEAD；确认后用完整SHA安装，且只更新`Depends`、`Imports`、
`LinkingTo`运行时依赖，不批量升级无关CRAN包。2026-10-06 manifest：

```r
refs <- c(
  "tidyverse/ellmer@248c86704a52baf2f4f66a91f12b42a48ddac993",
  "posit-dev/btw@6a27d997120f11cfda15bf0a5953a22329b01715",
  "posit-dev/shinychat/pkg-r@05e0bbd987286068638d3cf96d6ea7daff15c5b2",
  "rstudio/shiny@bbc43849f06059f5daa7310ea0f40ec901f0ed0f",
  "rstudio/bslib@ac1e25f8070e1f952509b6575ced19b4237e7ec5",
  "posit-dev/mcptools@ff94da04ccb5e6e86a56537c9d2dcb0e0532067b",
  "r-lib/Rapp@489655f24945042791ddb083d0d5518c4a905d9f",
  "r-lib/httr2@b9d93794884228bd6654ca7f2abc0162c1ba5f81"
)
pak::pkg_install(refs, upgrade = TRUE, ask = FALSE,
  dependencies = c("Depends", "Imports", "LinkingTo"))

for (pkg in c("ellmer", "btw", "shinychat", "shiny", "bslib",
              "mcptools", "Rapp", "httr2")) {
  desc <- packageDescription(pkg)
  cat(pkg, desc[["Version"]], desc[["RemoteSha"]], "\n")
}
```

**注意：** shinychat 是monorepo，必须使用`posit-dev/shinychat/pkg-r`。

## codeagent 0.2.0 shared release 基线

最后验证：2026-08-20。共享发布库：`/usrfiles/shared-projects/users/kaiping_yang/Rlibs/codeagent/R-4.4`。

| 包 | release版本 | release GitHub SHA |
|---|---|---|
| ellmer | 0.4.2.9000 | `19be478ebf1a2e5d2db96a8aeaca71592c8d3f26` |
| btw | 1.4.0.9000 | `d11591b09d9127b05d673e8c96569d2bbae2ec44` |
| shinychat | 0.4.0.9000 | `c1654aa2e13c979e52a16edace094d30680fa4dd` |
| shiny | 1.14.0 | stable shared build |
| bslib | 0.11.0 | stable shared build |

开发版经常只更新Git SHA而不改变`Version`；ellmer、btw、shinychat必须比较完整`RemoteSha`，不能只比较`packageVersion()`。codeagent 0.2.0的`DESCRIPTION`有意固定上述三个已验收SHA。

### 安装release固定依赖

```r
pak::pak(c(
  "tidyverse/ellmer@19be478ebf1a2e5d2db96a8aeaca71592c8d3f26",
  "posit-dev/btw@d11591b09d9127b05d673e8c96569d2bbae2ec44",
  "posit-dev/shinychat/pkg-r@c1654aa2e13c979e52a16edace094d30680fa4dd"
), ask = FALSE)
```

当前个人默认开发环境使用以下完整manifest；0.2.0 shared library保持上方历史
基线，不得被普通开发安装覆盖：

- `ellmer` 0.5.0.9000 @ `248c86704a52baf2f4f66a91f12b42a48ddac993`
- `btw` 1.5.0.9000 @ `6a27d997120f11cfda15bf0a5953a22329b01715`
- `shinychat` 0.5.0.9000 @ `05e0bbd987286068638d3cf96d6ea7daff15c5b2`（monorepo：`posit-dev/shinychat/pkg-r`）
- `shiny` 1.14.0.9000 @ `bbc43849f06059f5daa7310ea0f40ec901f0ed0f`
- `bslib` 0.12.0.9000 @ `ac1e25f8070e1f952509b6575ced19b4237e7ec5`
- `mcptools` 1.0.3.9000 @ `ff94da04ccb5e6e86a56537c9d2dcb0e0532067b`
- `Rapp` 0.4.1.9000 @ `489655f24945042791ddb083d0d5518c4a905d9f`
- `httr2` 1.3.0.9000 @ `b9d93794884228bd6654ca7f2abc0162c1ba5f81`

普通运行不依赖`/tmp` candidate。exact shinychat的官方tool结果取值是
`open_style = "framed"`（不是`"frame"`）；它还提供`page_chat()`、
`chat_drawer()`和compact citations。Shiny开发版内含`shiny-for-r` skill。
逐包核对完整`RemoteSha`，然后重跑testthat、R CMD check和两种布局的Chromium gate。

模型价格从不自动联网刷新；需要时显式调用`codeagent::update_model_prices()`。失败会保留现有cache，custom/private endpoint即使刷新后也可能仍无价格。

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
| `Chat$on_request_start()` / `$on_request_end()` | ellmer | `R/compaction.R` 在每次模型请求前执行 mid-loop compaction；完整 outgoing turns 用于阈值计数 |
| `models_update_prices()` | ellmer | `update_model_prices()` 显式调用；从不启动时自动执行 |
| `ContentCitation` / content stream | ellmer | 自定义 web 使用当前-turn marker bridge，不信任 raw model aside |
| `btw_tool_files_patch` | btw | `R/tools_btw_files_pathA.R` Path A |
| `btw_tools()` groups | btw | 唯一 Agent owner + Settings 原子组替换 |
| `tool_result_display()` | shinychat | 官方 display、label/value preview；artifact/sources 留在私有 metadata |
| `chat_greeting(persistent=TRUE)` | shinychat | New/Delete/Restore 后 greeting 不丢失、不重复 |
| `allow_attachments=` / `user_input_contents()` | shinychat | `R/ui_panels.R` / `R/server_chat.R` |
| `contents_shinychat()` | shinychat | presentation-only legacy replay migration |
