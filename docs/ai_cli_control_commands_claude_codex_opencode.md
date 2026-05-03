# Claude Code / Codex / OpenCode CLI 控制命令整理

> 目标：为「Flutter 局域网手机端控制电脑 AI Coding CLI」应用整理可用的 CLI / Server 控制命令。  
> 设计假设：手机端不直接执行 CLI，不做 PTY/远程终端；手机端只调用 Desktop Daemon；Daemon 再通过 CLI headless/exec/server 模式驱动 Claude Code、Codex、OpenCode。  
> 更新时间：2026-05-01

---

## 1. 总体结论

你的应用最适合使用这三类控制方式：

```text
Flutter App
  -> Desktop Daemon
    -> Claude Code: process + stream-json
    -> Codex: process + JSONL
    -> OpenCode: HTTP server / OpenAPI，或 process + json events fallback
```

不建议把手机做成远程 shell。不要让手机传 raw command / raw cwd / raw CLI args。所有命令参数都应该由 daemon 内部的 adapter profile 生成。

---

## 2. 能力对照表

| 工具 | 推荐控制方式 | 实时输出 | 继续会话 | 取消任务 | Diff/文件变更 | 适合程度 |
|---|---|---|---|---|---|---|
| Claude Code | `claude -p --output-format stream-json` | JSONL | `--continue` / `--resume` | daemon kill 子进程 | 通过事件/文件系统/git diff 归一化 | 很高 |
| Codex | `codex exec --json` | JSONL | `codex exec resume` | daemon kill 子进程 | 通过事件/文件系统/git diff 归一化 | 很高 |
| OpenCode | `opencode serve` HTTP API | SSE / HTTP events | server session API | `POST /session/:id/abort` | `GET /session/:id/diff` | 最高 |
| OpenCode fallback | `opencode run --format json` | json events | `--continue` / `--session` | daemon kill 子进程 | git diff fallback | 中高 |

---

## 3. Desktop Daemon Adapter Contract 建议

所有工具统一实现这个抽象：

```ts
export interface CliTaskAdapter {
  id: "claude" | "codex" | "opencode";

  detect(): Promise<AdapterStatus>;

  startRun(input: {
    runId: string;
    workspacePath: string;
    prompt: string;
    mode: "read_only" | "workspace_write" | "dangerous";
    model?: string;
    sessionId?: string;
  }): AsyncIterable<NormalizedRunEvent>;

  resumeRun?(input: {
    runId: string;
    workspacePath: string;
    prompt: string;
    sessionId: string;
  }): AsyncIterable<NormalizedRunEvent>;

  cancel(runId: string): Promise<void>;
}
```

统一事件：

```ts
type NormalizedRunEvent =
  | { type: "run.started"; runId: string }
  | { type: "assistant.delta"; runId: string; text: string }
  | { type: "assistant.message"; runId: string; text: string }
  | { type: "tool.started"; runId: string; name: string; input?: unknown }
  | { type: "tool.output"; runId: string; stream: "stdout" | "stderr"; text: string }
  | { type: "diff.summary"; runId: string; files: DiffFileSummary[] }
  | { type: "approval.required"; runId: string; approvalId: string; payload: unknown }
  | { type: "adapter.raw_stdout"; runId: string; text: string }
  | { type: "adapter.raw_stderr"; runId: string; text: string }
  | { type: "adapter.parse_error"; runId: string; linePreview: string }
  | { type: "run.completed"; runId: string; exitCode?: number }
  | { type: "run.failed"; runId: string; error: NormalizedError };
```

---

# 4. Claude Code

## 4.1 官方适配判断

Claude Code 适合你的应用，因为它支持：

- `-p` / `--print` 非交互执行
- `--output-format json`
- `--output-format stream-json`
- `--include-partial-messages`
- `--verbose`
- `--continue`
- `--resume`
- `--allowedTools`
- `--permission-mode`
- `--bare`

官方文档说明，`-p` 可以用于程序化运行 Claude Code；`stream-json` 是 newline-delimited JSON，适合实时 UI；`--continue` 和 `--resume` 可继续会话。

---

## 4.2 能力检测命令

### 版本检测

```bash
claude --version
# 或
claude -v
```

### 登录状态检测

```bash
claude auth status
```

建议 daemon 判断：

```text
exit code 0 => 已登录
exit code 1 => 未登录或不可用
```

如果需要人类可读输出：

```bash
claude auth status --text
```

### 检测 stream-json 是否可用

```bash
claude --bare -p "Reply with OK only." \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

Daemon 只需要验证 stdout 是否出现一行或多行 JSON。

---

## 4.3 推荐启动任务命令

### 只读分析任务

```bash
claude --bare -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  --permission-mode dontAsk \
  --allowedTools "Read,Bash(git status *),Bash(git diff *)"
```

适用：

- 解释代码
- 搜索问题
- 生成分析报告
- 看 git diff
- 不希望自动改文件

### 工作区写入任务

```bash
claude --bare -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  --permission-mode acceptEdits \
  --allowedTools "Read,Edit,Bash(git status *),Bash(git diff *),Bash(npm test *),Bash(pnpm test *),Bash(dart test *),Bash(flutter test *)"
```

适用：

- 修 bug
- 写测试
- 修改项目文件
- 跑测试命令

注意：

- 不要默认允许所有 Bash。
- Bash 允许规则尽量限定前缀。
- `acceptEdits` 会让文件编辑更顺滑，但 shell 命令仍应限制。

### 高风险任务

不建议 V1 默认支持。  
如果支持，必须二次确认。

```bash
claude --bare -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  --permission-mode default
```

不要在移动端默认暴露：

```bash
claude --dangerously-skip-permissions
```

---

## 4.4 继续会话

### 继续当前目录最近会话

```bash
claude --bare -p "$PROMPT" \
  --continue \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

### 继续指定 session

```bash
claude --bare -p "$PROMPT" \
  --resume "$CLAUDE_SESSION_ID" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

### 捕获 session id

```bash
claude --bare -p "Start review" --output-format json | jq -r '.session_id'
```

Daemon 需要把 Claude 返回的 `session_id` 存到 `runs.cli_session_id`。

---

## 4.5 结构化结果

### 一次性 JSON 结果

```bash
claude --bare -p "$PROMPT" --output-format json
```

适合：

- 生成摘要
- 返回固定字段
- 非实时任务结果

### JSON Schema 输出

```bash
claude --bare -p "$PROMPT" \
  --output-format json \
  --json-schema "$JSON_SCHEMA"
```

适合：

- 让 Claude 返回结构化诊断
- 生成 fixed shape 的分析结果
- 生成 commit summary JSON

---

## 4.6 实时流式输出

```bash
claude --bare -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

Daemon 解析 stdout JSONL：

```ts
child.stdout.on("data", chunk => jsonlParser.push(chunk));
```

推荐映射：

| Claude event | App event |
|---|---|
| text delta | `assistant.delta` |
| tool use start | `tool.started` |
| tool output | `tool.output` |
| system/init | `run.started` / adapter metadata |
| system/api_retry | `adapter.retrying` |
| final result | `run.completed` |

---

## 4.7 文件/工具权限控制

### 允许工具

```bash
claude --bare -p "$PROMPT" \
  --allowedTools "Read,Edit,Bash(git status *),Bash(git diff *)"
```

### 禁用某些工具

```bash
claude --bare -p "$PROMPT" \
  --disallowedTools "Bash(rm *),Bash(curl *),Bash(wget *)"
```

### 限制可用工具

```bash
claude --bare -p "$PROMPT" \
  --tools "Read,Edit,Bash"
```

### 额外目录

不建议从手机传。  
如果确实需要，必须由 daemon workspace 配置产生：

```bash
claude --bare -p "$PROMPT" --add-dir "../shared-lib"
```

---

## 4.8 取消任务

Claude Code 不需要通过 PTY 取消。你的 daemon 直接管理子进程：

```ts
child.kill("SIGTERM");

setTimeout(() => {
  if (!child.killed) child.kill("SIGKILL");
}, 5000);
```

Windows 下建议用进程树 kill，避免 Bash/测试子进程残留。

---

## 4.9 Claude Code 推荐 Adapter Profile

```json
{
  "adapterId": "claude",
  "invocationMode": "process-jsonl",
  "command": "claude",
  "argsTemplate": [
    "--bare",
    "-p",
    "{{prompt}}",
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--permission-mode",
    "{{permissionMode}}"
  ],
  "cwdPolicy": "workspace-root",
  "stdout": "jsonl",
  "stderr": "text",
  "resume": {
    "supported": true,
    "argsTemplate": [
      "--bare",
      "-p",
      "{{prompt}}",
      "--resume",
      "{{sessionId}}",
      "--output-format",
      "stream-json",
      "--verbose",
      "--include-partial-messages"
    ]
  },
  "dangerousFlagsForbidden": [
    "--dangerously-skip-permissions"
  ]
}
```

---

# 5. Codex CLI

## 5.1 官方适配判断

Codex 适合你的应用，因为它支持：

- `codex exec` 非交互执行
- `--json` 输出 newline-delimited JSON events
- `codex exec resume`
- `--sandbox`
- `--ask-for-approval`
- `--cd`
- `codex login status`
- `codex app-server` WebSocket server

主线建议用：

```text
codex exec --json
```

不要主线使用 TUI。`app-server` 可以作为高级路线，但官方文档标注它主要用于开发和调试，可能变动。

---

## 5.2 能力检测命令

### 版本检测

```bash
codex --version
```

如果不稳定，可 fallback：

```bash
codex --help
```

### 登录状态检测

```bash
codex login status
```

Codex 文档说明该命令在凭据存在时 exit code 为 0，适合自动化检测。

### 检测 JSONL exec

```bash
codex exec --json \
  --sandbox read-only \
  --ask-for-approval never \
  "Reply with OK only."
```

---

## 5.3 推荐启动任务命令

### 只读分析任务

```bash
codex exec --json \
  --cd "$WORKSPACE" \
  --sandbox read-only \
  --ask-for-approval on-request \
  "$PROMPT"
```

适用：

- 解释代码
- 代码审阅
- 查找问题
- 不写文件

### 工作区写入任务

```bash
codex exec --json \
  --cd "$WORKSPACE" \
  --sandbox workspace-write \
  --ask-for-approval on-request \
  "$PROMPT"
```

适用：

- 修改 workspace 内文件
- 跑测试
- 修复失败
- 生成代码

这是你的 App 最推荐的默认模式。

### 非交互自动化模式

谨慎使用：

```bash
codex exec --json \
  --cd "$WORKSPACE" \
  --sandbox workspace-write \
  --ask-for-approval never \
  "$PROMPT"
```

只适合：

- synthetic adapter 测试
- 低风险命令
- CI-like 环境
- 已有额外 sandbox 的 isolated runner

### 明确禁止

不要从手机或默认配置传：

```bash
codex exec --dangerously-bypass-approvals-and-sandbox "$PROMPT"
codex exec --yolo "$PROMPT"
codex exec --sandbox danger-full-access "$PROMPT"
```

---

## 5.4 继续会话

### 继续指定 session

```bash
codex exec resume "$CODEX_SESSION_ID" \
  --json \
  "$PROMPT"
```

### 继续当前工作目录最近 session

```bash
codex exec resume --last \
  --json \
  "$PROMPT"
```

### 跨目录搜索最近 session

不建议默认使用：

```bash
codex exec resume --last --all \
  --json \
  "$PROMPT"
```

你的 app 应保持 workspace 边界，不要默认跨工作区找 session。

---

## 5.5 输出结果

### JSONL 实时事件

```bash
codex exec --json "$PROMPT"
```

Daemon 处理：

```ts
parseJsonl(child.stdout, (event) => {
  publish(normalizeCodexEvent(event));
});
```

### 保存最终消息

```bash
codex exec --json \
  --output-last-message "$OUTPUT_FILE" \
  "$PROMPT"
```

适合：

- 生成 release note
- 生成 commit summary
- 保存最终报告

### 结构化最终输出

```bash
codex exec --json \
  --output-schema ./schema.json \
  "$PROMPT"
```

适合：

- 诊断报告
- fixed JSON summary
- 任务结果校验

---

## 5.6 图片输入

如果后续做截图/报错图上传到 desktop daemon，可以用：

```bash
codex exec --json \
  --image "$IMAGE_PATH" \
  "$PROMPT"
```

不建议手机直接传本地路径。手机上传附件后，由 daemon 存入临时文件，再传给 Codex。

---

## 5.7 app-server 可选路线

### 启动 app-server

```bash
codex app-server --listen ws://127.0.0.1:7071
```

### 带 capability token

```bash
codex app-server \
  --listen ws://127.0.0.1:7071 \
  --ws-auth capability-token \
  --ws-token-file "$TOKEN_FILE"
```

### 带 signed bearer token

```bash
codex app-server \
  --listen ws://127.0.0.1:7071 \
  --ws-auth signed-bearer-token \
  --ws-shared-secret-file "$SECRET_FILE" \
  --ws-issuer "your-daemon" \
  --ws-audience "codex-mobile"
```

建议：

- V1 不依赖 app-server。
- V2 可做高级集成。
- 不要直接让 Flutter 连 Codex app-server。
- 仍然由 daemon 代理认证和事件转换。

---

## 5.8 取消任务

主线 process 模式：

```ts
child.kill("SIGTERM");
```

必要时 kill 进程树。

app-server 模式则应通过对应协议取消，但 V1/V1.2 主线不建议依赖它。

---

## 5.9 Codex 推荐 Adapter Profile

```json
{
  "adapterId": "codex",
  "invocationMode": "process-jsonl",
  "command": "codex",
  "argsTemplate": [
    "exec",
    "--json",
    "--cd",
    "{{workspacePath}}",
    "--sandbox",
    "{{sandbox}}",
    "--ask-for-approval",
    "{{approvalMode}}",
    "{{prompt}}"
  ],
  "modeMapping": {
    "read_only": {
      "sandbox": "read-only",
      "approvalMode": "on-request"
    },
    "workspace_write": {
      "sandbox": "workspace-write",
      "approvalMode": "on-request"
    },
    "dangerous": {
      "disabledByDefault": true
    }
  },
  "stdout": "jsonl",
  "stderr": "text",
  "resume": {
    "supported": true,
    "argsTemplate": [
      "exec",
      "resume",
      "{{sessionId}}",
      "--json",
      "--cd",
      "{{workspacePath}}",
      "{{prompt}}"
    ]
  },
  "dangerousFlagsForbidden": [
    "--dangerously-bypass-approvals-and-sandbox",
    "--yolo"
  ]
}
```

---

# 6. OpenCode

## 6.1 官方适配判断

OpenCode 有两条路线：

1. `opencode serve`：headless HTTP server，暴露 OpenAPI endpoint，最适合你的 App。
2. `opencode run --format json`：非交互 process 模式，适合作为 fallback。

优先级：

```text
首选：daemon -> opencode serve HTTP API
备选：daemon -> opencode run --format json
```

不要让 Flutter 直接连 OpenCode server。应始终：

```text
Flutter -> Your Daemon -> OpenCode Server
```

---

## 6.2 能力检测命令

### 版本检测

```bash
opencode --version
```

如果不可用：

```bash
opencode --help
```

### Provider 登录状态

```bash
opencode auth list
# 或
opencode auth ls
```

### 模型列表

```bash
opencode models
opencode models anthropic
opencode models --refresh
```

---

## 6.3 Server 模式

### 启动本地 server

```bash
opencode serve
```

默认：

```text
host: 127.0.0.1
port: 4096
```

### 指定端口和 host

```bash
opencode serve --hostname 127.0.0.1 --port 4096
```

### 允许局域网监听

谨慎使用：

```bash
opencode serve --hostname 0.0.0.0 --port 4096
```

你的 App 更推荐：

```text
OpenCode server 只监听 127.0.0.1
你的 daemon 监听 LAN
Flutter 只连你的 daemon
```

### 开启 mDNS

```bash
opencode serve --hostname 0.0.0.0 --port 4096 --mdns
```

如果直接暴露 LAN，必须配 basic auth。但仍不建议 Flutter 直连。

### CORS

```bash
opencode serve \
  --port 4096 \
  --cors http://localhost:5173 \
  --cors https://app.example.com
```

移动端 App 不应依赖 CORS，因为 daemon 不是浏览器。

---

## 6.4 Server basic auth

### 默认用户名 opencode

```bash
OPENCODE_SERVER_PASSWORD="strong-password" opencode serve
```

### 自定义用户名

```bash
OPENCODE_SERVER_USERNAME="daemon" \
OPENCODE_SERVER_PASSWORD="strong-password" \
opencode serve --hostname 127.0.0.1 --port 4096
```

注意：

- 密码只存 daemon 本地。
- 不发送给 Flutter。
- 不写日志。
- 不放入 diagnostic bundle。

---

## 6.5 OpenCode HTTP API 关键接口

OpenCode server 暴露 OpenAPI 3.1 spec：

```text
http://localhost:4096/doc
```

### 健康检查

```http
GET /global/health
```

### 事件流

```http
GET /global/event
```

这是 SSE stream，可用于 daemon 订阅 OpenCode 全局事件。

### 项目/VCS

```http
GET /project
GET /project/current
GET /path
GET /vcs
```

### Session

```http
GET    /session
POST   /session
GET    /session/status
GET    /session/:id
DELETE /session/:id
PATCH  /session/:id
GET    /session/:id/children
GET    /session/:id/todo
POST   /session/:id/abort
GET    /session/:id/diff
POST   /session/:id/revert
POST   /session/:id/unrevert
POST   /session/:id/permissions/:permissionID
```

这些接口对应你的 App 需求：

| App 需求 | OpenCode API |
|---|---|
| 创建任务 | `POST /session` + `POST /session/:id/message` 或 `prompt_async` |
| 会话列表 | `GET /session` |
| 会话状态 | `GET /session/status` |
| 取消任务 | `POST /session/:id/abort` |
| 查看 diff | `GET /session/:id/diff` |
| 权限响应 | `POST /session/:id/permissions/:permissionID` |
| revert | `POST /session/:id/revert` |
| todo | `GET /session/:id/todo` |

### Message

```http
GET  /session/:id/message
POST /session/:id/message
GET  /session/:id/message/:messageID
POST /session/:id/prompt_async
```

建议：

- 移动端发起任务时，daemon 创建 session 后走 `prompt_async`。
- `GET /global/event` 或 session status 用于推送状态。
- 结果通过 daemon normalize 成统一 run event。

---

## 6.6 OpenCode process fallback

### 非交互运行

```bash
opencode run "$PROMPT"
```

### JSON events

```bash
opencode run --format json "$PROMPT"
```

### 连接已有 server 运行

```bash
opencode run --attach http://localhost:4096 "$PROMPT"
```

### 指定模型

```bash
opencode run --model anthropic/claude-sonnet-4-5 "$PROMPT"
```

### 指定 agent

```bash
opencode run --agent build "$PROMPT"
```

### 附件文件

```bash
opencode run --file ./lib/main.dart "$PROMPT"
```

### 继续最近 session

```bash
opencode run --continue "$PROMPT"
```

### 继续指定 session

```bash
opencode run --session "$SESSION_ID" "$PROMPT"
```

### 明确禁止

不要默认使用：

```bash
opencode run --dangerously-skip-permissions "$PROMPT"
```

---

## 6.7 OpenCode session 管理命令

### 列 session

```bash
opencode session list
```

### JSON 格式

```bash
opencode session list --format json
```

### 限制最近 N 个

```bash
opencode session list --max-count 20 --format json
```

### 导出 session

```bash
opencode export "$SESSION_ID"
```

可用于 diagnostic bundle，但默认不要包含完整敏感内容。

---

## 6.8 OpenCode agent / 权限配置

### 列 agents

```bash
opencode agent list
```

### 创建 agent

交互式：

```bash
opencode agent create
```

非交互式示例：

```bash
opencode agent create \
  --path .opencode/agent/mobile-safe.md \
  --description "Safe mobile coding agent" \
  --mode primary \
  --permissions read,edit,grep,glob,lsp \
  --model anthropic/claude-sonnet-4-5
```

权限可选项包括：

```text
bash, read, edit, glob, grep, webfetch, task, todowrite, websearch, lsp, skill
```

建议为你的 App 创建一个低风险 agent：

```text
read, edit, grep, glob, lsp, todowrite
```

不要默认给：

```text
bash, webfetch, websearch
```

除非有审批链路。

---

## 6.9 OpenCode 推荐 Adapter Profile：Server 模式

```json
{
  "adapterId": "opencode",
  "invocationMode": "http-server",
  "server": {
    "baseUrl": "http://127.0.0.1:4096",
    "health": "GET /global/health",
    "events": "GET /global/event",
    "sessions": "GET /session",
    "createSession": "POST /session",
    "sendMessage": "POST /session/:id/message",
    "sendPromptAsync": "POST /session/:id/prompt_async",
    "abort": "POST /session/:id/abort",
    "diff": "GET /session/:id/diff",
    "permission": "POST /session/:id/permissions/:permissionID"
  },
  "auth": {
    "type": "basic",
    "storedInDaemonOnly": true
  },
  "flutterDirectAccess": false
}
```

---

## 6.10 OpenCode 推荐 Adapter Profile：Process fallback

```json
{
  "adapterId": "opencode-run",
  "invocationMode": "process-json",
  "command": "opencode",
  "argsTemplate": [
    "run",
    "--format",
    "json",
    "{{prompt}}"
  ],
  "cwdPolicy": "workspace-root",
  "stdout": "json-or-jsonl",
  "stderr": "text",
  "resume": {
    "supported": true,
    "argsTemplate": [
      "run",
      "--session",
      "{{sessionId}}",
      "--format",
      "json",
      "{{prompt}}"
    ]
  },
  "dangerousFlagsForbidden": [
    "--dangerously-skip-permissions"
  ]
}
```

---

# 7. 统一启动命令模板

## 7.1 Claude

```bash
claude --bare -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  --permission-mode acceptEdits \
  --allowedTools "Read,Edit,Bash(git status *),Bash(git diff *),Bash(npm test *),Bash(dart test *),Bash(flutter test *)"
```

## 7.2 Codex

```bash
codex exec --json \
  --cd "$WORKSPACE" \
  --sandbox workspace-write \
  --ask-for-approval on-request \
  "$PROMPT"
```

## 7.3 OpenCode Server

```bash
OPENCODE_SERVER_USERNAME="daemon" \
OPENCODE_SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD" \
opencode serve --hostname 127.0.0.1 --port 4096
```

然后 daemon 调：

```http
GET  http://127.0.0.1:4096/global/health
GET  http://127.0.0.1:4096/global/event
POST http://127.0.0.1:4096/session
POST http://127.0.0.1:4096/session/:id/prompt_async
GET  http://127.0.0.1:4096/session/:id/diff
POST http://127.0.0.1:4096/session/:id/abort
```

## 7.4 OpenCode Process fallback

```bash
opencode run --format json "$PROMPT"
```

或连接 server：

```bash
opencode run --attach http://localhost:4096 --format json "$PROMPT"
```

---

# 8. App 功能与 CLI 命令映射

| App 功能 | Claude Code | Codex | OpenCode |
|---|---|---|---|
| 检测安装 | `claude --version` | `codex --version` / `codex --help` | `opencode --version` / `opencode --help` |
| 检测登录 | `claude auth status` | `codex login status` | `opencode auth list` |
| 创建任务 | `claude --bare -p ... stream-json` | `codex exec --json ...` | `POST /session` + `POST /session/:id/prompt_async` |
| 实时输出 | stdout JSONL | stdout JSONL | `/global/event` SSE / session APIs |
| 继续最近任务 | `--continue` | `codex exec resume --last` | `opencode run --continue` |
| 继续指定任务 | `--resume <id>` | `codex exec resume <id>` | `opencode run --session <id>` / server session API |
| 取消任务 | kill process | kill process | `POST /session/:id/abort` |
| 权限审批 | `--allowedTools` / `--permission-mode` / permission prompt tool | `--ask-for-approval` | `POST /session/:id/permissions/:permissionID` |
| 变更查看 | git diff fallback | git diff fallback | `GET /session/:id/diff` |
| 会话列表 | 本地记录为主 | 本地记录为主 | `GET /session` / `opencode session list --format json` |
| 模型选择 | `--model` | `--model` | `--model` / provider API |
| 安全沙箱 | tools / permission mode | `--sandbox` | agent permissions / server permissions |

---

# 9. Daemon 实现建议

## 9.1 不要使用 shell 字符串

不要：

```ts
exec(`codex exec --json "${prompt}"`);
```

要：

```ts
spawn("codex", [
  "exec",
  "--json",
  "--cd",
  workspacePath,
  "--sandbox",
  "workspace-write",
  "--ask-for-approval",
  "on-request",
  prompt
], {
  cwd: workspacePath,
  env: safeEnv
});
```

## 9.2 JSONL parser

Claude 和 Codex 都适合 JSONL parser。

```ts
class JsonLineParser {
  private buffer = "";

  push(chunk: Buffer, onEvent: (event: unknown) => void, onError: (line: string) => void) {
    this.buffer += chunk.toString("utf8");

    while (true) {
      const i = this.buffer.indexOf("\n");
      if (i < 0) break;

      const line = this.buffer.slice(0, i).trim();
      this.buffer = this.buffer.slice(i + 1);

      if (!line) continue;

      try {
        onEvent(JSON.parse(line));
      } catch {
        onError(line.slice(0, 500));
      }
    }
  }
}
```

## 9.3 进程取消

```ts
function cancelProcess(child: ChildProcess) {
  child.kill("SIGTERM");

  setTimeout(() => {
    if (!child.killed) {
      child.kill("SIGKILL");
    }
  }, 5000);
}
```

Windows 需要进程树清理。

## 9.4 Workspace 边界

手机端请求只能传：

```json
{
  "workspaceId": "my-project"
}
```

不能传：

```json
{
  "cwd": "C:\\Users\\..."
}
```

Daemon 根据 workspace registry 转换：

```ts
const workspacePath = workspaceRegistry.resolve(workspaceId);
```

---

# 10. 需要明确禁止的命令/参数

## 10.1 Claude Code 禁止

```bash
claude --dangerously-skip-permissions
```

除非用户在电脑端明确开启 isolated runner。

## 10.2 Codex 禁止

```bash
codex exec --dangerously-bypass-approvals-and-sandbox
codex exec --yolo
codex exec --sandbox danger-full-access
```

`danger-full-access` 不应由手机端触发。  
如果以后支持，必须电脑端配置 + 二次确认 + 审计。

## 10.3 OpenCode 禁止

```bash
opencode run --dangerously-skip-permissions
```

除非 isolated runner。

## 10.4 所有工具禁止

手机端不得传：

```text
raw cmd
raw cwd
raw shell path
raw cli args
environment variables
provider API key
OpenCode server password
```

---

# 11. 推荐 UI 操作与后端命令映射

## 11.1 AI 中间 Tab：创建任务

用户输入：

```text
修复 login_test.dart 失败的问题，补充边界条件测试
```

Daemon 执行：

Claude：

```bash
claude --bare -p "$PROMPT" --output-format stream-json --verbose --include-partial-messages --permission-mode acceptEdits
```

Codex：

```bash
codex exec --json --cd "$WORKSPACE" --sandbox workspace-write --ask-for-approval on-request "$PROMPT"
```

OpenCode：

```http
POST /session
POST /session/:id/prompt_async
```

---

## 11.2 文件变更页

Daemon 统一执行：

```bash
git status --short
git diff --stat
git diff -- "$FILE"
```

OpenCode server 模式优先：

```http
GET /session/:id/diff
GET /vcs
```

---

## 11.3 运行测试模板

不要手机发 raw command。手机只发 template id：

```json
{
  "templateId": "dart-test"
}
```

Daemon 内部：

```bash
dart test
# 或
flutter test
```

如果交给 AI 工具：

Claude：

```bash
claude --bare -p "Run the test suite and fix failures" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  --allowedTools "Read,Edit,Bash(dart test *),Bash(flutter test *)"
```

Codex：

```bash
codex exec --json \
  --cd "$WORKSPACE" \
  --sandbox workspace-write \
  --ask-for-approval on-request \
  "Run the test suite and fix failures"
```

---

## 11.4 取消任务

App：

```http
POST /api/runs/:runId/cancel
```

Daemon：

- Claude/Codex/OpenCode process fallback：kill child process
- OpenCode server：`POST /session/:id/abort`

---

# 12. 推荐优先级

## V1 必须支持

1. Claude `stream-json`
2. Codex `exec --json`
3. OpenCode `serve` health/session/event/diff/abort
4. 统一 JSONL parser
5. process kill cancel
6. workspace whitelist
7. run event normalization
8. git diff fallback

## V1.1 支持

1. Claude resume
2. Codex exec resume
3. OpenCode session list/status
4. command templates
5. approval mapping
6. model selector
7. adapter diagnostics

## V2 可选

1. Codex app-server
2. OpenCode SDK client generation from OpenAPI
3. Claude Agent SDK TypeScript/Python
4. remote relay / Tailscale mode
5. multi-device coordination

仍然不建议做 PTY，除非以后明确要支持 TUI 镜像。

---

# 13. 参考资料

## Claude Code

- Headless / Programmatic usage: https://code.claude.com/docs/en/headless
- CLI reference: https://code.claude.com/docs/en/cli-reference
- Overview: https://code.claude.com/docs/en/overview

## Codex

- CLI reference: https://developers.openai.com/codex/cli/reference
- CLI features: https://developers.openai.com/codex/cli/features
- Agent approvals & security: https://developers.openai.com/codex/agent-approvals-security
- Config reference: https://developers.openai.com/codex/config-reference

## OpenCode

- CLI docs: https://opencode.ai/docs/cli/
- Server docs: https://opencode.ai/docs/server/
- Web docs: https://opencode.ai/docs/web/
- Config docs: https://opencode.ai/docs/config/

---

# 14. 最终建议

你的 App 最核心的控制命令应该固定成三条主线：

```bash
claude --bare -p "$PROMPT" --output-format stream-json --verbose --include-partial-messages
```

```bash
codex exec --json --cd "$WORKSPACE" --sandbox workspace-write --ask-for-approval on-request "$PROMPT"
```

```bash
opencode serve --hostname 127.0.0.1 --port 4096
```

OpenCode 由 daemon 走 HTTP API 控制：

```http
GET  /global/health
GET  /global/event
POST /session
POST /session/:id/prompt_async
GET  /session/:id/diff
POST /session/:id/abort
POST /session/:id/permissions/:permissionID
```

一句话原则：

> 手机端负责创建任务、查看执行流、审批、取消和看 diff；Desktop Daemon 负责 CLI 调用、权限边界、进程管理和事件归一化。
