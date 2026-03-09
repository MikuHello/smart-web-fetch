# Smart Web Fetch - Agent Edition

轻量级网页抓取 Skill / CLI，可供不同智能体系统复用。

> 项目Fork自`Kim-Huang-JunKai/smart-web-fetch`  
> **借鉴来源：** 本工具功能设计借鉴自 clawhub.ai/Leochens/smart-web-fetch，感谢原作者的创意和实现思路。

它会抓取指定 URL，并优先输出更干净的 Markdown 内容，默认按以下顺序自动降级：

1. `Jina Reader`
2. `markdown.new`
3. `defuddle.md`
4. 直接 `curl` 抓取

项目刻意保持小而简单，方便在不同环境中复用：

- `SKILL.md`：适用于 Codex 风格的 Skill 系统
- `skill.json`：适用于 Claude 风格的 Skill 注册方式
- `smart-web-fetch`：适用于普通智能体、脚本或自动化流程直接调用
- `smart-web-fetch.ps1`：适用于 Windows / `pwsh 7` 的原生 PowerShell 用法

## 功能特性

- 优先输出 Markdown，减少噪音与 Token 消耗
- 内置多服务自动降级策略
- 支持保存到文件
- 支持详细日志输出
- 基础 `curl` fallback 支持 HTML 清洗

## 依赖

- `curl`：必需
- `jq`：可选，用于从 JSON 响应中提取 Markdown 字段
- `html2text` 或 `lynx`：可选，用于将 fallback 的 HTML 转为文本
- `perl`：可选，用于在 fallback 模式下进行更完整的 HTML 清洗

### 常见安装命令

以下命令只是为了方便安装，保留上面的依赖说明不变。

#### macOS（Homebrew）

```bash
brew install curl jq html2text lynx perl
```

#### Debian / Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y curl jq html2text lynx perl
```

#### Fedora / RHEL / CentOS Stream

```bash
sudo dnf install -y curl jq html2text lynx perl
```

#### Arch Linux

```bash
sudo pacman -S --needed curl jq html2text lynx perl
```

#### Windows（PowerShell 7 + winget）

```powershell
winget install jqlang.jq
winget install StrawberryPerl.StrawberryPerl
winget install Python.Python.3
py -m pip install html2text
```

如果你只想先满足最低要求，安装 `curl` 即可；其余依赖都是增强项。

## 安装

### 方式一：直接在仓库中运行

```bash
./smart-web-fetch https://example.com
```

### 方式二：加入 `PATH`

```bash
chmod +x smart-web-fetch
cp smart-web-fetch /usr/local/bin/smart-web-fetch
smart-web-fetch https://example.com
```

如果你的环境不使用 `/usr/local/bin`，放到任意已在 `PATH` 中的目录即可。

### Windows 原生用法

```powershell
pwsh -File .\smart-web-fetch.ps1 https://example.com
```

## 使用方法

### Bash / 类 Unix 环境

```bash
smart-web-fetch <URL> [options]
```

### PowerShell 7

```powershell
./smart-web-fetch.ps1 <URL> [-Output FILE] [-Service jina|markdown|defuddle] [-VerboseMode] [-NoClean]
```

### 示例

```bash
smart-web-fetch https://example.com
smart-web-fetch https://example.com -o output.md
smart-web-fetch https://example.com -s jina
smart-web-fetch https://example.com --no-clean
smart-web-fetch https://example.com -v
```

```powershell
./smart-web-fetch.ps1 https://example.com
./smart-web-fetch.ps1 https://example.com -Output output.md
./smart-web-fetch.ps1 https://example.com -Service jina
./smart-web-fetch.ps1 https://example.com -NoClean
./smart-web-fetch.ps1 https://example.com -VerboseMode
```

### 参数说明

| 参数 | 说明 |
| --- | --- |
| `-h`, `--help` | 显示帮助 |
| `-o`, `--output FILE` | 输出到文件 |
| `-s`, `--service NAME` | 指定服务：`jina`、`markdown` 或 `defuddle` |
| `-v`, `--verbose` | 显示详细日志 |
| `--no-clean` | 跳过基础 `curl` fallback 的 HTML 清洗 |

PowerShell 版本对应参数：`-Output`、`-Service`、`-VerboseMode`、`-NoClean`。

## 默认服务顺序

默认自动尝试顺序：

1. `jina`
2. `markdown`
3. `defuddle`
4. 基础 `curl` fallback

## 说明

- `--no-clean` 只影响基础 fallback 路径，不影响外部清洗服务返回的内容。
- 如果没有安装 `html2text` 或 `lynx`，fallback 会直接返回清洗后的原始 HTML。
- 某些网站可能会拦截清洗服务，请求最终会回退到直接 `curl` 抓取。

## License

MIT