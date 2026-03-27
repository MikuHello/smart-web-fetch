# Smart Web Fetch Contract（Bash / PowerShell 一致性规范）

本文件定义 `smart-web-fetch`（Bash）与 `smart-web-fetch.ps1`（PowerShell）在抓取判定上的统一契约。新增 provider 或调整判定规则时，应先更新本文件，再同步修改两个脚本。

## 1) Provider 与默认顺序

默认自动降级顺序：

1. `jina`
2. `markdown`
3. `defuddle`
4. `basic fallback`

若显式指定 provider（`-s/--service` 或 `-Service`），仅尝试该 provider；失败后直接报错，不继续降级。

## 2) URL 归一化

- 输入若不带 `http://` 或 `https://`，统一自动补 `https://`。

## 3) 成功判定（所有 provider）

### 通用要求

- HTTP 状态码必须是 `2xx`。
- 响应不能为空。
- 响应长度必须达到对应 provider 的最小长度阈值。

### 最小长度阈值

- Jina: `100`
- markdown.new: `40`
- defuddle.md: `40`
- basic fallback: `40`

## 4) 结构化错误判定（JSON）

当响应可被识别为 JSON 时，若存在以下语义应判定为失败：

- `error` 字段为 `true`
- `error` 或 `message` 字段文本包含失败语义（如 `error`、`fail`、`invalid`、`unauthorized`、`forbidden`、`not found`）

## 5) HTML 错误页判定（主要用于 JSON 预期 provider）

对于 `markdown.new` / `defuddle.md`：

- 若 `Content-Type` 指示 HTML（如 `text/html`、`application/xhtml+xml`），且内容具备 HTML 特征（`<html` 或 `<title`），并命中典型错误页关键词（如 `access denied`、`captcha`、`bad gateway` 等），则判定失败。

## 6) Basic fallback 的阶段性校验

basic fallback 需按阶段校验：

1. 原始 HTML 拉取后：非空且达到最小长度。
2. 清洗后（若启用清洗）：非空且达到最小长度。
3. HTML 转文本后（若转换器可用）：非空且达到最小长度。

任一阶段失败均应返回失败并设置可追踪错误信息。

## 7) 可选依赖策略

- 必需依赖缺失：启动即失败并退出。
- 可选依赖缺失：仅在 verbose 下提示，继续执行并走降级路径。

## 8) 文档与实现同步要求

- `README.md` 与 `QUICKSTART.md` 的行为描述应与本契约一致。
- 两个脚本的阈值常量命名应保持一一对应，避免漂移。
