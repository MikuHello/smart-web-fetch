# Smart Web Fetch - Agent Edition

轻量级网页抓取 Skill / CLI，适合需要更干净、更易复用网页内容的智能体工作流。

> 项目 Fork 自 `Kim-Huang-JunKai/smart-web-fetch`  
> **借鉴来源：** clawhub.ai/Leochens/smart-web-fetch，感谢原作者的创意和工作流设计。

工具会抓取目标 URL，并优先输出更干净的 Markdown 内容，默认按以下顺序自动降级：

1. `Jina Reader`
2. `markdown.new`
3. `defuddle.md`
4. 直接 fallback 抓取

项目刻意保持小而简单，方便在不同智能体系统中复用：

- `SKILL.md`：适用于 Codex 风格的 Skill 系统
- `skill.json`：适用于 Claude 风格的 Skill 注册方式
- `smart-web-fetch`：适用于 Bash / 类 Unix 环境中的通用智能体、脚本和自动化流程
- `smart-web-fetch.ps1`：适用于 Windows / `pwsh 7` 的原生 PowerShell 用法

## 功能特性

- 优先输出 Markdown，减少 HTML 噪音和 Token 消耗
- 内置多服务自动降级策略
- 支持将抓取结果写入文件
- 支持详细日志输出，方便排查问题
- 基础 fallback 路径支持 HTML 清洗

## 使用前提

- 需要当前宿主环境提供可用的联网能力，例如搜索工具、网络访问权限，或可发起 HTTP 请求的命令行环境
- 本 Skill 负责提供抓取流程和调用方式，实际能否联网取决于运行它的工具环境

## 依赖

### Bash / 类 Unix CLI

- `curl`：必需（启动时强校验；缺失直接报错并退出）
- `jq`：可选，用于从 JSON 响应中提取 Markdown 字段
- `html2text` 或 `lynx`：可选，用于将 fallback HTML 转成纯文本
- `perl`：可选，用于在 fallback 模式下进行更强的 HTML 清洗

### PowerShell CLI

- PowerShell 7 + `Invoke-WebRequest`：必需（启动时强校验；缺失直接报错并退出）
- `html2text` 或 `lynx`：可选，用于将 fallback HTML 转成纯文本
- `jq`：可选，安装后会优先用于 `markdown.new` 的 JSON 字段提取
- `perl`：可选，安装后会优先用于基础 fallback 的更强 HTML 清洗
- 默认 PowerShell 流程不依赖 `curl`，未安装 `jq` / `perl` 时会回退到原生 PowerShell 解析与清洗逻辑

### 启动时依赖检查与行为对应

> 两个 CLI 都会在开始抓取前执行依赖检查；错误统一为 `[ERROR] [Dependency] ...` 格式。

| 运行入口 | 依赖项 | 类型 | 启动时行为 |
| --- | --- | --- | --- |
| `smart-web-fetch` (Bash) | `curl` | 必需 | 缺失时立即报错并退出 |
| `smart-web-fetch` (Bash) | `jq` | 可选 | 缺失时仅提示（verbose 下），继续运行并回退 |
| `smart-web-fetch` (Bash) | `perl` | 可选 | 缺失时仅提示（verbose 下），继续运行并回退到 `sed` 轻量块级 + 属性清洗 |
| `smart-web-fetch` (Bash) | `html2text` / `lynx` | 可选 | 两者都缺失时仅提示（verbose 下），继续运行并输出清洗后的 HTML |
| `smart-web-fetch.ps1` (PowerShell) | PowerShell 7+ | 必需 | 版本不足时立即报错并退出 |
| `smart-web-fetch.ps1` (PowerShell) | `Invoke-WebRequest` | 必需 | 不可用时立即报错并退出 |
| `smart-web-fetch.ps1` (PowerShell) | `jq` | 可选 | 缺失时仅提示（verbose 下），继续运行并回退到原生 JSON 解析 |
| `smart-web-fetch.ps1` (PowerShell) | `perl` | 可选 | 缺失时仅提示（verbose 下），继续运行并回退到 PowerShell 正则清洗 |
| `smart-web-fetch.ps1` (PowerShell) | `html2text` / `lynx` | 可选 | 两者都缺失时仅提示（verbose 下），继续运行并输出清洗后的 HTML |

### 常见安装示例

#### macOS (Homebrew)

```bash
brew install curl jq html2text lynx perl
```

#### Debian / Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y curl jq html2text lynx perl
```

#### Fedora / RHEL / CentOS Stream

```bash
sudo dnf install -y curl jq html2text lynx perl
```

#### Arch Linux

```bash
sudo pacman -S --needed curl jq html2text lynx perl
```

#### Windows（PowerShell 版：PowerShell 7 + 可选辅助工具）

```powershell
# winget install Microsoft.PowerShell
winget install jqlang.jq
winget install StrawberryPerl.StrawberryPerl
# winget install Python.Python.3
py -m pip install html2text
winget install lynx.portable
```

如果你只使用 PowerShell 版 `smart-web-fetch.ps1`，核心要求是 PowerShell 7；`jq`、`perl`、`html2text`、`lynx` 都是可选增强项，其中 `jq` 和 `perl` 在安装后会优先参与与 Bash 版一致的解析和清洗流程。

#### Windows（Bash 版：Git Bash / WSL / MSYS2 等环境）

```powershell
# winget install Microsoft.PowerShell
# winget install Git.Git
winget install jqlang.jq
winget install StrawberryPerl.StrawberryPerl
# winget install Python.Python.3
py -m pip install html2text
winget install lynx.portable
```

在 Windows 上运行 Bash 版 `smart-web-fetch` 时，至少需要可用的 `curl` 环境；`jq`、`perl`、`html2text`、`lynx` 都是推荐安装的增强项。若使用 WSL，也可以直接按 Linux 发行版方式安装这些依赖。

## 安装

### 方式一：直接在仓库中运行

```bash
./smart-web-fetch https://example.com
```

### 方式二：将 Bash CLI 加入 `PATH`

```bash
chmod +x smart-web-fetch
cp smart-web-fetch /usr/local/bin/smart-web-fetch
smart-web-fetch https://example.com
```

如果你的环境不使用 `/usr/local/bin`，放到任意已在 `PATH` 中的目录即可。

### Windows 原生用法

```powershell
pwsh -File .\smart-web-fetch.ps1 https://example.com
```

## 使用方法

### Bash / 类 Unix 环境

```bash
smart-web-fetch <URL> [options]
```

### PowerShell 7

```powershell
./smart-web-fetch.ps1 <URL> [-Output FILE] [-Service jina|markdown|defuddle] [-VerboseMode] [-NoClean]
```

### 示例

```bash
smart-web-fetch https://example.com
smart-web-fetch https://example.com -o output.md
smart-web-fetch https://example.com -s jina
smart-web-fetch https://example.com --no-clean
smart-web-fetch https://example.com -v
# 参数值不可省略：下面写法会报错并显示帮助
smart-web-fetch https://example.com -o
smart-web-fetch https://example.com -s
smart-web-fetch https://example.com -s -v
# 仅支持一个 URL：多 URL 输入会报错并显示帮助（不会取最后一个）
smart-web-fetch https://example.com https://openai.com
```

```powershell
./smart-web-fetch.ps1 https://example.com
./smart-web-fetch.ps1 https://example.com -Output output.md
./smart-web-fetch.ps1 https://example.com -Service jina
./smart-web-fetch.ps1 https://example.com -NoClean
./smart-web-fetch.ps1 https://example.com -VerboseMode
./smart-web-fetch.ps1 -Help
./smart-web-fetch.ps1 -h
./smart-web-fetch.ps1 --help
# 仅支持一个 URL：多 URL 或未知参数会直接报错
./smart-web-fetch.ps1 https://example.com https://openai.com
./smart-web-fetch.ps1 https://example.com -VerbosMode
```

### 参数说明

| 参数 | 说明 |
| --- | --- |
| Bash：`-h`, `--help` | 显示帮助 |
| Bash：`-o`, `--output FILE` | 输出到文件 |
| Bash：`-s`, `--service NAME` | 强制指定服务：`jina`、`markdown` 或 `defuddle`（失败即报错，不再自动降级） |
| Bash：`-v`, `--verbose` | 显示详细日志 |
| Bash：`--no-clean` | 跳过基础 fallback 路径中的 HTML 清洗 |
| PowerShell：`-Help`, `-h`, `--help` | 显示帮助（`--help` 兼容） |
| PowerShell：`-Output` | 输出到文件 |
| PowerShell：`-Service` | 强制指定服务：`jina`、`markdown` 或 `defuddle`（失败即报错，不再自动降级） |
| PowerShell：`-VerboseMode` | 显示详细日志 |
| PowerShell：`-NoClean` | 跳过基础 fallback 路径中的 HTML 清洗 |

> PowerShell 版会严格校验额外参数：仅允许一个 URL；未知参数（如拼写错误的开关）会直接报错，避免静默忽略。

## 默认服务顺序

默认自动尝试顺序：

1. `jina`
2. `markdown`
3. `defuddle`
4. 基础 fallback

补充判定规则（Bash 与 PowerShell 一致）：
- 对所有路径统一要求 HTTP 2xx（包含基础 fallback）。
- `markdown.new` / `defuddle` 除结构化错误判定外，还会识别典型 HTML 错误页（例如 Access Denied/CAPTCHA/网关错误）并按失败处理。

## 规则文件与离线回归

- 统一规则文件：`docs/fetch-rules.json`（阈值、关键词、provider 顺序）。
- 两个 CLI 会优先读取该文件；读取失败时自动回退到脚本内置默认值。
- 离线样例与回归说明：`docs/qa-cases.md` 与 `fixtures/`。

## Bash / PowerShell 一致性说明

`smart-web-fetch`（Bash）与 `smart-web-fetch.ps1`（PowerShell）遵循同一抓取判定契约，包括：

- provider 顺序与 forced service 行为
- HTTP 2xx 与最小长度阈值判定
- 结构化错误字段识别规则
- `markdown.new` / `defuddle` 的 HTML 错误页识别
- basic fallback 的分阶段校验（拉取后 / 清洗后 / 转换后）
- 自动降级全部失败时包含最后一次失败原因（便于排障）

详细规则见：`docs/fetch-contract.md`。

## 说明

## Jina 入参拼接规则（Bash 与 PowerShell 一致）

为避免 `r.jina.ai` 路径出现重复协议层（例如 `.../http://https://example.com`），两个 CLI 统一采用以下规则构造 Jina 请求地址：

1. 先把目标 URL 规范化为 `http://` 或 `https://` 开头。
2. 解析出原始协议（`http` / `https`）和“去协议”的 URL 主体（`example.com/path?...`）。
3. 按 `https://r.jina.ai/<原始协议>://<去协议URL>` 进行拼接。

例如：

- `https://example.com/a?b=1` → `https://r.jina.ai/https://example.com/a?b=1`
- `http://example.com/a?b=1` → `https://r.jina.ai/http://example.com/a?b=1`

这样可以确保 Jina 路径中协议层只出现一次，避免后续维护时误拼接。

- `--no-clean` 只影响基础 fallback 路径，不会修改外部服务返回的内容。
- 如果安装了 `jq` / `perl`，PowerShell 版会优先使用它们；未安装时会自动回退到原生 PowerShell 解析与清洗逻辑。
- 如果没有安装 `html2text` 或 `lynx`，fallback 路径会返回清洗后的 HTML，而不是转换后的纯文本。
- 某些网站可能会拦截第三方清洗服务，此时工具会回退到直接抓取路径。

## License

MIT
