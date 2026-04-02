---
name: smart-web-fetch
description: Fetch web pages and article-like URLs as clean Markdown with automatic fallback across Jina Reader, markdown.new, defuddle.md, and a direct fetch path. Use when an agent needs to read a URL, extract main content, reduce HTML noise, save fetched output, or convert webpage content into token-efficient text.
compatibility: Requires network access and Python 3.11+.
---

# Smart Web Fetch

Use the bundled scripts to retrieve a URL as clean Markdown/text or as structured JSON for scripts and agents.

## When To Use

- The task requires reading a webpage, article, or documentation page as Markdown.
- The user wants webpage content saved to a file for later reuse.
- You need a fallback sequence instead of relying on a single service.

## Run

This skill is intended to be distributed as a standalone `smart-web-fetch/` directory or zip. The commands below assume you are running from inside that extracted directory.

### Bash / Unix-like systems

```bash
./scripts/smart-web-fetch <URL>
```

### Windows CMD / 原生 PowerShell

```cmd
.\scripts\smart-web-fetch <URL>
```

### PowerShell 7（显式调用）

```powershell
pwsh -File .\scripts\smart-web-fetch.ps1 <URL>
```

## Preferred options

- Use `-s jina` when you want the most stable cleaned result.
- Use `--json` when another tool or agent should consume structured output.
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

The clean-skip flag only changes the basic fallback path. External service output is passed through unchanged.

URLs without a scheme are normalized to `https://`, but non-HTTP(S) schemes fail fast. The basic fallback rejects binary responses instead of returning garbled text.

Default mode prints only the fetched body. `--json` prints a single JSON object with `success`, `url`, `content`, and `source`; failures also include `error` and still exit non-zero. `source` resolves to the actual winning backend: `jina`, `markdown`, `defuddle`, `basic`, or `none`.

## Requirements

- Python 3.11+
- No third-party runtime dependency; the bundled `core/` package only relies on Python standard-library modules
- `core/` is internal only; the shipped wrappers execute the skill-root `main.py` bootstrap and keep the public command surface unchanged

## Notes

- `-o <file>` writes the final output for the current mode, including JSON mode.
- `--no-clean` only affects the direct/basic fallback path.
- Unknown arguments or fetch failures exit non-zero.
