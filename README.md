# Smart Web Fetch

[English](./README_EN.md)

面向智能体、脚本和自动化流程的轻量级网页抓取工具，把网页内容转换成干净、易复用的 Markdown。

> Fork 自 `Kim-Huang-JunKai/smart-web-fetch`  
> 借鉴来源：`clawhub.ai/Leochens/smart-web-fetch`，感谢原作者的创意和工作流设计。

## 🎯 核心定位

面向已知 URL 的网页读取与正文提取工具。

- 将网页正文转换成适合阅读、总结和二次处理的 Markdown
- 为 agent 和自动化流程提供稳定的已知 URL 读取入口
- 内置服务降级策略，在单一路径失败时自动切换后备路径
- 支持将抓取结果保存到文件，便于归档和分析

## 📦 安装

优先从最新发行版页面下载：[Latest release](https://github.com/MikuHello/smart-web-fetch/releases/latest)。
也可以直接下载仓库中的 `skills/smart-web-fetch` 目录。

以下命令默认在发行包根目录或下载后的 `skills/smart-web-fetch/` 目录中执行。
如果你是直接 clone 整个仓库，请先执行 `cd skills/smart-web-fetch`。

**Linux / macOS / WSL / Git Bash** 需要先赋予执行权限：

```bash
chmod +x ./scripts/smart-web-fetch
```

### 依赖

- 统一运行时基线为 `Python 3.11+`
- 默认只依赖 Python 标准库
- `core/` 是内部实现包；对外包装器会执行技能根目录下确定的 `main.py` bootstrap，再由它引导 `core.cli:main`
- 运行时无需 `curl` / `pwsh` / `jq` / `perl` / `html2text` / `lynx`

### 常见安装命令

#### macOS

```bash
brew install python
```

#### Debian / Ubuntu

```bash
sudo apt-get update && sudo apt-get install -y python3
```

#### Fedora / RHEL / CentOS Stream

```bash
sudo dnf install -y python3
```

#### Arch Linux

```bash
sudo pacman -S --needed python
```

#### Windows

```powershell
winget install Python.Python.3.11
```

## 🚀 快速开始

所有终端使用统一命令名称和参数接口。以下示例默认在发行包根目录或下载后的 `skills/smart-web-fetch/` 目录中执行。

| 终端环境 | 调用方式 |
| --- | --- |
| Linux / macOS / WSL / Git Bash | `./scripts/smart-web-fetch <URL>` |
| Windows CMD / 原生 PowerShell | `.\scripts\smart-web-fetch <URL>` |
| PowerShell 7（显式调用） | `pwsh -File .\scripts\smart-web-fetch.ps1 <URL>` |

### 按场景使用

直接查看正文：

```bash
./scripts/smart-web-fetch https://example.com
```

保存到文件：

```bash
./scripts/smart-web-fetch https://example.com -o article.md
```

返回结构化 JSON：

```bash
./scripts/smart-web-fetch https://example.com --json
```

指定服务源或调试抓取过程：

```bash
./scripts/smart-web-fetch https://example.com -s jina
./scripts/smart-web-fetch https://example.com -v
./scripts/smart-web-fetch https://example.com --no-clean
```

Windows CMD / 原生 PowerShell 示例：

```cmd
.\scripts\smart-web-fetch https://example.com
.\scripts\smart-web-fetch https://example.com -o article.md
.\scripts\smart-web-fetch https://example.com --json
.\scripts\smart-web-fetch https://example.com -s jina
.\scripts\smart-web-fetch https://example.com -v
.\scripts\smart-web-fetch https://example.com --no-clean
```

## ⚙️ 参数一览

| 参数 | 说明 | 备注 |
| --- | --- | --- |
| `-h`, `--help` | 显示帮助 | 仅打印帮助并退出 |
| `-o <FILE>`, `--output <FILE>` | 写入输出文件 | 默认写正文；配合 `--json` 时写结构化结果 |
| `-s <NAME>`, `--service <NAME>` | 强制指定服务源 | 可选值：`jina`、`markdown`、`defuddle` |
| `--json` | 返回结构化结果 | 适合脚本、自动化和 agent 消费 |
| `-v`, `--verbose` | 显示详细日志 | 日志输出到 stderr |
| `--no-clean` | 跳过 basic fallback 的 HTML 清洗 | 只影响 direct/basic fallback 路径 |

## 🧾 输出方式

默认情况下，命令会直接输出抓取到的正文内容，适合在终端中阅读，或通过重定向保存到文件。

如果需要把结果交给脚本、自动化流程或 agent 继续处理，可以加上 `--json`。此时命令会返回结构化结果，例如：

```json
{"success":true,"url":"https://example.com","content":"...","source":"jina"}
```

在 `--json` 模式下，失败时也会返回 JSON，并附带错误信息。`source` 会标明实际命中的来源。`--json` 也可以与 `-o` / `--output` 组合使用，此时文件会写入当前模式下的最终输出。

## 🔄 抓取策略

默认按以下顺序依次尝试，前一个失败才进入下一个；全部失败时以非零状态退出并报告最后一次失败原因。显式指定服务源（`-s` / `--service`）后只尝试该源，失败直接报错。

| 优先级 | 服务源 | 方式 | 请求端点 |
| :---: | --- | :---: | --- |
| 1 | Jina Reader | GET | `r.jina.ai/<URL>` |
| 2 | markdown.new | POST | `api.markdown.new/api/v1/convert` |
| 3 | defuddle.md | POST | `defuddle.md/api/convert` |
| 4 | basic fallback | GET | 原始 URL，本地 HTML 清洗 |

仓库中的详细判定规则见 [`spec/fetch-contract.md`](spec/fetch-contract.md)。

补充说明：

- 未带 scheme 的 URL 会自动补成 `https://`
- 仅允许 `http://` / `https://`；如 `ftp://` 会直接失败
- `basic fallback` 遇到图片、PDF、压缩包等二进制响应会直接失败，不返回乱码文本

## License

MIT
