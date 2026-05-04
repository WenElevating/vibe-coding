# Claude Code CLI 交互开发指南

> 面向 Agent 开发者，基于官方文档整理，覆盖 CLI 调用、流式协议、权限管理、会话管理、工具控制等核心主题。
>
> 官方文档索引：https://code.claude.com/docs/en/cli-reference
> Agent SDK 文档：https://code.claude.com/docs/en/agent-sdk/overview

---

## 目录

1. [基础调用模式](#1-基础调用模式)
2. [核心 CLI Flag 速查](#2-核心-cli-flag-速查)
3. [能力检测](#3-能力检测)
4. [双向流式协议（stream-json）](#4-双向流式协议stream-json)
5. [权限模式](#5-权限模式)
6. [工具控制](#6-工具控制)
7. [会话管理](#7-会话管理)
8. [系统提示定制](#8-系统提示定制)
9. [进程管理与环境变量](#9-进程管理与环境变量)
10. [错误处理与退出码](#10-错误处理与退出码)
11. [常见陷阱](#11-常见陷阱)

---

## 1. 基础调用模式

Claude Code CLI 有两种核心运行模式，agent 集成时几乎都走**非交互（print）模式**：

### 单次查询（Single Message）

适合无状态场景（CI/CD、Lambda 等）：

```bash
claude -p "你的 prompt" --output-format json
```

局限：不支持图片附件、hooks 回调、实时中断，也不支持原生多轮对话。

### 流式双向（Streaming Input）—— **推荐**

适合长期运行的 agent 进程，支持多轮、工具审批、`AskUserQuestion`、图片等：

```bash
claude \
  --print \
  --output-format stream-json \
  --input-format stream-json \
  --verbose \
  --include-partial-messages \
  --permission-mode default \
  --permission-prompt-tool stdio
```

通过 stdin/stdout 进行 NDJSON 双向通信（每行一个 JSON 对象）。

---

## 2. 核心 CLI Flag 速查

> **重要**：`claude --help` 并不列出所有 flag，某个 flag 不出现在 `--help` 里不代表它不可用。

### 输入输出

| Flag | 可选值 | 说明 |
|---|---|---|
| `--print` / `-p` | — | 非交互模式，用完即退 |
| `--output-format` | `text` / `json` / `stream-json` | 输出格式；`stream-json` 最适合 agent 集成 |
| `--input-format` | `text` / `stream-json` | 输入格式；`stream-json` 开启 stdin 双向通信 |
| `--include-partial-messages` | — | 输出流式增量内容（需配合 `stream-json`） |
| `--verbose` | — | 输出每轮完整内容 |
| `--replay-user-messages` | — | 将 stdin 用户消息回显到 stdout（需双 stream-json） |

### 会话

| Flag | 说明 |
|---|---|
| `--continue` / `-c` | 继续当前目录最近一次会话 |
| `--resume <id或name>` / `-r` | 按 session ID 或名字恢复会话 |
| `--session-id <uuid>` | 指定 UUID 作为会话 ID |
| `--name` / `-n` | 为本次会话设置显示名 |
| `--fork-session` | resume 时创建新 session ID 而非复用原始 ID |
| `--no-session-persistence` | 禁止会话持久化（仅 print 模式） |

### 权限

| Flag | 说明 |
|---|---|
| `--permission-mode <mode>` | 见第5节；**不要用 `--help` 来判断支持哪些值** |
| `--permission-prompt-tool <name>` | 指定 MCP 工具处理权限提示（非交互模式） |
| `--dangerously-skip-permissions` | 等同 `bypassPermissions`，仅用于隔离容器 |
| `--allowedTools` | 预批准工具列表，跳过确认提示 |
| `--disallowedTools` | 从模型上下文中移除工具，使其不可用 |
| `--tools` | 限制可用工具集；`""` 禁用所有工具 |

### 工作区与性能

| Flag | 说明 |
|---|---|
| `--add-dir <path>` | 追加工作目录（可多次使用） |
| `--bare` | 跳过 hooks/skills/MCP/CLAUDE.md 自动发现，加快脚本启动 |
| `--max-turns <n>` | 限制 agent 轮次（仅 print 模式） |
| `--max-budget-usd <n>` | 限制 API 花费上限（仅 print 模式） |
| `--effort <level>` | `low`/`medium`/`high`/`xhigh`/`max`，控制推理深度 |
| `--model <name>` | 指定模型；支持别名 `sonnet`/`opus` |

---

## 3. 能力检测

### 正确姿势：运行时探测，不依赖 `--help`

`claude --help` 不完整，**不能**用它的输出来判断 flag 是否支持。

```javascript
function detectCapabilities(command = 'claude') {
  const version = spawnSync(command, ['--version'], { encoding: 'utf8' });
  if (version.error || version.status !== 0) {
    return { available: false, error: 'claude not found' };
  }
  // 实际检测：直接尝试运行，观察错误而非解析 --help
  return {
    available: true,
    version: version.stdout.trim()
  };
}
```

### 检测 `--permission-mode` 支持的值

`auto` 模式在 npm 包和原生安装器之间存在差异，**必须在运行时通过 `--help` 提取实际枚举值**：

```javascript
function detectPermissionModes(command = 'claude') {
  const help = spawnSync(command, ['--help'], { encoding: 'utf8' });
  const text = `${help.stdout}\n${help.stderr}`;

  // 从 --help 输出里提取 permission-mode 的合法值
  // 不同安装来源枚举不同：npm 包含 auto，原生安装器可能没有
  const match = text.match(/--permission-mode[^:]*:\s*([^\n]+)/);
  const supported = new Set(['default']); // default 始终可用

  if (match) {
    const line = match[1];
    ['auto', 'acceptEdits', 'bypassPermissions', 'plan', 'dontAsk', 'delegate']
      .forEach(m => { if (line.includes(m)) supported.add(m); });
  }
  return supported;
}
```

---

## 4. 双向流式协议（stream-json）

这是 agent 与 Claude Code CLI 进行程序化双向通信的**唯一官方机制**。

### 启动命令

```bash
claude \
  --print \
  --output-format stream-json \
  --input-format stream-json \
  --verbose \
  --include-partial-messages
```

### 通信格式

stdin 和 stdout 均为 NDJSON（每行一个 JSON 对象，`\n` 分隔）。

### stdin → Claude Code（发送消息）

**初始化握手**（启动后首先发送）：

```json
{
  "type": "control_request",
  "request_id": "init_abc123",
  "request": { "subtype": "initialize", "hooks": null }
}
```

**发送用户 prompt**（收到 `control_response` 确认初始化后发送）：

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "请帮我检查 auth.py 中的 bug"
  },
  "parent_tool_use_id": null,
  "session_id": ""
}
```

**响应权限请求**（收到 `control_request` 后回复）：

```json
{
  "type": "control_response",
  "response": {
    "request_id": "req_xyz",
    "subtype": "success",
    "response": {
      "behavior": "allow",
      "updatedInput": { }
    }
  }
}
```

拒绝时：

```json
{
  "type": "control_response",
  "response": {
    "request_id": "req_xyz",
    "subtype": "success",
    "response": {
      "behavior": "deny",
      "message": "用户拒绝了该操作",
      "interrupt": true
    }
  }
}
```

### stdout → 你（接收消息）

| `type` 字段 | 含义 |
|---|---|
| `control_response` | 对你发送的 `control_request` 的确认 |
| `control_request` | Claude Code 请求你的决策（权限或问题） |
| `assistant` | Claude 的文字回复（含增量内容） |
| `result` | 本次运行结束结果（含 `session_id`、`is_error`） |
| `system` | 系统事件（API 重试、状态更新等） |
| `stream_event` | 包装的流式事件，需提取内层 `event` 字段 |

### `control_request` 事件处理

收到时，`raw.request.subtype === 'can_use_tool'` 表示工具审批请求：

```javascript
// 工具审批
if (payload.subtype === 'can_use_tool') {
  const { tool_name, input, tool_use_id, request_id } = payload;

  if (tool_name === 'AskUserQuestion') {
    // 处理 Claude 的澄清性提问（见第6节）
    handleAskUserQuestion(payload, requestId);
    return;
  }

  // 其他工具：交由上层决策
  emitApprovalRequired({ tool_name, input, requestId });
}
```

### 完整通信时序

```
Agent                           Claude Code CLI
  |                                     |
  |-- stdin: control_request(init) ---->|
  |<-- stdout: control_response --------|
  |                                     |
  |-- stdin: user message ------------->|
  |<-- stdout: assistant (delta) -------|  × N
  |<-- stdout: control_request ---------|  (可选：工具审批)
  |-- stdin: control_response --------->|
  |<-- stdout: result ------------------|
  |                                     |
  |-- stdin: EOF (auto模式) ----------->|
```

---

## 5. 权限模式

### 有效枚举值

| 值 | 行为 | 适用场景 |
|---|---|---|
| `default` | 每次工具操作都提示用户 | 交互式开发 |
| `acceptEdits` | 自动批准文件操作，Bash 仍需确认 | 代码编辑场景 |
| `plan` | 只读探索，不执行写操作 | 需求分析、代码阅读 |
| `dontAsk` | 自动拒绝所有未预批准的操作 | 严格 CI 管道 |
| `auto` | 智能分类器自动决策（**仅 npm 包支持**） | 高自动化 agent |
| `bypassPermissions` | 跳过所有检查（**仅隔离容器使用**） | 沙箱 CI |

> **`auto` 的兼容性问题**：原生安装器（`curl install.sh`）上 `--permission-mode auto` 会在解析阶段直接报错，必须先检测支持的值再决定是否使用。

### 推荐写法

```javascript
function buildPermissionArgs(permissionMode, supportedModes) {
  const safeMode = supportedModes.has(permissionMode)
    ? permissionMode
    : 'default'; // 降级兜底

  if (safeMode === 'default') {
    // default 模式：需要 permission-prompt-tool 配合双向流
    return ['--permission-mode', 'default'];
    // 注意：不要同时传 --permission-prompt-tool stdio，
    // 使用 --input-format stream-json 时权限已通过 JSON 流处理
  }

  return ['--permission-mode', safeMode];
}
```

---

## 6. 工具控制

### `--allowedTools` vs `--tools`

这两个 flag 经常被混淆，**含义完全不同**：

| Flag | 作用 |
|---|---|
| `--allowedTools` | 预批准指定工具（跳过确认提示），未列工具仍可用但需提示 |
| `--tools` | 限制工具**可用集合**，未列工具完全不可用 |
| `--disallowedTools` | 从模型上下文中移除工具，优先级高于 `allowedTools` |

```bash
# 只允许读操作，完全移除写/执行能力
claude -p "分析代码" --tools "Read,Glob,Grep"

# 允许全部工具，但 git 操作无需确认
claude -p "修复 bug" --allowedTools "Bash(git status *),Bash(git diff *),Read,Edit"
```

### Bash 工具的 glob 限制

`Bash(pattern)` 语法允许精细控制命令白名单：

```
Bash(git *)          # 允许所有 git 命令
Bash(npm test *)     # 允许 npm test
Bash(git status *)   # 仅允许 git status
```

**注意**：`allowedTools` 在 `bypassPermissions` 模式下无效——该模式批准所有工具，如需限制需用 `--disallowedTools`。

### `AskUserQuestion` 工具

Claude 在需要澄清时调用此工具。如果你用 `--tools` 限制了工具集，必须显式包含它：

```bash
claude -p "..." --tools "Read,Glob,Grep,AskUserQuestion"
```

处理 `AskUserQuestion` 的 `control_request`：

```javascript
// input 结构
{
  questions: [
    {
      question: "你希望如何格式化输出？",
      header: "格式",
      options: [
        { label: "简洁", description: "仅关键信息" },
        { label: "详细", description: "包含完整说明" }
      ],
      multiSelect: false
    }
  ]
}

// 回复结构（允许并附带答案）
{
  behavior: "allow",
  updatedInput: {
    questions: [...],   // 透传原始 questions
    answers: {
      "你希望如何格式化输出？": "简洁"
    }
  }
}
```

多选时用 `", "` 连接多个 label；用户自定义输入直接作为 value 传入。

---

## 7. 会话管理

### 获取 session ID

监听 `result` 类型事件，其中包含 `session_id`：

```javascript
// stdout 流式解析
if (event.type === 'result') {
  const sessionId = event.session_id || event.sessionId;
  // 持久化此 ID 以备后续恢复
}
// 或从 system 初始化事件里提取
if (event.type === 'system' && event.subtype === 'session_start') {
  const sessionId = event.session_id;
}
```

### 恢复会话

```bash
# 按 ID 恢复
claude -p "继续之前的工作" --resume <session_id>

# 继续最近一次会话
claude -p "继续" --continue

# fork：恢复但生成新 ID（探索性场景）
claude -p "尝试另一种方案" --resume <session_id> --fork-session
```

### 禁用持久化（无状态场景）

```bash
claude -p "一次性查询" --no-session-persistence
```

---

## 8. 系统提示定制

**优先使用 append 系列 flag**，避免覆盖 Claude Code 的内置能力：

| Flag | 行为 |
|---|---|
| `--append-system-prompt "..."` | 追加到默认提示末尾（**推荐**） |
| `--append-system-prompt-file ./rules.txt` | 从文件追加 |
| `--system-prompt "..."` | 完全替换默认提示（谨慎使用） |
| `--system-prompt-file ./prompt.txt` | 从文件完全替换 |

> **不要传 `--system-prompt ''`**（空字符串替换）——这会清空 Claude Code 的内置系统提示，导致行为异常。

```bash
# 追加项目规范（推荐）
claude -p "..." --append-system-prompt "所有代码必须有单元测试"

# 完全定制（仅在需要完整控制时）
claude -p "..." --system-prompt-file ./custom-agent-prompt.txt
```

---

## 9. 进程管理与环境变量

### 工作目录处理

```javascript
// 正确：同时通过 cwd 选项和命令参数指定
const child = spawn('sh', ['-c', `cd ${shQuote(workspacePath)} && claude ${args}`], {
  cwd: workspacePath,   // Node.js 进程 cwd
});

// 必须验证路径存在，否则 Windows 上会回落到 C:\
if (!workspacePath || !fs.existsSync(workspacePath)) {
  throw new Error('workspacePath 必须是存在的目录');
}
```

Windows 上还需注意 `cmd.exe` 特殊字符转义（`&`、`()`、`^` 等）。

### 关键环境变量

| 变量 | 作用 |
|---|---|
| `ANTHROPIC_API_KEY` | API 认证 |
| `CLAUDE_CODE_ENTRYPOINT` | 标识启动来源（建议设为 `sdk-js` 或自定义标识） |
| `CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING` | 设为 `1` 启用细粒度工具流 |
| `CLAUDECODE` | Claude Code 自身运行时标识；**不要随意删除** |
| `CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_VERTEX` | 切换 API 提供商 |
| `PWD` | 在 env 中设置确保子进程工作目录正确 |

### stdin 关闭时机

```javascript
// bypassPermissions / auto 模式：发完 prompt 后立即关闭 stdin
if (permissionMode === 'bypassPermissions' || permissionMode === 'auto') {
  child.stdin.end();
}
// default / acceptEdits 模式：保持 stdin 开放以接收 control_response
// 在收到 result 事件后再关闭
```

### 登录 shell 的副作用

Unix 上启动时**不要加 `-l` flag**：

```bash
# 错误：会读取 ~/.profile，可能修改 PATH 等环境
sh -lc "cd /path && claude ..."

# 正确
sh -c "cd /path && claude ..."
```

---

## 10. 错误处理与退出码

| 退出码 | 含义 |
|---|---|
| `0` | 成功 |
| 非 `0` | 失败 |
| signal | 被信号终止（用户取消等） |

### result 事件的 is_error 字段

```javascript
if (event.type === 'result') {
  if (event.is_error || event.subtype === 'error') {
    // 运行失败：显示 event.result 中的错误信息
  } else {
    // 成功：event.result 是最终文字结果
  }
}
```

### API 重试事件

```javascript
// type: "system", subtype: "api_retry"
{
  type: "system",
  subtype: "api_retry",
  error_status: 529,
  error: "overloaded",
  attempt: 1,
  max_retries: 5,
  retry_delay_ms: 30000
}
```

可在 UI 上展示重试状态而无需自己实现重试逻辑。

---

## 11. 常见陷阱

### 陷阱 1：用 `--help` 来判断 flag 支持

`--help` 输出不完整，缺失不代表不支持。能力检测应通过实际运行并捕获错误来完成。

### 陷阱 2：`--permission-mode auto` 在原生安装器上报错

原生安装器的合法值不含 `auto`，必须运行时检测后降级。

### 陷阱 3：`--allowedTools` 以为在限制工具

`--allowedTools` 只是跳过确认提示，工具仍然可用。真正限制工具可用性用 `--tools`。

### 阱 4：`--system-prompt ''` 导致行为异常

空字符串会覆盖内置系统提示。如需追加内容用 `--append-system-prompt`，不需要定制就不传系统提示相关 flag。

### 陷阱 5：auto/bypassPermissions 模式下 stdin 不关闭导致卡死

这两种模式不会发来 `control_request`，prompt 发完后必须调用 `stdin.end()`。

### 陷阱 6：Windows 路径中的特殊字符

`&`、`()`、`^`、`!` 等字符在 `cmd.exe` 中有特殊含义，需要全部转义，不只是转义双引号。

### 陷阱 7：协议泄漏到用户输出

`control_request`、`hookSpecificOutput`、`suppressOutput`、`parent_tool_use_id` 等内部字段不应透出给用户。在渲染文字前检测并过滤以 `{` 开头且含 `"type"` 和 `"message"` 的文本。

---

## 附录：推荐的 Flag 组合

### 最小可用（自动审批）

```bash
claude \
  --print \
  --output-format stream-json \
  --verbose \
  --permission-mode bypassPermissions \  # 仅限隔离环境
  "你的 prompt"
```

### 交互式 Agent（需人工审批）

```bash
claude \
  --print \
  --output-format stream-json \
  --input-format stream-json \
  --verbose \
  --include-partial-messages \
  --permission-mode default
```

### 只读分析

```bash
claude \
  --print \
  --output-format stream-json \
  --verbose \
  --tools "Read,Glob,Grep,AskUserQuestion" \
  --permission-mode dontAsk \
  "分析这个项目的架构"
```

### 恢复历史会话

```bash
claude \
  --print \
  --output-format stream-json \
  --input-format stream-json \
  --verbose \
  --include-partial-messages \
  --resume <session_id> \
  --permission-mode default
```

---

*文档基于 Claude Code CLI 当前版本（2026年5月）整理，如有变动以 https://code.claude.com/docs 为准。*
