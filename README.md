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
chmod +x ./scripts/smart-web-fetch-core
```

### 依赖

> Bash core 采用严格模式（`set -euo pipefail`）执行；参数缺值等边界情况会直接报错退出。

| 运行入口 | 依赖项 | 类型 | 启动时行为 |
| --- | --- | --- | --- |
| `scripts/smart-web-fetch`（Bash） | `curl` | 必需 | 缺失时自动切换到 PowerShell 路径；若 `pwsh` 也不存在则报错退出 |
| `scripts/smart-web-fetch`（Bash） | `jq` | 可选 | verbose 模式下提示缺失，继续执行并回退内置 JSON 解析 |
| `scripts/smart-web-fetch`（Bash） | `perl` | 可选 | verbose 模式下提示缺失，继续执行并回退 awk 轻量 HTML 清洗 |
| `scripts/smart-web-fetch`（Bash） | `html2text` / `lynx` | 可选 | 两者都缺失时仅提示，继续执行并输出清洗后的 HTML |
| `scripts/smart-web-fetch.ps1`（PowerShell） | PowerShell 7+ | 必需 | 版本不足时立即报错并退出 |
| `scripts/smart-web-fetch.ps1`（PowerShell） | `Invoke-WebRequest` | 必需 | 不可用时立即报错并退出 |
| `scripts/smart-web-fetch.ps1`（PowerShell） | `jq` | 可选 | verbose 模式下提示缺失，继续执行并回退 `ConvertFrom-Json` |
| `scripts/smart-web-fetch.ps1`（PowerShell） | `perl` | 可选 | verbose 模式下提示缺失，继续执行并回退 PowerShell 正则清洗 |
| `scripts/smart-web-fetch.ps1`（PowerShell） | `html2text` / `lynx` | 可选 | 两者都缺失时仅提示，继续执行并输出清洗后的 HTML |

### 常见安装命令

#### macOS

```bash
brew install jq html2text lynx perl
```

#### Debian / Ubuntu

```bash
sudo apt-get update && sudo apt-get install -y curl jq html2text lynx perl
```

#### Fedora / RHEL / CentOS Stream

```bash
sudo dnf install -y curl jq html2text lynx perl
```

#### Arch Linux

```bash
sudo pacman -S --needed curl jq html2text lynx perl
```

#### Windows

```powershell
winget install Microsoft.PowerShell jqlang.jq StrawberryPerl.StrawberryPerl lynx.portable
py -m pip install html2text
```

## 🚀 快速开始

所有终端使用统一命令名称和参数接口。以下示例默认在发行包根目录或下载后的 `skills/smart-web-fetch/` 目录中执行。

| 终端环境 | 调用方式 |
| --- | --- |
| Linux / macOS / WSL / Git Bash | `./scripts/smart-web-fetch <URL>` |
| Windows CMD / 原生 PowerShell | `.\scripts\smart-web-fetch <URL>` |
| PowerShell 7（显式调用） | `pwsh -File .\scripts\smart-web-fetch.ps1 <URL>` |

入口脚本自动检测运行时：有 `curl` 时走 Bash 路径，否则回退 PowerShell 7。Windows 下 `.cmd` 文件直接调用 PowerShell 包装器。

### 常用示例

```bash
./scripts/smart-web-fetch https://example.com -o article.md
./scripts/smart-web-fetch https://example.com -s jina
./scripts/smart-web-fetch https://example.com -v
./scripts/smart-web-fetch https://example.com --no-clean
```

Windows CMD / 原生 PowerShell：

```cmd
.\scripts\smart-web-fetch https://example.com -o article.md
.\scripts\smart-web-fetch https://example.com -s jina
.\scripts\smart-web-fetch https://example.com -v
.\scripts\smart-web-fetch https://example.com --no-clean
```

## ⚙️ 参数一览

| 功能 | 参数 |
| --- | --- |
| 显示帮助 | `-h` / `--help` |
| 输出到文件 | `-o <FILE>` / `--output <FILE>` |
| 指定服务源 | `-s <NAME>` / `--service <NAME>` |
| 显示详细日志 | `-v` / `--verbose` |
| 跳过 HTML 清洗 | `--no-clean` |

`-s` / `--service` 可选值：`jina`、`markdown`、`defuddle`。未知参数直接报错。

## 🔄 抓取策略

默认按以下顺序依次尝试，前一个失败才进入下一个；全部失败时以非零状态退出并报告最后一次失败原因。显式指定服务源（`-s` / `--service`）后只尝试该源，失败直接报错。

| # | 服务源 | 方式 | 请求端点 |
| :---: | --- | :---: | --- |
| 1 | Jina Reader | GET | `r.jina.ai/<URL>` |
| 2 | markdown.new | POST | `api.markdown.new/api/v1/convert` |
| 3 | defuddle.md | POST | `defuddle.md/api/convert` |
| 4 | basic fallback | GET | 原始 URL，本地 HTML 清洗 |

仓库中的详细判定规则见 [`spec/fetch-contract.md`](spec/fetch-contract.md)。

## 📁 仓库目录结构

```text
smart-web-fetch/
├── skills/
│   └── smart-web-fetch/
│       ├── SKILL.md
│       ├── assets/
│       └── scripts/
├── spec/
│   ├── fetch-contract.md
│   └── fixtures/
├── README.md
├── README_EN.md
└── LICENSE
```

## License

MIT
