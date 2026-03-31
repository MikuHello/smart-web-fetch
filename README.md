# Smart Web Fetch

面向智能体、脚本和自动化流程的轻量级网页抓取工具，把网页内容转换成干净、易复用的 Markdown。

> Fork 自 `Kim-Huang-JunKai/smart-web-fetch`
> 借鉴来源：`clawhub.ai/Leochens/smart-web-fetch`，感谢原作者的创意和工作流设计。

## 🎯 适合做什么

- 把网页正文转换成适合阅读、总结和二次处理的 Markdown
- 给 agent / 自动化流程提供稳定的网页读取入口
- 在单一服务源失败时自动切换后备路径
- 将抓取结果保存到文件，便于归档和分析

## 📦 安装

```bash
git clone https://github.com/<your-org>/smart-web-fetch.git
cd smart-web-fetch
```

**Linux / macOS / WSL / Git Bash** — 赋予执行权限：

```bash
chmod +x ./skills/smart-web-fetch/scripts/smart-web-fetch
chmod +x ./skills/smart-web-fetch/scripts/smart-web-fetch-core
```


### 依赖

| 依赖项 | 说明 |
| --- | --- |
| `curl` | Bash 路径必需；缺失时自动切换到 PowerShell 路径 |
| PowerShell 7 + `Invoke-WebRequest` | `curl` 不可用时必需；两者均缺失则报错退出 |
| `jq` | 可选；缺失时 Bash 回退内置解析，PowerShell 回退 `ConvertFrom-Json` |
| `perl` | 可选；缺失时回退 awk / 原生正则清洗，HTML 清洗效果略弱 |
| `html2text` / `lynx` | 可选；缺失时 basic fallback 保留清洗后 HTML，不转纯文本 |

> Bash core 采用严格模式（`set -euo pipefail`）执行；参数缺值等边界情况会直接报错退出。

## 🚀 快速开始

所有终端使用**统一命令名称和参数接口**：

| 终端环境 | 调用方式 |
| --- | --- |
| Linux / macOS / WSL / Git Bash | `./skills/smart-web-fetch/scripts/smart-web-fetch <URL>` |
| Windows CMD / 原生 PowerShell | `.\skills\smart-web-fetch\scripts\smart-web-fetch <URL>` |
| PowerShell 7（显式调用） | `pwsh -File .\skills\smart-web-fetch\scripts\smart-web-fetch.ps1 <URL>` |

入口脚本自动检测运行时：有 `curl` 时走 Bash 路径，否则回退 PowerShell 7。Windows 下 `.cmd` 文件直接调用 PowerShell 包装器。

### 常用示例

```bash
./skills/smart-web-fetch/scripts/smart-web-fetch https://example.com -o article.md   # 保存到文件
./skills/smart-web-fetch/scripts/smart-web-fetch https://example.com -s jina          # 指定服务源
./skills/smart-web-fetch/scripts/smart-web-fetch https://example.com -v               # 详细日志
./skills/smart-web-fetch/scripts/smart-web-fetch https://example.com --no-clean       # 跳过 HTML 清洗
```

Windows CMD / 原生 PowerShell：

```cmd
.\skills\smart-web-fetch\scripts\smart-web-fetch https://example.com -o article.md
.\skills\smart-web-fetch\scripts\smart-web-fetch https://example.com -s jina
.\skills\smart-web-fetch\scripts\smart-web-fetch https://example.com -v
.\skills\smart-web-fetch\scripts\smart-web-fetch https://example.com --no-clean
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

> 详细判定规则见 [`spec/fetch-contract.md`](spec/fetch-contract.md)。

## 📁 目录结构

```
smart-web-fetch/
├── skills/smart-web-fetch/
│   ├── SKILL.md                          # 智能体集成说明
│   ├── scripts/
│   │   ├── smart-web-fetch               # 统一入口（Bash / Git Bash）
│   │   ├── smart-web-fetch.ps1           # 统一入口（PowerShell 7）
│   │   ├── smart-web-fetch.cmd           # 统一入口（Windows CMD / 原生 PowerShell）
│   │   ├── smart-web-fetch-core          # Bash 核心实现（不直接调用）
│   │   └── smart-web-fetch-core.ps1      # PowerShell 核心实现（不直接调用）
│   └── assets/
│       └── fetch-rules.json              # 阈值与关键词规则（可调）
├── spec/
│   ├── fetch-contract.md                 # 行为契约与回归用例
│   └── fixtures/                         # 离线测试样例数据
├── README.md
└── LICENSE
```

## License

MIT
