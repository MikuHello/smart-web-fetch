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
```

### Dependencies

- The only runtime baseline is `Python 3.11+`
- Only Python standard-library modules are required at runtime
- `core/` is the internal implementation package; the public wrappers execute the deterministic `main.py` bootstrap in the skill root, which then dispatch to `core.cli:main`
- Runtime does not require `curl`, `pwsh`, `jq`, `perl`, `html2text`, or `lynx`

### Common install commands

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

## 🚀 Quick Start

All terminals use the same command name and argument interface. The examples below assume you are running from the release-package root or the downloaded `skills/smart-web-fetch/` directory.

| Terminal Environment | Invocation |
| --- | --- |
| Linux / macOS / WSL / Git Bash | `./scripts/smart-web-fetch <URL>` |
| Windows CMD / native PowerShell | `.\scripts\smart-web-fetch <URL>` |
| PowerShell 7 (explicit invocation) | `pwsh -File .\scripts\smart-web-fetch.ps1 <URL>` |

### Common usage patterns

Read the page body directly:

```bash
./scripts/smart-web-fetch https://example.com
```

Save the result to a file:

```bash
./scripts/smart-web-fetch https://example.com -o article.md
```

Return structured JSON:

```bash
./scripts/smart-web-fetch https://example.com --json
```

Force a provider or debug the fetch:

```bash
./scripts/smart-web-fetch https://example.com -s jina
./scripts/smart-web-fetch https://example.com -v
./scripts/smart-web-fetch https://example.com --no-clean
```

Windows CMD / native PowerShell examples:

```cmd
.\scripts\smart-web-fetch https://example.com
.\scripts\smart-web-fetch https://example.com -o article.md
.\scripts\smart-web-fetch https://example.com --json
.\scripts\smart-web-fetch https://example.com -s jina
.\scripts\smart-web-fetch https://example.com -v
.\scripts\smart-web-fetch https://example.com --no-clean
```

## ⚙️ Arguments

| Argument | Purpose | Notes |
| --- | --- | --- |
| `-h`, `--help` | Show help | Prints help and exits |
| `-o <FILE>`, `--output <FILE>` | Write to an output file | Writes body text by default; writes structured output when combined with `--json` |
| `-s <NAME>`, `--service <NAME>` | Force a specific service | Valid values: `jina`, `markdown`, `defuddle` |
| `--json` | Return structured output | Useful for scripts, automation, and agents |
| `-v`, `--verbose` | Enable verbose logs | Logs go to stderr |
| `--no-clean` | Skip HTML cleanup in the basic fallback | Only affects the direct/basic fallback path |

## 🧾 Output Modes

By default, the command prints the fetched body content directly, which is convenient for terminal use or shell redirection.

If the result should be consumed by scripts, automation, or agents, add `--json`. In that mode the CLI returns structured output, for example:

```json
{"success":true,"url":"https://example.com","content":"...","source":"jina"}
```

In `--json` mode, failures also return JSON and include error details. `source` reflects the backend that actually produced the result. `--json` can also be combined with `-o` / `--output`, in which case the output file receives the final payload for the active mode.

## 🔄 Fetch Strategy

By default, services are tried in order. The next provider is only attempted if the previous one fails. If all providers fail, the command exits with a non-zero status and reports the last failure reason. When a service is explicitly selected with `-s` / `--service`, only that service is attempted.

| Priority | Service | Method | Endpoint |
| :---: | --- | :---: | --- |
| 1 | Jina Reader | GET | `r.jina.ai/<URL>` |
| 2 | markdown.new | POST | `api.markdown.new/api/v1/convert` |
| 3 | defuddle.md | POST | `defuddle.md/api/convert` |
| 4 | basic fallback | GET | Original URL with local HTML cleanup |

See [`spec/fetch-contract.md`](./spec/fetch-contract.md) in the repository for the detailed decision contract.

Additional notes:

- URLs without a scheme are normalized to `https://`
- Only `http://` and `https://` are allowed; schemes such as `ftp://` fail fast
- The basic fallback rejects binary responses such as images, PDFs, and archive payloads instead of returning garbled text

## License

MIT
