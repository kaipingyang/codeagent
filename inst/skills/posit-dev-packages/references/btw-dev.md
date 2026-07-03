# btw 开发版新功能（vs CRAN 1.2.1）

当前安装：1.3.0.9000（GitHub: posit-dev/btw）

## 1.3.0 主要新功能

### `btw_tool_files_patch`（新工具）
原子多文件 patch：一次调用 add/update/delete/rename 多个文件，全部验证通过后才写入，部分失败不留痕。
```r
# 工具参数
btw::btw_tool_files_patch  # 已加入 codeagent Path A
```
codeagent 已在 `R/tools_btw_files_pathA.R` 的 `.BTW_FILE_WRITE` 列表中加入。

### `btw_app(model_choices = ...)` 参数
btw Shiny app 内置模型切换 UI。可传模型列表，切换时保留 chat 历史和 tools。
```r
btw::btw_app(model_choices = c("claude-sonnet-4-6", "claude-haiku-4-5"))
```
codeagent 有自己的 `/model` modal，不使用此参数。

### btw skills CLI 扩展
```bash
btw skills list              # 列出已安装 skills
btw skills get <name>        # 显示 skill 内容
btw skills resource <name>   # 列出 skill 资源
btw app                      # 启动 btw Shiny app
btw system-info              # 系统信息
btw check-installed          # 检查包安装状态
btw installed-packages       # 列出已安装包
```

### `btw.skills.paths` 选项
自定义 skill 搜索目录。
```r
options(btw.skills.paths = c("~/.my-skills", "./.project-skills"))
```

## 文件工具（1.2.0 起有，1.3.0 扩展）

### 两路径架构（codeagent 视角）

| 工具 | 来源 | 路径范围 | 特色 |
|------|------|----------|------|
| Read/Write/Edit/MultiEdit | codeagent 内置 | 任意绝对路径 | 权限门控 |
| btw_tool_files_read | btw | **仅 cwd 内** | 行 hash 注解（`1:abc\|content`） |
| btw_tool_files_edit | btw | **仅 cwd 内** | hash 锚定，stale edit 拒绝 |
| btw_tool_files_replace | btw | **仅 cwd 内** | 精确 find-replace，唯一匹配保护 |
| btw_tool_files_patch | btw | **仅 cwd 内** | 原子多文件 patch |
| btw_tool_files_write | btw | **仅 cwd 内** | 覆盖写 |
| btw_tool_files_list | btw | **仅 cwd 内** | 列目录 |
| btw_tool_files_search | btw | **仅 cwd 内** | 代码搜索（ripgrep + duckdb 索引） |

**cwd 限制是设计选择**：btw 工具对项目目录外的文件拒绝操作，这是安全架构。codeagent 两套工具并存，LLM 根据需要选择。

## 启用 Path A（两套并存）

```r
library(codeagent)
enable_btw_file_tools()   # sets options(codeagent.use_btw_files = TRUE)
client <- codeagent_client(chat)
# 现在 chat 上有两套工具：codeagent (绝对路径) + btw (cwd-safe hash-locked)
```

## 1.2.0 功能（已在 codeagent 中使用）

- `btw_tool_agent_subagent()`：隔离 subagent
- `btw_tool_skill()`：skill 调用工具
- `btw_tool_run_r()`：R 代码执行（codeagent 用 RunR 代替）
- `btw_tool_files_edit()`：hash 锚定编辑
- `btw_tool_files_replace()`：精确替换
- `btw_tool_pkg_load_all()`：devtools::load_all()
