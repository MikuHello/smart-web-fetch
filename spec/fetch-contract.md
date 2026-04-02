# Smart Web Fetch — 行为契约

本文件是 `smart-web-fetch` 的统一抓取判定规范。新增服务源或调整判定规则时，应先更新本文件，再同步修改 `core/` Python 包。包装器运行时发现逻辑与 smoke test 维护基线见 `spec/wrapper-runtime.md`；包装器会通过技能根目录下的 `main.py` bootstrap 引导内部 `core/` 包。

## 1. 规则来源

阈值与错误关键词集中管理于 `skills/smart-web-fetch/assets/fetch-rules.json`。由技能根目录 `main.py` 启动的 Python core 优先加载此文件；文件缺失或解析失败时回退到内置默认值。

## 2. 服务源与降级顺序

| # | 服务源 | 方式 | 端点 |
| :---: | --- | :---: | --- |
| 1 | `jina` | GET | `r.jina.ai/<URL>` |
| 2 | `markdown` | POST | `api.markdown.new/api/v1/convert` |
| 3 | `defuddle` | POST | `defuddle.md/api/convert` |
| 4 | `basic fallback` | GET | 原始 URL，本地 HTML 清洗 |

显式指定服务源（`-s` / `--service`）时，仅尝试该源；失败直接报错，不继续降级。

## 3. URL 归一化

输入 URL 按“解析 + 校验”执行：

- 若不带 scheme，自动补 `https://`
- 仅允许 `http://` 与 `https://`
- 其他 scheme（如 `ftp://`）直接判定失败，不进入抓取链路
- URL 缺少 host 时直接判定失败

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

### Basic fallback 二进制响应

满足以下任一条件即判失败：

- `Content-Type` 命中典型二进制媒体类型，如 `image/*`、`audio/*`、`video/*`、`application/octet-stream`、`application/pdf`、压缩包类型
- 类型不明确时，原始字节命中二进制启发式检测（如包含 `NUL` 字节或较高比例不可打印控制字节）

## 6. Basic fallback 阶段校验

按顺序逐阶段检查，每阶段均须非空且达到最小阈值：

1. 原始 HTML 拉取后
   若识别为二进制响应，直接失败
2. HTML 清洗后（若启用）
3. HTML 转文本后（Python 标准库内置转换）

`--no-clean` 时跳过本地 HTML 清洗，直接返回 basic fallback 原始响应正文。

## 7. 可选依赖策略

| 依赖类型 | 缺失时的行为 |
| --- | --- |
| 必需依赖（`Python 3.11+`） | 入口包装器启动即失败并退出 |
| 可选依赖 | 无；运行时仅依赖 Python 标准库 |

## 8. 离线回归样例

样例数据位于 `spec/fixtures/`，用于在无网络环境下验证行为变更。

| Fixture | 预期结果 | 对应规则 |
| --- | --- | --- |
| `fixtures/markdown-success.json` | ✅ 通过 — 正常 JSON 响应，含 `markdown` 字段，长度达标 | §4 成功判定；Python core 须通过内置 JSON 解析 |
| `fixtures/structured-error.json` | ❌ 失败 — `{"error":true,"message":"forbidden"}` | §5 结构化错误 |
| `fixtures/html-error-page.html` | ❌ 失败 — JSON 预期服务源收到 HTML 错误页 | §5 HTML 错误页 |
| `fixtures/too-short.txt` | ❌ 失败 — 内容仅 `"short"`，低于最小阈值 | §4 最小长度阈值 |

### 回归流程

1. 调整阈值或关键词时，先更新 `skills/smart-web-fetch/assets/fetch-rules.json`
2. 先运行离线回归脚本：`./spec/tests/offline-regression.sh`（仅校验夹具、规则文件、Python core 包与入口结构，不依赖外网）
3. 对照本文件检查 Python core 的行为一致性
4. 合并前确认上述 fixture 的预期结果仍然成立，且 Python core 仍能从规则文件加载阈值与关键词
5. 手工验证 `defuddle` 在 JSON 成功响应时会提取 `markdown` / `content` / `data` 字段正文，而不是输出原始 JSON
6. 手工验证 `defuddle` 在 JSON 响应缺少上述字段时会判定失败，并保留最后一次失败原因供后续降级/报错使用

## 9. CLI JSON 输出契约

当传入 `--json` 时，Python core 及其三个入口包装器都必须输出单个 JSON 对象。

成功：

```json
{"success":true,"url":"https://example.com","content":"...","source":"jina"}
```

失败：

```json
{"success":false,"url":"https://example.com","content":"","source":"none","error":"..."}
```

- `content` 必须始终为字符串
- 自动降级成功时，`source` 返回实际命中的来源：`jina`、`markdown`、`defuddle`、`basic`
- 显式指定服务失败时，失败 JSON 中的 `source` 回显指定服务名
- 自动模式全部失败时，失败 JSON 中的 `source` 为 `none`
- `--json` 模式失败时仍需返回非零退出码

## 10. 测试用端点覆盖

仅用于本地/CI smoke test，可通过环境变量覆盖远端服务端点：

- `SMART_WEB_FETCH_JINA_READER_BASE`
- `SMART_WEB_FETCH_MARKDOWN_NEW_URL`
- `SMART_WEB_FETCH_DEFUDDLE_URL`

## 11. 实现同步要求

- `README.md` / `README_EN.md` / `SKILL.md` 的行为描述应与本契约一致
- `core/` 的内置默认值与 `assets/fetch-rules.json` 的字段命名应保持一致，避免漂移
- 自动降级全部失败时，错误信息应包含最后一次失败原因，便于定位问题
- 包装器发现顺序、错误消息与测试对应关系由 `spec/wrapper-runtime.md` 单独维护
