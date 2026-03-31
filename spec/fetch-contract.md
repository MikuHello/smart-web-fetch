# Smart Web Fetch — 行为契约

本文件是 `smart-web-fetch`（Bash）与 `smart-web-fetch.ps1`（PowerShell）在抓取判定上的统一规范。新增服务源或调整判定规则时，应先更新本文件，再同步修改两个脚本。

## 1. 规则来源

阈值与错误关键词集中管理于 `skills/smart-web-fetch/assets/fetch-rules.json`。两个脚本优先加载此文件；文件缺失或解析失败时回退到脚本内置默认值。

## 2. 服务源与降级顺序

| # | 服务源 | 方式 | 端点 |
| :---: | --- | :---: | --- |
| 1 | `jina` | GET | `r.jina.ai/<URL>` |
| 2 | `markdown` | POST | `api.markdown.new/api/v1/convert` |
| 3 | `defuddle` | POST | `defuddle.md/api/convert` |
| 4 | `basic fallback` | GET | 原始 URL，本地 HTML 清洗 |

显式指定服务源（`-s` / `-Service`）时，仅尝试该源；失败直接报错，不继续降级。

## 3. URL 归一化

输入若不带 `http://` 或 `https://`（大小写不敏感），统一自动补 `https://`。

## 4. 成功判定

### 通用条件（所有服务源）

- HTTP 状态码为 `2xx`
- 响应非空，且长度达到对应阈值

### 最小长度阈值

| 服务源 | 阈值（字符） |
| --- | :---: |
| Jina | 100 |
| markdown.new | 40 |
| defuddle.md | 40 |
| basic fallback | 40 |

### markdown.new / defuddle 额外条件

- 若响应可识别为 JSON，必须能提取到 `markdown` / `content` / `data` 字段之一，否则判定失败

## 5. 失败判定

### 结构化错误（JSON 响应）

满足以下任一条件即判失败：

- `error` 字段为 `true`
- `error` 或 `message` 字段包含关键词：`error` / `fail` / `invalid` / `unauthorized` / `forbidden` / `denied` / `blocked` / `not found` / `rate limit` / `too many requests`

### HTML 错误页（markdown.new / defuddle）

`Content-Type` 为 HTML，且内容含 `<html` / `<title`，且命中关键词：`access denied` / `captcha` / `bad gateway` / `cloudflare` / `just a moment` / `unauthorized` / `gateway timeout` / `service unavailable`

## 6. Basic fallback 阶段校验

按顺序逐阶段检查，每阶段均须非空且达到最小阈值：

1. 原始 HTML 拉取后
2. HTML 清洗后（若启用）
3. HTML 转文本后（若转换器可用）

`perl` 不可用时，Bash 路径仍须执行轻量块级清洗（`script` / `style` / `noscript` / `nav` / `header` / `footer` / `aside` 及注释）与属性清洗（`class` / `id` / `style` / `on*`）。

## 7. 可选依赖策略

| 依赖类型 | 缺失时的行为 |
| --- | --- |
| 必需依赖（`curl` / PowerShell 7） | 启动即失败并退出 |
| 可选依赖（`jq` / `perl` / `html2text` / `lynx`） | verbose 模式下提示，继续执行并走降级路径 |

## 8. 离线回归样例

样例数据位于 `spec/fixtures/`，用于在无网络环境下验证行为变更。

| Fixture | 预期结果 | 对应规则 |
| --- | --- | --- |
| `fixtures/markdown-success.json` | ✅ 通过 — 正常 JSON 响应，含 `markdown` 字段，长度达标 | §4 成功判定；Bash 无 `jq` 时亦须通过内置解析 |
| `fixtures/structured-error.json` | ❌ 失败 — `{"error":true,"message":"forbidden"}` | §5 结构化错误 |
| `fixtures/html-error-page.html` | ❌ 失败 — JSON 预期服务源收到 HTML 错误页 | §5 HTML 错误页 |
| `fixtures/too-short.txt` | ❌ 失败 — 内容仅 `"short"`，低于最小阈值 | §4 最小长度阈值 |

### 回归流程

1. 调整阈值或关键词时，先更新 `skills/smart-web-fetch/assets/fetch-rules.json`
2. 对照本文件检查两个脚本的行为一致性
3. 合并前确认上述 fixture 的预期结果仍然成立，且 Bash 在无 `jq` 时仍能从规则文件加载阈值与关键词
4. 手工验证 `defuddle` 在 JSON 成功响应时会提取 `markdown` / `content` / `data` 字段正文，而不是输出原始 JSON
5. 手工验证 `defuddle` 在 JSON 响应缺少上述字段时会判定失败，并保留最后一次失败原因供后续降级/报错使用

## 9. 实现同步要求

- `README.md` 的行为描述应与本契约一致
- 两个脚本的阈值常量命名应保持一一对应，避免漂移
- 自动降级全部失败时，错误信息应包含最后一次失败原因，便于定位问题
