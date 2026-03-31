---
name: smart-web-fetch
description: Fetch web pages and article-like URLs as clean Markdown with automatic fallback across Jina Reader, markdown.new, defuddle.md, and a direct fetch path. Use when an agent needs to read a URL, extract main content, reduce HTML noise, save fetched output, or convert webpage content into token-efficient text.
compatibility: Requires network access. Bash usage requires curl; if curl is absent, the entry point automatically falls back to PowerShell 7 with Invoke-WebRequest.
---

# Smart Web Fetch

Use the bundled scripts to retrieve a URL as clean Markdown or text.

## When To Use

- The task requires reading a webpage, article, or documentation page as Markdown.
- The user wants webpage content saved to a file for later reuse.
- You need a fallback sequence instead of relying on a single service.

## Run

所有终端使用相同的参数接口：

### Bash / Unix-like systems

```bash
./scripts/smart-web-fetch <URL>
```

### Windows CMD / 原生 PowerShell

```cmd
smart-web-fetch <URL>
```

（需将 `scripts/` 目录加入 PATH，或使用完整路径）

### PowerShell 7（显式调用）

```powershell
./scripts/smart-web-fetch.ps1 <URL>
```

## Preferred options

- Use `-s jina` when you want the most stable cleaned result.
- Use `-o <file>` when the fetched content should be reused later.
- Use `-v` when debugging a failed fetch.
- Use `--no-clean` only if you want the basic fallback to keep rawer HTML.

## Behavior

The tool tries services in this order unless one is explicitly forced:

1. `jina`
2. `markdown`
3. `defuddle`
4. direct fallback

When a service is explicitly forced via `-s`/`--service`, the CLI only attempts that service. If it fails, the command exits with an error instead of continuing to other services.

The entry point detects `curl` first; if present it routes to the Bash core. Otherwise it falls back to PowerShell 7. When routing to PowerShell, POSIX-style flags (`--no-clean`, `--verbose`, etc.) are translated automatically.

The clean-skip flag only changes the basic fallback path. External service output is passed through unchanged.

The runtime rules file is `assets/fetch-rules.json`. The scripts load it when present and fall back to built-in defaults if it is missing or cannot be parsed.

## Requirements

- `curl` **or** PowerShell 7 with `Invoke-WebRequest` (at least one required)
- Prefer `jq` for JSON parsing (Bash path)
- Prefer `html2text` or `lynx` for fallback HTML conversion
- Prefer `perl` for stronger fallback HTML cleanup when available

## Files

- `scripts/smart-web-fetch`: 统一入口（Bash / Git Bash）。检测运行时并路由到对应 core。
- `scripts/smart-web-fetch.ps1`: 统一入口（PowerShell 7）。接受 POSIX 风格参数并转发给 core。
- `scripts/smart-web-fetch.cmd`: 统一入口（Windows CMD / 原生 PowerShell）。调用 PS1 包装器。
- `scripts/smart-web-fetch-core`: Bash 核心实现。不直接调用。
- `scripts/smart-web-fetch-core.ps1`: PowerShell 核心实现。不直接调用。
- `assets/fetch-rules.json`: Runtime thresholds and keyword rules.
