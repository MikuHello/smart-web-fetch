---
name: smart-web-fetch
description: Fetch web pages and article-like URLs as clean Markdown with automatic fallback across Jina Reader, markdown.new, defuddle.md, and a direct curl fallback. Use when Codex or another agent needs to read a URL, extract the main content, reduce HTML noise, save fetched content to a file, or turn webpage content into token-efficient text.
---

# Smart Web Fetch

Use the bundled CLI to retrieve a URL.

## Run

### Bash / ? Unix ??

```bash
./smart-web-fetch <URL>
```

If the script is already on `PATH`, run:

```bash
smart-web-fetch <URL>
```

### Windows / PowerShell 7

```powershell
./smart-web-fetch.ps1 <URL>
```

## Preferred options

- Use `-s jina` or `-Service jina` when you want the most stable cleaned result.
- Use `-o <file>` or `-Output <file>` when the fetched content should be reused later.
- Use `-v` or `-VerboseMode` when debugging a failed fetch.
- Use `--no-clean` or `-NoClean` only if you want the basic fallback to keep rawer HTML.

## Behavior

The tool tries providers in this order unless a service is forced:

1. `jina`
2. `markdown`
3. `defuddle`
4. direct `curl` fallback

The clean-skip flag only changes the basic fallback path. External provider output is passed through unchanged.

## Requirements

- Require `curl`
- Prefer `jq` for JSON parsing
- Prefer `html2text` or `lynx` for fallback HTML conversion
- Prefer `perl` for stronger fallback HTML cleanup when available
