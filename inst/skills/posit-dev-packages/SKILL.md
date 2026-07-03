---
name: posit-dev-packages
description: 更新 ellmer/btw/shinychat 到最新开发版，并显示开发版相比 CRAN 的新功能。当用户提到"更新开发包"、"dev version"、"开发版包"、"更新 ellmer btw shinychat"、"posit dev packages"时触发。
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

# 验证版本
for (pkg in c("ellmer", "btw", "shinychat")) {
  cat(pkg, ":", as.character(packageVersion(pkg)), "\n")
}
```

**注意：** shinychat 是 monorepo，必须用 `posit-dev/shinychat/pkg-r`，不能用 `posit-dev/shinychat`。

## 各包开发版新功能

详见 skill 目录下的 references 文件：

- `references/ellmer-dev.md` — ellmer 开发版新功能
- `references/btw-dev.md` — btw 1.3.0 开发版新功能  
- `references/shinychat-dev.md` — shinychat 开发版新功能

## codeagent 已使用的开发版功能

| 功能 | 包 | 用在哪 |
|------|-----|--------|
| `set_model()` | ellmer | `R/model_switch.R` |
| `chat_posit()` | ellmer | `R/setup.R` + `R/query.R` |
| `tool(name=)` | ellmer | 所有工具（Bash/Read/Write/...） |
| `btw_tool_files_patch` | btw | `R/tools_btw_files_pathA.R` Path A |
| `allow_attachments=` | shinychat | `R/ui_panels.R` |
| `user_input_contents()` | shinychat | `R/server_chat.R` |
