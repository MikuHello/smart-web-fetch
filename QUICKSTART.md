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

## 指定服务

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

## 跳过 fallback HTML 清洗

```bash
./smart-web-fetch https://example.com --no-clean
```

```powershell
./smart-web-fetch.ps1 https://example.com -NoClean
```

## 推荐集成方式

- Codex 风格系统：加载 `SKILL.md`
- Claude 风格系统：注册 `skill.json`
- 其他智能体：直接调用 `smart-web-fetch` 或 `smart-web-fetch.ps1`
