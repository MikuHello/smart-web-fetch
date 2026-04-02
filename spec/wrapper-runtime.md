# 包装器运行时说明

本文档只面向维护者，记录 `smart-web-fetch` 三个入口包装器的运行时发现逻辑、职责边界与测试基线。

## 1. 总体结构

- `skills/smart-web-fetch/main.py` 是唯一受支持的 Python bootstrap 文件。
- `skills/smart-web-fetch/core/` 是内部实现包。
- `smart-web-fetch`、`smart-web-fetch.ps1`、`smart-web-fetch.cmd` 都是薄启动器。
- `scripts/` 目录只保留平台入口，不再承载业务实现。
- 包装器的目标只有两件事：
  - 找到可用的 Python 入口
  - 将原始 CLI 参数原样转发给确定文件入口 `main.py`

## 2. 入口文件定位

| 入口 | 目标环境 | Python 启动目标 |
| --- | --- | --- |
| `scripts/smart-web-fetch` | Bash / Git Bash / WSL / 类 Unix Shell | 技能根目录 `main.py` |
| `scripts/smart-web-fetch.ps1` | PowerShell | 技能根目录 `main.py` |
| `scripts/smart-web-fetch.cmd` | Windows CMD / 原生 PowerShell | 技能根目录 `main.py` |

禁止再引入额外的 shell core、PowerShell core 或重复实现的第二套主逻辑。

## 3. Bootstrap 发现方式

- 三个包装器都通过定位技能根目录 `skills/smart-web-fetch/`，直接执行该目录下的 `main.py`。
- 包装器不得通过设置 `PYTHONPATH` 或切换当前工作目录来发现 `core/`，以免破坏用户相对路径语义（如 `--output relative/path.md`）。
- `main.py` 负责在任意调用方 `cwd` 下优先解析同级 `core/` 包，并将控制权交给 `core.cli:main`。

## 4. 解释器发现顺序

### 4.1 Bash 包装器

文件：`skills/smart-web-fetch/scripts/smart-web-fetch`

发现顺序：

1. `python3`
2. `python`

判定规则：

- 每个候选命令都必须同时满足：
  - `command -v <candidate>` 可执行
  - `<candidate> -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'` 返回成功
- 找到后使用：
  - `exec "$PYTHON_BIN" "$SKILL_DIR/main.py" "$@"`

失败行为：

- 若两个候选都不满足，向 stderr 输出统一错误：
  - `smart-web-fetch: error: Python 3.11+ was not found. Install Python 3.11 or newer and ensure a compatible interpreter is on PATH.`
- 退出码为 `1`

### 4.2 PowerShell 包装器

文件：`skills/smart-web-fetch/scripts/smart-web-fetch.ps1`

发现顺序：

1. `py` 管理的任意 `>= 3.11` 解释器
2. `python`

判定规则：

- 第一优先级是：
  - 先执行 `py -0p`
  - 解析其中所有 `-V:<major>.<minor>` 项
  - 只保留版本 `>= 3.11` 的候选
  - 选择其中最高的 `major.minor`
  - 命中后使用 `py -<major>.<minor> <skill-dir>\main.py @args`
- 若未命中任何 `>= 3.11` 的 `py` 解释器，再尝试 `python`
  - 通过 `python -c <VersionCheck>` 校验版本是否 `>= 3.11`
  - 校验成功后执行 `python <skill-dir>\main.py @args`

失败行为：

- 两条路径都不可用时，向 stderr 输出统一错误消息
- 退出码为 `1`
- 若已成功启动 Python core，则包装器退出码必须回传 `$LASTEXITCODE`

### 4.3 CMD 包装器

文件：`skills/smart-web-fetch/scripts/smart-web-fetch.cmd`

发现顺序：

1. `py` 管理的任意 `>= 3.11` 解释器
2. `python`

判定规则：

- 若 `where py` 成功：
  - 执行 `py -0p`
  - 提取所有 `-V:<major>.<minor>` 候选
  - 只保留版本 `>= 3.11`
  - 选择其中最高的 `major.minor`
  - 命中时执行 `py -<major>.<minor> "%SKILL_DIR%\main.py" %*`
- 若未命中任何 `>= 3.11` 的 `py` 解释器，再尝试 `where python`
  - 只检查命令是否存在
  - 当前 CMD 包装器不会在启动前自行校验 `python` 的版本
  - 版本下限由 `main.py` 在导入 `core.cli` 之前兜底

失败行为：

- `py -3.11` 与 `python` 都不可用时，向 stderr 输出统一错误消息
- 退出码为 `1`
- 成功启动 Python core 后，包装器退出码必须回传 `%errorlevel%`

## 5. 包装器边界

包装器禁止承担以下职责：

- 不重复实现 URL 归一化
- 不重复实现服务降级顺序
- 不重复实现规则文件加载
- 不重复实现 JSON 成功/失败输出拼装
- 不重复实现错误关键词判定
- 不重复实现 HTML 清洗或正文提取

这些逻辑只能存在于 `core/` 包内。

## 6. 参数转发原则

- 包装器不解析业务参数，不重写参数，不添加默认参数。
- Bash 包装器使用 `"$@"` 原样转发。
- PowerShell 包装器使用脚本原始 `@args` 原样转发。
- CMD 包装器使用 `%*` 原样转发。
- `-h/--help`、`--json`、`-o/--output`、`-s/--service`、`-v/--verbose`、`--no-clean` 的语义全部由 `main.py` 引导后的 Python core 决定。

## 7. Python core 边界

`skills/smart-web-fetch/main.py` 负责：

- Python 3.11+ 下限兜底校验
- 保障从任意调用方 `cwd` 执行时优先导入同级 `core/`
- 将控制权移交给 `core.cli:main`

`skills/smart-web-fetch/core/` 负责：

- CLI 参数解析
- 规则文件加载与默认值回退
- 各服务源请求与降级
- JSON / 文本输出
- 文件写入
- 非零退出码与错误信息

因此，包装器维护不应修改抓取契约；抓取行为变更应先更新 `spec/fetch-contract.md`。

## 8. 退出码要求

- 包装器自身找不到可用解释器时，必须返回 `1`
- Python core 正常完成时，包装器必须回传 `0`
- Python core 报错时，包装器必须回传 Python 进程的非零退出码
- `--json` 模式失败时，仍然必须保留非零退出码，不得因为返回了 JSON 而吞掉失败状态

## 9. 与测试的对应关系

### 9.1 离线回归

文件：`spec/tests/offline-regression.sh`

当前覆盖：

- `spec/fetch-contract.md`、规则文件、`main.py`、Python core 包、fixture 是否存在
- 已移除旧的 shell / PowerShell core 文件
- Bash 包装器语法检查
- Python core 包导入、语法检查与部分内置函数行为校验
- 仓库内不应再残留旧的模块名启动 contract 引用

说明：

- 该测试不直接验证 PowerShell / CMD 入口的运行时发现逻辑
- 其目标是保证核心文件结构与基础契约未漂移

### 9.2 Bash JSON smoke

文件：`spec/tests/json-smoke.sh`

当前覆盖：

- `scripts/smart-web-fetch --help`
- Bash 包装器能成功启动 `main.py`
- `--json` 成功/失败输出与退出码
- 自动降级到 `markdown`、`defuddle`、`basic`
- 显式指定 `-s jina`
- 调用方工作目录存在假 `core.py` 时，仍应进入真实 CLI

### 9.3 PowerShell / CMD JSON smoke

文件：`spec/tests/json-smoke.ps1`

当前覆盖：

- `scripts/smart-web-fetch.ps1 --help`
- `scripts/smart-web-fetch.cmd --help`
- PowerShell 入口 `--json` 成功/失败输出与退出码
- CMD 入口 `--json` 成功路径
- `--output` 与 JSON 输出落盘
- Windows `py` launcher 回退
- 调用方工作目录存在假 `core.py` 时，PowerShell / CMD 入口仍应进入真实 CLI

### 9.4 CI 维护基线

包装器调整后，至少要保证：

- 离线回归仍通过
- Bash JSON smoke 仍通过
- PowerShell JSON smoke 仍通过
- CMD 入口 smoke 仍通过

如果运行时发现顺序、错误消息或入口文件命名发生变化，应同步更新对应 smoke test 与本文件。

## 10. 维护约束

- 不要在 README 中展开解释器发现顺序或包装器内部职责
- 不要把测试矩阵说明重新塞回 `README.md` / `README_EN.md`
- 包装器新增行为前，先判断该逻辑是否应该下沉到 Python core
- 若包装器实现与本文档不一致，应以代码为准修正文档，或在同一变更中一起修正两者
