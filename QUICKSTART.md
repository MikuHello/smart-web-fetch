# Smart Web Fetch - 快速参考

## 最快开始

### Bash / 类 Unix 环境

```bash
chmod +x smart-web-fetch
./smart-web-fetch https://example.com
```

### PowerShell 7

```powershell
pwsh -File .\smart-web-fetch.ps1 https://example.com
```

## 保存输出到文件

```bash
./smart-web-fetch https://example.com -o article.md
```

```powershell
./smart-web-fetch.ps1 https://example.com -Output article.md
```

## 指定 Provider

```bash
./smart-web-fetch https://example.com -s jina
./smart-web-fetch https://example.com -s markdown
./smart-web-fetch https://example.com -s defuddle
```

```powershell
./smart-web-fetch.ps1 https://example.com -Service jina
./smart-web-fetch.ps1 https://example.com -Service markdown
./smart-web-fetch.ps1 https://example.com -Service defuddle
```

## 显示详细日志

```bash
./smart-web-fetch https://example.com -v
```

```powershell
./smart-web-fetch.ps1 https://example.com -VerboseMode
```

## 跳过基础 fallback 的 HTML 清洗

```bash
./smart-web-fetch https://example.com --no-clean
```

```powershell
./smart-web-fetch.ps1 https://example.com -NoClean
```

## 参数校验说明（PowerShell）

- 仅允许一个 URL 参数。
- 未知参数会直接报错（例如 `-VerbosMode` 这类拼写错误不会被静默忽略）。


## 显示帮助

```bash
./smart-web-fetch -h
./smart-web-fetch --help
```

```powershell
./smart-web-fetch.ps1 -Help
./smart-web-fetch.ps1 -h
./smart-web-fetch.ps1 --help
```

## 平台说明

- Bash / 类 Unix CLI：依赖 `curl`，`jq`、`html2text`、`lynx`、`perl` 都是可选辅助工具。
- PowerShell CLI：依赖 PowerShell 7 和 `Invoke-WebRequest`，`jq`、`perl`、`html2text`、`lynx` 都是可选辅助工具。

## 推荐集成方式

- Codex 风格系统：加载 `SKILL.md`
- Claude 风格系统：注册 `skill.json`
- 其他智能体：直接调用 `smart-web-fetch` 或 `smart-web-fetch.ps1`
