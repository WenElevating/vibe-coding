# Flutter 局域网控制 Claude Code / Codex / OpenCode CLI 通信方案调研

> 目标：自己写一个 Flutter 手机端应用，在同一局域网内控制电脑上的 Claude Code、Codex、OpenCode 等 AI Coding CLI，支持创建任务、实时查看输出、继续会话、停止任务、审批危险操作，并尽量保证安全性和可扩展性。

---

## 1. 结论

推荐方案：

**Flutter App 不直接连接 Claude Code / Codex / OpenCode，而是连接电脑上自研的本地 Controller Daemon。**

通信结构如下：

```text
Flutter App
  ├─ HTTP REST：登录、配对、列 workspace、创建任务、取消任务、审批操作
  └─ WebSocket：实时输出、状态变化、增量文本、tool call、审批请求、任务完成事件

Desktop Controller Daemon
  ├─ Auth / Pairing / ACL
  ├─ Session Manager
  ├─ Process Supervisor
  ├─ Workspace Registry
  ├─ Claude Adapter   -> spawn claude CLI
  ├─ Codex Adapter    -> spawn codex CLI
  └─ OpenCode Adapter -> call opencode server API 或 spawn opencode CLI
```

核心判断：

- **手机端只维护一套协议**，不要分别理解 Claude Code、Codex、OpenCode 的内部事件格式。
- **电脑端 daemon 负责适配各 CLI**，把不同 CLI 的输出统一转换成标准事件。
- **WebSocket 做主通道**，因为这是一个双向实时控制场景：手机既要接收输出，也要随时发送取消、继续输入、审批等控制消息。
- **HTTP REST 做控制面**，负责可重试、幂等、状态查询类请求。
- **CLI 调用层优先使用官方 headless / exec / server 能力**：
  - Claude Code：`claude -p --output-format stream-json`
  - Codex：`codex exec --json`
  - OpenCode：`opencode serve`

---

## 2. 为什么不让 Flutter 直接控制 CLI？

不推荐 Flutter 直接通过 SSH / shell / 各 CLI 原生协议操作电脑上的工具。

原因：

1. **安全边界太差**  
   手机 App 一旦能远程执行任意 shell，风险非常高。你很容易做出类似：

   ```http
   POST /exec
   {"cmd": "rm -rf ..."}
   ```

   这种接口必须避免。

2. **三套 CLI 的协议不统一**  
   Claude Code、Codex、OpenCode 的自动化方式不同：
   - Claude Code 更适合通过 headless CLI 输出 JSONL。
   - Codex 稳定路线是 `codex exec --json`。
   - OpenCode 已经有 `opencode serve` HTTP server。

3. **移动端不应该处理进程生命周期**  
   子进程启动、退出码、stdout/stderr、JSONL 半包、kill process group、session resume，这些都应该放在电脑端 daemon。

4. **后续扩展困难**  
   如果未来想支持 Gemini CLI、Aider、Qwen Code、自研 agent，只需要新增 daemon adapter，而不是改 Flutter 主协议。

---

## 3. 推荐通信协议：HTTP REST + WebSocket

### 3.1 WebSocket 用途

WebSocket 适合以下事件：

- 实时 assistant token / message delta
- tool call started / finished
- stdout / stderr 输出
- diff 事件
- approval required
- run completed / failed
- 手机端发送 cancel / approve / follow-up input

WebSocket 是双向通信通道，适合这种“手机控制正在运行的远端任务”的场景。

参考：MDN 对 WebSocket 的说明：WebSocket API 可以在用户客户端和服务端之间打开双向交互通信会话，客户端可以向服务端发送消息，也可以接收服务端响应，不需要轮询。  
Source: https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API

### 3.2 HTTP REST 用途

HTTP REST 适合以下操作：

```http
POST /api/pair
GET  /api/workspaces
POST /api/workspaces
GET  /api/runs
GET  /api/runs/{runId}
POST /api/runs
POST /api/runs/{runId}/cancel
POST /api/runs/{runId}/input
POST /api/approvals/{approvalId}/respond
GET  /api/runs/{runId}/events?afterSeq=100
```

HTTP 的好处：

- 简单
- 易调试
- 易做鉴权
- 易做重试
- 手机断线后可以补历史事件

### 3.3 为什么不用纯 SSE？

SSE 适合“服务端持续推送，客户端只读”的场景。

但这里手机端需要：

- 发送 follow-up prompt
- 点击 approve / deny
- 取消任务
- 切换订阅
- 发送心跳
- 请求补发事件

这些都属于双向交互。SSE 可以配合 HTTP POST 勉强实现，但整体不如 WebSocket 自然。

参考：MDN 对 Server-Sent Events 的说明：SSE 允许服务端随时向网页推送新数据。  
Source: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events

---

## 4. 总体架构

```text
+-------------------+           HTTP / WebSocket           +--------------------------+
|                   |  <--------------------------------->  |                          |
|   Flutter App     |                                      |  Desktop Controller      |
|   iOS / Android   |                                      |  Daemon                  |
|                   |                                      |                          |
+-------------------+                                      +------------+-------------+
                                                                        |
                                                                        |
                                             +--------------------------+--------------------------+
                                             |                          |                          |
                                      spawn process              spawn process                HTTP API
                                             |                          |                          |
                                      +------+-------+           +------+-------+           +------+-------+
                                      | Claude Code  |           | Codex CLI    |           | OpenCode     |
                                      | claude -p    |           | codex exec   |           | serve API    |
                                      +--------------+           +--------------+           +--------------+
```

Daemon 的核心职责：

- 监听局域网连接
- 配对和认证
- 管理 workspace 白名单
- 启动 / 停止 CLI 子进程
- 解析 JSONL 输出
- 标准化事件
- 存储 session / run / event 历史
- 做权限控制和危险操作审批
- 屏蔽不同 CLI 的协议差异

---

## 5. Daemon 与各 CLI 的适配方式

---

## 5.1 Claude Code Adapter

Claude Code 官方支持通过 CLI 非交互调用，并支持 `stream-json` 输出。

推荐调用方式：

```bash
claude --bare -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

继续指定会话：

```bash
claude -p "$PROMPT" \
  --resume "$SESSION_ID" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

建议：

- MVP 阶段优先使用 `--bare`，降低 hooks、plugins、memory、MCP、项目配置带来的不确定性。
- 使用 `--output-format stream-json` 获取 JSONL 事件流。
- 将 Claude 输出事件转换成统一的 daemon event。
- 保存 Claude 返回的 session id，用于后续 resume。

参考资料：

- Claude Code headless 官方文档：  
  https://code.claude.com/docs/en/headless
- Claude Code CLI reference：  
  https://code.claude.com/docs/ja/cli-reference

### Claude Adapter 伪代码

```ts
import { spawn } from "node:child_process";

function runClaude(prompt: string, cwd: string) {
  const child = spawn("claude", [
    "--bare",
    "-p",
    prompt,
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
  ], {
    cwd,
    env: buildSafeEnv(),
    stdio: ["ignore", "pipe", "pipe"],
  });

  parseJsonl(child.stdout, event => {
    publish(normalizeClaudeEvent(event));
  });

  child.stderr.on("data", chunk => {
    publish({
      type: "process.stderr",
      text: chunk.toString("utf8"),
    });
  });

  child.on("exit", code => {
    publish({
      type: "run.completed",
      exitCode: code,
    });
  });

  return child;
}
```

---

## 5.2 Codex Adapter

Codex CLI 官方文档中，`codex exec` 是非交互运行方式，并支持 `--json` 输出 JSONL 事件。

推荐调用方式：

```bash
codex exec --json \
  --sandbox workspace-write \
  --ask-for-approval on-request \
  "$PROMPT"
```

继续指定会话：

```bash
codex exec resume "$SESSION_ID" "$PROMPT" --json
```

或者继续当前目录最近的会话：

```bash
codex exec resume --last "$PROMPT" --json
```

参考资料：

- Codex CLI reference：  
  https://developers.openai.com/codex/cli/reference
- Codex App Server：  
  https://developers.openai.com/codex/app-server

### 是否使用 Codex App Server？

Codex 有 `app-server`，并支持 WebSocket / JSON-RPC 形式的双向通信。但我不建议 MVP 强依赖它。

原因：

- `codex exec --json` 更稳定、简单。
- `app-server` 更像给 IDE / 本地开发集成使用的底层能力。
- 你的 Flutter App 仍然需要统一协议，所以即使用 `app-server`，也应该由 daemon 适配，而不是 Flutter 直接连接。

建议：

- MVP：使用 `codex exec --json`
- 后续高级版本：评估是否接入 `codex app-server`

---

## 5.3 OpenCode Adapter

OpenCode 最适合服务化集成，因为它官方提供 `opencode serve`。

启动示例：

```bash
OPENCODE_SERVER_PASSWORD='strong-random-password' \
opencode serve --hostname 0.0.0.0 --port 4096 --mdns
```

OpenCode server 支持：

- HTTP server
- OpenAPI endpoint
- Basic Auth
- `--hostname`
- `--port`
- `--mdns`
- CORS 配置

参考资料：

- OpenCode Server 官方文档：  
  https://opencode.ai/docs/server/
- OpenCode Web 官方文档：  
  https://opencode.ai/docs/web/
- OpenCode Config 文档：  
  https://opencode.ai/docs/ja/config/

建议：

- 不要让 Flutter 直接访问 OpenCode server。
- 让 daemon 访问 OpenCode server，再转换成统一事件。
- OpenCode 的 basic auth 只作为 daemon 与 OpenCode server 之间的一层保护，不作为最终 App 鉴权。

---

## 6. 统一事件协议设计

Flutter 不应该关心 Claude / Codex / OpenCode 的原始事件结构。

建议 daemon 对外统一成以下事件。

### 6.1 run.started

```json
{
  "type": "run.started",
  "seq": 1,
  "runId": "run_123",
  "tool": "claude",
  "workspaceId": "my_project",
  "createdAt": "2026-04-30T10:00:00Z"
}
```

### 6.2 assistant.delta

```json
{
  "type": "assistant.delta",
  "seq": 2,
  "runId": "run_123",
  "text": "我先查看项目结构。"
}
```

### 6.3 tool.started

```json
{
  "type": "tool.started",
  "seq": 3,
  "runId": "run_123",
  "toolCallId": "tool_abc",
  "name": "bash",
  "input": {
    "command": "npm test"
  }
}
```

### 6.4 tool.output

```json
{
  "type": "tool.output",
  "seq": 4,
  "runId": "run_123",
  "toolCallId": "tool_abc",
  "stream": "stdout",
  "text": "test output..."
}
```

### 6.5 approval.required

```json
{
  "type": "approval.required",
  "seq": 5,
  "runId": "run_123",
  "approvalId": "ap_456",
  "risk": "medium",
  "action": "edit_file",
  "summary": "修改 lib/main.dart",
  "details": {
    "path": "lib/main.dart"
  }
}
```

### 6.6 run.completed

```json
{
  "type": "run.completed",
  "seq": 100,
  "runId": "run_123",
  "exitCode": 0
}
```

### 6.7 run.failed

```json
{
  "type": "run.failed",
  "seq": 100,
  "runId": "run_123",
  "error": {
    "code": "PROCESS_EXITED",
    "message": "codex exited with code 1"
  }
}
```

---

## 7. Flutter 到 Daemon 的控制消息

### 7.1 创建任务

```json
{
  "type": "run.create",
  "clientRequestId": "uuid",
  "tool": "claude",
  "workspaceId": "my_project",
  "prompt": "帮我修复测试失败",
  "mode": "workspace-write"
}
```

### 7.2 继续会话

```json
{
  "type": "run.continue",
  "clientRequestId": "uuid",
  "runId": "run_123",
  "prompt": "继续，把 lint 也修了"
}
```

### 7.3 停止任务

```json
{
  "type": "run.cancel",
  "runId": "run_123"
}
```

### 7.4 审批操作

```json
{
  "type": "approval.respond",
  "approvalId": "ap_456",
  "decision": "allow"
}
```

或者：

```json
{
  "type": "approval.respond",
  "approvalId": "ap_456",
  "decision": "deny",
  "reason": "不要修改配置文件"
}
```

### 7.5 订阅历史事件

```json
{
  "type": "run.subscribe",
  "runId": "run_123",
  "afterSeq": 42
}
```

---

## 8. 数据存储设计

建议 daemon 使用 SQLite。

### 8.1 表结构

```sql
CREATE TABLE workspaces (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE runs (
  id TEXT PRIMARY KEY,
  tool TEXT NOT NULL,
  workspace_id TEXT NOT NULL,
  status TEXT NOT NULL,
  prompt TEXT NOT NULL,
  cli_session_id TEXT,
  process_id INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE events (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(run_id, seq)
);

CREATE TABLE approvals (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  status TEXT NOT NULL,
  action TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  token_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen_at TEXT
);
```

### 8.2 为什么事件要持久化？

因为手机端经常断线：

- 锁屏
- 网络切换
- App 进入后台
- 局域网不稳定
- 电脑睡眠

所以 WebSocket 不能是唯一状态来源。

正确做法：

1. 每个事件写入 SQLite。
2. 每个事件有递增 `seq`。
3. 手机端保存最后收到的 `seq`。
4. 重连后请求 `afterSeq` 之后的事件。

---

## 9. JSONL 解析

Claude Code 和 Codex 都适合输出 JSONL。

子进程 stdout 的 chunk 不一定刚好是一行，所以必须 buffer。

```ts
function parseJsonl(stream: NodeJS.ReadableStream, onEvent: (event: any) => void) {
  let buffer = "";

  stream.on("data", chunk => {
    buffer += chunk.toString("utf8");

    while (true) {
      const index = buffer.indexOf("\n");
      if (index < 0) break;

      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);

      if (!line) continue;

      try {
        onEvent(JSON.parse(line));
      } catch {
        onEvent({
          type: "raw.output",
          text: line,
        });
      }
    }
  });

  stream.on("end", () => {
    const line = buffer.trim();
    if (!line) return;

    try {
      onEvent(JSON.parse(line));
    } catch {
      onEvent({
        type: "raw.output",
        text: line,
      });
    }
  });
}
```

---

## 10. 安全设计

这是整个项目最关键的部分。

你本质上是在做一个“手机远程控制电脑 AI agent 执行代码和 shell”的工具。不能把它当普通局域网小工具处理。

### 10.1 默认不开 LAN

daemon 默认只监听：

```text
127.0.0.1
```

用户明确开启 LAN 模式后才监听：

```text
0.0.0.0
```

### 10.2 首次配对

电脑端显示一次性配对码或二维码：

```text
Pairing Code: 482-193
```

Flutter 扫码或输入配对码。

配对成功后：

- 手机获得 device token
- daemon 保存 token hash
- 原始 token 只在手机端保存

### 10.3 Workspace 白名单

手机端不能传任意 `cwd`。

错误设计：

```json
{
  "cwd": "/Users/me"
}
```

正确设计：

```json
{
  "workspaceId": "my_project"
}
```

workspace 只能在电脑端提前登记：

```json
{
  "id": "my_project",
  "path": "/Users/me/code/my_project"
}
```

### 10.4 权限模式

建议定义三档：

```text
read-only
workspace-write
dangerous
```

映射到不同 CLI：

| App mode | Claude Code | Codex | OpenCode |
|---|---|---|---|
| read-only | 限制 allowed tools | sandbox read-only | server-side policy |
| workspace-write | 允许编辑 workspace | `--sandbox workspace-write` | server-side policy |
| dangerous | 需要二次确认 | `--ask-for-approval` / full-auto 慎用 | server-side policy |

### 10.5 禁止任意 shell API

不要提供：

```http
POST /api/exec
```

也不要提供：

```json
{
  "cmd": "任意 shell 命令"
}
```

所有 shell 执行必须由 agent CLI 触发，并经过权限策略、审批策略、日志记录。

### 10.6 日志脱敏

daemon 推送日志前应过滤：

- API key
- `.env`
- SSH private key
- GitHub token
- npm token
- OpenAI / Anthropic / Google token

可先做基础正则脱敏，后续再做更完整的 secret scanner。

---

## 11. 技术栈建议

### 11.1 Daemon

推荐优先级：

1. **TypeScript + Node.js**
2. Go
3. Rust

我更推荐 TypeScript + Node.js 做第一版。

原因：

- 子进程控制方便
- JSON / JSONL 处理方便
- WebSocket / HTTP 生态成熟
- 快速迭代协议
- 和 OpenAPI / SDK 集成更轻松

建议依赖：

```text
fastify 或 hono       HTTP server
ws                    WebSocket
execa 或 child_process 子进程
zod                   协议校验
better-sqlite3        SQLite
pino                  日志
nanoid / uuid         ID 生成
```

### 11.2 Flutter

建议依赖：

```text
dio                   HTTP client
web_socket_channel    WebSocket
riverpod 或 bloc       状态管理
drift 或 sqlite        本地缓存
mobile_scanner        扫二维码配对
```

---

## 12. MVP 范围

第一版不要做太大。

### MVP 必做

- 局域网连接电脑 daemon
- 二维码 / 配对码配对
- workspace 列表
- 创建 run
- 实时输出
- 停止 run
- run 历史记录
- Claude Code adapter
- Codex adapter
- OpenCode adapter 初版

### MVP 可暂缓

- 完整 diff viewer
- 文件浏览器
- 多电脑管理
- Tailscale / WireGuard 远程访问
- 复杂审批 UI
- 多用户权限
- 插件系统
- 语音输入
- push notification

---

## 13. 推荐开发路线

### 阶段 1：本机 CLI 原型

目标：验证 daemon 能稳定启动 CLI 并解析输出。

实现：

```bash
desktop-daemon run claude "解释这个项目结构"
desktop-daemon run codex "修复测试"
desktop-daemon run opencode "检查代码"
```

输出统一 JSONL：

```json
{"type":"assistant.delta","text":"..."}
{"type":"tool.started","name":"bash"}
{"type":"run.completed","exitCode":0}
```

### 阶段 2：HTTP API

实现：

```http
POST /api/runs
GET  /api/runs
GET  /api/runs/{id}/events
POST /api/runs/{id}/cancel
```

先用 curl / Postman 测试。

### 阶段 3：WebSocket

实现：

```text
/ws
```

支持：

- subscribe run
- push events
- cancel
- approve
- heartbeat

### 阶段 4：Flutter App

页面：

- 连接电脑
- workspace 列表
- 新建任务
- run 实时输出
- 历史记录
- 设置页

### 阶段 5：安全加固

加入：

- pairing
- token
- workspace 白名单
- permission mode
- approval flow
- log redaction

---

## 14. Flutter 页面结构建议

```text
App
├─ PairingPage
├─ DevicesPage
├─ WorkspaceListPage
├─ RunCreatePage
├─ RunDetailPage
│  ├─ ChatTimeline
│  ├─ ToolCallCard
│  ├─ ApprovalCard
│  └─ OutputConsole
├─ RunHistoryPage
└─ SettingsPage
```

RunDetailPage 是核心。

UI 事件流：

```text
用户输入 prompt
  -> POST /api/runs
  -> 拿到 runId
  -> WebSocket subscribe runId
  -> 展示 assistant delta / tool call / output
  -> 如果 approval.required，展示允许/拒绝按钮
  -> run.completed 后展示结果
```

---

## 15. Daemon 内部模块设计

```text
src/
├─ server/
│  ├─ http.ts
│  ├─ websocket.ts
│  └─ auth.ts
├─ core/
│  ├─ run-manager.ts
│  ├─ workspace-manager.ts
│  ├─ event-store.ts
│  ├─ approval-manager.ts
│  └─ policy.ts
├─ adapters/
│  ├─ claude-adapter.ts
│  ├─ codex-adapter.ts
│  ├─ opencode-adapter.ts
│  └─ types.ts
├─ process/
│  ├─ process-runner.ts
│  └─ jsonl-parser.ts
├─ db/
│  ├─ schema.sql
│  └─ db.ts
└─ main.ts
```

Adapter 统一接口：

```ts
export interface AgentAdapter {
  name: "claude" | "codex" | "opencode";

  startRun(input: StartRunInput): Promise<RunningAgentProcess>;

  resumeRun(input: ResumeRunInput): Promise<RunningAgentProcess>;

  cancelRun(runId: string): Promise<void>;
}
```

---

## 16. 协议版本化

建议所有 WebSocket 消息带版本：

```json
{
  "protocol": "agent-control.v1",
  "type": "run.create",
  "payload": {}
}
```

未来如果事件结构变化，可以升级到：

```text
agent-control.v2
```

Flutter 和 daemon 可以在连接时协商版本。

---

## 17. 最终建议

最佳方案是：

```text
Flutter App
  <-> HTTP REST + WebSocket
Desktop Controller Daemon
  <-> Claude Code / Codex / OpenCode adapters
```

具体落地：

```text
Flutter
  -> POST /api/runs 创建任务
  -> WebSocket /ws 接收实时事件
  -> POST /api/approvals/{id}/respond 审批危险操作
  -> POST /api/runs/{id}/cancel 停止任务

Daemon
  -> Claude: spawn claude -p --output-format stream-json
  -> Codex: spawn codex exec --json
  -> OpenCode: call opencode serve HTTP API
```

我的明确判断：

- **不要让 Flutter 直接 SSH 到电脑。**
- **不要让 Flutter 分别接 Claude / Codex / OpenCode 原生协议。**
- **不要暴露任意 shell 执行 API。**
- **用自研 daemon 做统一控制层。**
- **WebSocket 做实时主通道，HTTP REST 做控制面。**
- **所有 CLI 输出统一转换成自己的标准事件。**

这是最稳、最安全、最容易产品化的路线。

---

## 18. 参考资料

- Claude Code headless mode  
  https://code.claude.com/docs/en/headless

- Claude Code CLI reference  
  https://code.claude.com/docs/ja/cli-reference

- Codex CLI reference  
  https://developers.openai.com/codex/cli/reference

- Codex App Server  
  https://developers.openai.com/codex/app-server

- OpenCode Server  
  https://opencode.ai/docs/server/

- OpenCode Web  
  https://opencode.ai/docs/web/

- OpenCode Config  
  https://opencode.ai/docs/ja/config/

- MDN WebSocket API  
  https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API

- MDN Server-Sent Events  
  https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events
