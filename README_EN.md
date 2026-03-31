# Smart Web Fetch

Lightweight web fetching for agents, scripts, and automation workflows, converting web pages into clean, reusable Markdown.

> Forked from `Kim-Huang-JunKai/smart-web-fetch`  
> Inspired by `clawhub.ai/Leochens/smart-web-fetch`, with thanks to the original author for the idea and workflow design.

## 🎯 Core Positioning

A webpage reading and main-content extraction tool for known URLs.

- Converts webpage content into Markdown suitable for reading, summarization, and downstream processing
- Provides a stable known-URL reading entry point for agents and automation workflows
- Includes a fallback strategy that automatically switches providers when one path fails
- Supports saving fetched output to files for archiving and analysis

## 📦 Installation

Prefer downloading from the latest release page: [Latest release](https://github.com/MikuHello/smart-web-fetch/releases/latest).
You can also download the `skills/smart-web-fetch` directory directly from the repository.

The commands below assume you are running from the release-package root or the downloaded `skills/smart-web-fetch/` directory.
If you cloned the full repository, run `cd skills/smart-web-fetch` first.

**Linux / macOS / WSL / Git Bash** should make the scripts executable first:

```bash
chmod +x ./scripts/smart-web-fetch
chmod +x ./scripts/smart-web-fetch-core
```

### Dependencies

> The Bash core runs in strict mode (`set -euo pipefail`); missing option values and similar edge cases exit explicitly.

| Entry Point | Dependency | Type | Startup Behavior |
| --- | --- | --- | --- |
| `scripts/smart-web-fetch` (Bash) | `curl` | Required | Falls back to PowerShell when missing; exits with an error if `pwsh` is also unavailable |
| `scripts/smart-web-fetch` (Bash) | `jq` | Optional | Warns in verbose mode and falls back to built-in JSON parsing |
| `scripts/smart-web-fetch` (Bash) | `perl` | Optional | Warns in verbose mode and falls back to awk-based HTML cleanup |
| `scripts/smart-web-fetch` (Bash) | `html2text` / `lynx` | Optional | Warns when both are missing and returns cleaned HTML instead of plain text |
| `scripts/smart-web-fetch.ps1` (PowerShell) | PowerShell 7+ | Required | Exits immediately when the runtime version is insufficient |
| `scripts/smart-web-fetch.ps1` (PowerShell) | `Invoke-WebRequest` | Required | Exits immediately when unavailable |
| `scripts/smart-web-fetch.ps1` (PowerShell) | `jq` | Optional | Warns in verbose mode and falls back to `ConvertFrom-Json` |
| `scripts/smart-web-fetch.ps1` (PowerShell) | `perl` | Optional | Warns in verbose mode and falls back to PowerShell regex cleanup |
| `scripts/smart-web-fetch.ps1` (PowerShell) | `html2text` / `lynx` | Optional | Warns when both are missing and returns cleaned HTML instead of plain text |

### Common install commands

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

## 🚀 Quick Start

All terminals use the same command name and argument interface. The examples below assume you are running from the release-package root or the downloaded `skills/smart-web-fetch/` directory.

| Terminal Environment | Invocation |
| --- | --- |
| Linux / macOS / WSL / Git Bash | `./scripts/smart-web-fetch <URL>` |
| Windows CMD / native PowerShell | `.\scripts\smart-web-fetch <URL>` |
| PowerShell 7 (explicit invocation) | `pwsh -File .\scripts\smart-web-fetch.ps1 <URL>` |

The entry script detects the runtime automatically: it prefers the Bash path when `curl` is available and otherwise falls back to PowerShell 7. On Windows, the `.cmd` wrapper calls the PowerShell entry point.

### Common examples

```bash
./scripts/smart-web-fetch https://example.com -o article.md
./scripts/smart-web-fetch https://example.com -s jina
./scripts/smart-web-fetch https://example.com -v
./scripts/smart-web-fetch https://example.com --no-clean
```

Windows CMD / native PowerShell:

```cmd
.\scripts\smart-web-fetch https://example.com -o article.md
.\scripts\smart-web-fetch https://example.com -s jina
.\scripts\smart-web-fetch https://example.com -v
.\scripts\smart-web-fetch https://example.com --no-clean
```

## ⚙️ Arguments

| Function | Argument |
| --- | --- |
| Show help | `-h` / `--help` |
| Write output to file | `-o <FILE>` / `--output <FILE>` |
| Force a service | `-s <NAME>` / `--service <NAME>` |
| Enable verbose logs | `-v` / `--verbose` |
| Skip HTML cleanup | `--no-clean` |

Valid values for `-s` / `--service`: `jina`, `markdown`, `defuddle`. Unknown arguments exit with an error.

## 🔄 Fetch Strategy

By default, services are tried in order. The next provider is only attempted if the previous one fails. If all providers fail, the command exits with a non-zero status and reports the last failure reason. When a service is explicitly selected with `-s` / `--service`, only that service is attempted.

| # | Service | Method | Endpoint |
| :---: | --- | :---: | --- |
| 1 | Jina Reader | GET | `r.jina.ai/<URL>` |
| 2 | markdown.new | POST | `api.markdown.new/api/v1/convert` |
| 3 | defuddle.md | POST | `defuddle.md/api/convert` |
| 4 | basic fallback | GET | Original URL with local HTML cleanup |

See [`spec/fetch-contract.md`](./spec/fetch-contract.md) in the repository for the detailed decision contract.

## 📁 Repository Layout

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
