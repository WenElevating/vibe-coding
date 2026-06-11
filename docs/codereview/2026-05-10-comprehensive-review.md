# 全面代码审查报告

- **日期**: 2026-05-10
- **项目**: LAN AI CLI 控制面板 (Node.js daemon + Flutter mobile)
- **审查范围**: 性能、稳定性、并发安全、安全、协议一致性
- **涉及代码**:
  - `daemon/src/` — Node.js 守护进程 (HTTP API, 工作区管理, 适配器编排, SQLite 持久化)
  - `mobile/lib/src/` — Flutter 移动客户端 (widgets, models, services, state)

---

## 总览

| 严重级别 | 数量 |
|----------|------|
| CRITICAL (严重) | 12 |
| HIGH (高危) | 17 |
| MEDIUM (中等) | 5 |

**整体评价**: 项目架构清晰，适配器模式和事件溯源设计合理，SQL 查询基本都用了参数化，路径遍历防护到位。最突出的系统性问题是：

1. **缺少任何淘汰/清理策略** — EventStore、RunManager、ConversationManager、AuditLog 四个核心模块只增不减，长时间运行必然 OOM
2. **认证安全加固不足** — 硬编码密钥回退、无速率限制、6 位配对码可暴力破解
3. **移动端资源管理缺失** — HTTP Client 泄漏、Token 不持久化、原生 ASR 资源未释放

---

## 一、严重问题 (CRITICAL) — 12 项

### S1. 硬编码 Token 签名密钥回退值

- **文件**: `daemon/src/auth.js:9`
- **置信度**: 95%
- **问题**: `AUTH_TOKEN_SECRET` 环境变量未设置时，`hashToken()` 回退到静态字符串 `'development-auth-token-secret'`。任何知道此默认值的攻击者可以伪造任意设备的 bearer token，实现完全的认证绕过。
- **影响**: 生产环境未设置环境变量时，认证形同虚设。
- **修复**: 移除默认回退值，启动时强制要求环境变量：

```js
function hashToken(token, secret) {
  if (!secret) throw new Error('AUTH_TOKEN_SECRET environment variable is required');
  return crypto.createHmac('blake2b512', secret).update(token).digest('hex');
}
```

---

### S2. 硬编码设备 ID pepper 回退值

- **文件**: `daemon/src/auth.js:23`
- **置信度**: 95%
- **问题**: `DEVICE_ID_PEPPER` 环境变量未设置时回退到 `'development-device-id-pepper'`。攻击者可预计算已知设备 ID 的哈希值，进行设备冒充和追踪关联攻击。
- **影响**: 设备身份验证可被绕过。
- **修复**: 同 S1，移除默认值，启动时强制要求。

---

### S3. 认证端点无速率限制 — 配对码可暴力破解

- **文件**: `daemon/src/server.js:19-28`
- **置信度**: 92%
- **问题**: 配对码端点 (`POST /api/pairing-code`)、配对端点 (`POST /api/pair`)、Token 刷新端点 (`POST /api/token/refresh`) 均无速率限制。配对码为 6 位数字（`crypto.randomInt(100000, 999999)`），仅 90 万种可能。LAN 内攻击者可在数秒内暴力破解。
- **影响**: 任意 LAN 设备可在配对码有效期内（5 分钟）获得合法认证。
- **修复**: 添加速率限制中间件：
  - `POST /api/pairing-code`: 1 次/30 秒/IP
  - `POST /api/pair`: 10 次/分钟/IP + 指数退避
  - `POST /api/token/refresh`: 20 次/分钟/设备

---

### S4. 请求体无大小限制 — DoS 攻击向量

- **文件**: `daemon/src/server.js:193`
- **置信度**: 90%
- **问题**: `readJson()` 无限制地累积请求体数据到内存中。影响所有 POST 端点（至少 15 个）。
- **影响**: 单个恶意请求即可耗尽 Node.js 进程内存导致 OOM 崩溃。
- **修复**:

```js
async function readJson(req, maxBytes = 1024 * 1024) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > maxBytes) {
      const error = new Error('request body too large');
      error.status = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
```

---

### S5. SQL 注入风险 — ensureColumn 函数

- **文件**: `daemon/src/app-sqlite-store.js:539-543`
- **置信度**: 90%
- **问题**: `ensureColumn()` 的 `table`、`column`、`definition` 参数直接拼接到 SQL 字符串和 PRAGMA 语句中。虽然当前调用点使用硬编码值，但函数本身不校验输入，未来调用者传入用户数据即成为 SQL 注入向量。
- **影响**: 潜在的 SQL 注入风险。
- **修复**: 添加标识符白名单校验：

```js
function ensureColumn(db, table, column, definition) {
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(table) || !/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(column)) {
    throw new Error('Invalid table or column name');
  }
  // ...
}
```

---

### S6. 审计日志仅内存存储，重启丢失

- **文件**: `daemon/src/audit.js:3-16`
- **置信度**: 85%
- **问题**: `AuditLog` 将记录存储在纯数组中。daemon 重启后所有安全操作记录（审批决策、消息、取消操作）全部丢失。且无篡改防护（无哈希、无追加式持久化）。
- **影响**: 对于具有审批流程的 LAN 控制系统，丢失审计历史是安全缺陷。
- **修复**: 将审计记录持久化到 SQLite，添加 `audit_records` 表（自增 ID、type、payload_json、created_at）。

---

### M1. 核心内存存储无限增长 (EventStore / RunManager / ConversationManager)

- **文件**: `event-store.js:4-27`, `run-manager.js:13,34`, `conversation-manager.js:23,84`
- **置信度**: 90-95%
- **问题**: 三个核心模块使用 Map/Array 存储数据，只有 `set`/`push` 操作，没有任何 `delete` 或淘汰逻辑：
  - `EventStore.eventsByRun` — 每次运行的所有事件永久驻留内存
  - `RunManager.runs` — 完成的运行对象（含子进程引用）永久驻留
  - `ConversationManager.conversations` — 对话句柄（含子进程和事件监听器）永久驻留
- **影响**: 长时间运行的 daemon 必然 OOM，尤其在处理大量运行或长对话时。
- **修复**: 实现 TTL 或 LRU 淘汰策略。完成的运行/对话在保留期后自动清理，至少将 `run.child` 置 null。

---

### M2. 审计日志无限增长

- **文件**: `audit.js:4-6`
- **置信度**: 85%
- **问题**: `AuditLog.records` 数组只 push 不清理，与 M1 叠加加剧内存泄漏。
- **修复**: 添加最大容量限制，超过时淘汰最旧记录。

---

### M3. 移动端 HTTP Client 资源泄漏

- **文件**: `mobile/lib/src/services/daemon_client.dart:73-86`, `conversation_client.dart:8-17`
- **置信度**: 92%
- **问题**: `DaemonClient` 和 `ConversationClient` 创建的 `HttpClient`/`IOClient` 没有 `dispose()` 方法。每次用户重连都会创建新客户端，旧的 socket 资源泄漏。
- **影响**: 反复重连后累积泄漏原生 socket 资源。
- **修复**: 为 `DaemonClient` 和 `ConversationClient` 添加 `dispose()` 方法，调用 `_httpClient.close()`。

---

### C1. 事件序列号竞态 + 静默数据丢失

- **文件**: `conversation-event-store.js:10-28`, `app-sqlite-store.js:199-202`
- **置信度**: 90%
- **问题**: `append()` 中 `nextEventSeq()` 从 SQLite 读取 MAX(seq)，然后分别写入内存 Map 和 SQLite。这两步非原子操作。更严重的是 `appendEvent()` 使用 `INSERT OR REPLACE`，同 seq 的事件会被静默覆盖（如 `user.message` 被 `status_changed` 覆盖）。
- **影响**: 数据丢失 — 事件在竞态条件下被静默替换。
- **修复**: 将 `nextEventSeq` + `appendEvent` 包裹在 SQLite 事务中。将 `INSERT OR REPLACE` 改为 `INSERT`，捕获约束冲突后使用新 seq 重试。

---

### C2. 移动端轮询竞态导致重复消息

- **文件**: `coding_workbench_page.dart:825-836`
- **置信度**: 85%
- **问题**: `_restartConversationPolling()` 可从 `_sendPrompt` (line 699) 和 `_respondApproval` (line 1103) 被并发调用。两个重叠调用都可能通过 guard 并各自创建新的 `Timer.periodic`，导致双倍轮询。`_pollEvents()` 本身也无并发守卫。
- **影响**: 重复事件应用导致消息重复显示和状态不一致。
- **修复**: 添加 `bool _pollingInProgress = false` 守卫。

---

### C3. Token 存储在内存中，重启即丢失

- **文件**: `mobile/lib/src/services/daemon_client.dart:29-71`, `mobile_ui.dart:47`
- **置信度**: 95%
- **问题**: 生产环境使用 `MemoryTokenStore`，所有 Token 仅存于易失性内存中。每次冷启动都需重新配对。`SharedPreferences` 存储的连接配置是明文的。
- **影响**: 每次冷启动需重新配对，且 Token/配置未安全存储。
- **修复**: 使用 `flutter_secure_storage` 替换 `MemoryTokenStore`，持久化 Token 到平台密钥链。

---

### P1. 无 Graceful Shutdown

- **文件**: `daemon/src/main.js:98-105`
- **置信度**: 95%
- **问题**: daemon 无 SIGTERM/SIGINT/uncaughtException 处理器。进程退出时：
  - 由适配器启动的子进程（claude, codex 等）成为孤立进程
  - SQLite 数据库未正确关闭，可能导致 WAL 文件损坏
  - `AppSqliteStore.close()` 方法存在但从未被调用
- **影响**: 孤立进程消耗资源并可能损坏工作区状态；数据库损坏风险。
- **修复**: 注册信号处理器：遍历所有活跃运行/对话 → 杀子进程树 → 关闭 SQLite → 退出。

---

## 二、高危问题 (HIGH) — 17 项

### 服务端

| # | 问题 | 文件:行 | 说明 |
|---|------|---------|------|
| H1 | **同步 SQLite API 阻塞事件循环** | `app-sqlite-store.js:15-17` | 使用 `DatabaseSync`，每个请求的 `authenticate` 都阻塞事件循环；未启用 WAL 模式，写入时阻塞所有读取。建议启用 `PRAGMA journal_mode = WAL` 和 `PRAGMA busy_timeout` |
| H2 | **Windows 下 SIGTERM 不杀进程树** | `run-manager.js:96` | `child.kill('SIGTERM')` 仅杀直接子进程，孙进程继续运行。`codex-conversation-adapter.js` 正确使用了 `taskkill /T /F`，但其他适配器没有 |
| H3 | **子进程退出后事件监听器未清理** | `claude-adapter.js:115-121`, `jsonline-adapter.js:61-68` | 退出后 stdout/stderr/child 上的 data/exit 监听器未移除，闭包持有 emitEvent、parseStdout、run 等引用阻止 GC |
| H4 | **无 CORS 保护** | `server.js` (全局) | 未设置任何 CORS 头。恶意网站可向未认证端点 (`/api/health`, `/api/pairing-code`, `/api/pair`) 发送跨域请求 |
| H5 | **工作区文件读取无文件类型限制** | `workspace-inspector.js:47-66` | 任何已认证设备可读取工作区内所有文件（包括 `.env`、密钥文件）。无细粒度控制 |
| H6 | **错误响应暴露内部信息** | `server.js:119` | 错误响应包含 `error.message`、`error.details`、`error.stack`，泄漏文件路径和内部架构 |
| H7 | **RunQueue.cancel() 不更新剩余排队项位置** | `run-queue.js` | 取消排队运行后，剩余项的 `position` 不更新，客户端显示错误的队列位置 |

### 移动端

| # | 问题 | 文件:行 | 说明 |
|---|------|---------|------|
| H8 | **HTTP 请求无超时** | `daemon_client.dart:500-513` | 所有 API 调用无超时设置，网络异常时轮询 future 永远挂起 |
| H9 | **POST 请求无重试** | `daemon_client.dart:516-524` | `_post()` 无重试逻辑，审批操作因网络抖动失败即永久丢失。`_getWithRetry` 仅重试一次、固定 200ms 间隔，无指数退避 |
| H10 | **空工作区列表崩溃** | `app_snapshot.dart:54-55` | `workspaces.first` 在空列表时抛出 `StateError`，无友好错误提示 |
| H11 | **HTTP 明文传输 Token** | `daemon_connection_config.dart:79-93` | 默认 `http://`，LAN 内 Token 可通过 ARP 欺骗被嗅探 |
| H12 | **ASR 原生资源未释放** | `speech_input_service.dart:145-149` | `dispose()` 未释放 `_recognizer` 和 `_recognizerStream`，这些是 ONNX 运行时原生对象，持有大量内存 |
| H13 | **消息列表使用非 builder ListView** | `coding_workbench_page.dart:1232-1251` | 使用 `ListView(children:)` 而非 `ListView.builder`，构建所有消息 widget，长对话时严重卡顿 |
| H14 | **DaemonClient 可变状态** | `daemon_client.dart:88-89` | `_deviceId` 和 `_token` 为可变字段，违反项目不可变性原则 |

### 协议层

| # | 问题 | 文件:行 | 说明 |
|---|------|---------|------|
| H15 | **protocol.warning 事件被静默丢弃** | `conversation_reducer.dart:64-211` | daemon 发出的会话漂移、阻塞项冲突等警告在 Dart reducer 中无 case 处理，用户看不到关键警告 |
| H16 | **normalizeLoadedConversation 直接修改对象** | `app-sqlite-store.js:178-195` | 直接修改反序列化后的 conversation 对象（status、sessionBinding 等），违反不可变性原则。与 `deserializeConversation` 的归一化逻辑重叠 |
| H17 | **MigrationService 是空壳** | `migrations.js` | `schemaVersion` 为 5 但 `schema_migrations` 表只插入版本 1。无实际迁移函数，`ensureColumn` 只能增加列，无法处理类型变更或表重构 |

---

## 三、中等问题 (MEDIUM) — 5 项

| # | 问题 | 文件:行 | 说明 |
|---|------|---------|------|
| Med1 | **版本兼容性检查硬编码 `1.3.` 前缀** | `dashboard_state.dart:20` | `hasVersionMismatch` 硬编码检查 `startsWith('1.3.')`，daemon 升级到 1.4.0 即误报 |
| Med2 | **语音输入错误消息硬编码中文** | `voice_input_controller.dart:179-186` | 未走 `AppLocalizations` i18n 系统，非中文用户无法理解 |
| Med3 | **ASR 模型下载崩溃后部分文件残留** | `asr_model_manager.dart:157-218` | 解压过程中崩溃，staging 目录和模型目录可能处于不一致状态。建议添加 `.extracting` 哨兵文件 |
| Med4 | **coding_workbench_page.dart 超过 1600 行** | 整个文件 | 远超 800 行上限。混合了路由、消息构建、语音管理、ASR 下载、轮询、审批处理等。建议拆分为路由协调器、语音控制器、对话控制器等 |
| Med5 | **diff.summary 事件在 conversation reducer 中未处理** | `conversation_reducer.dart` | 对话模式下的文件变更事件不在状态中追踪，仅在渲染层检查，导致状态不一致 |

---

## 四、优先修复建议

### 第一优先级 — 立即修复（安全防线）

| 序号 | 措施 | 对应问题 |
|------|------|----------|
| 1 | 移除 `auth.js` 中的硬编码密钥回退值，启动时强制要求环境变量 | S1, S2 |
| 2 | 为认证端点添加速率限制 | S3 |
| 3 | 为 `readJson()` 添加请求体大小限制 (1MB) | S4 |
| 4 | 修复事件序列号竞态，事务包裹 seq 读取+写入，`INSERT OR REPLACE` → `INSERT` | C1 |

### 第二优先级 — 尽快修复（稳定性）

| 序号 | 措施 | 对应问题 |
|------|------|----------|
| 5 | 实现 graceful shutdown（信号处理 → 杀子进程树 → 关闭 SQLite → 退出） | P1 |
| 6 | 为 EventStore/RunManager/ConversationManager/AuditLog 添加 TTL 或 LRU 淘汰 | M1, M2 |
| 7 | 移动端 Token 改用 `flutter_secure_storage` 持久化 | C3 |
| 8 | 为所有 HTTP 请求添加超时 (15s)，POST 添加重试+指数退避 | H8, H9 |
| 9 | 修复轮询竞态（添加 `_pollingInProgress` 守卫） | C2 |
| 10 | Windows 下统一使用 `taskkill /T /F` 杀进程树 | H2 |

### 第三优先级 — 规划修复（质量提升）

| 序号 | 措施 | 对应问题 |
|------|------|----------|
| 11 | 启用 SQLite WAL 模式 + `busy_timeout` | H1 |
| 12 | 在 Dart reducer 中处理 `protocol.warning` 和 `diff.summary` | H15, Med5 |
| 13 | 审计日志持久化到 SQLite | S6 |
| 14 | 拆分 `coding_workbench_page.dart` (1614 行 → 多个模块) | Med4 |
| 15 | 实现协议版本协商和 `minMobileVersion` 检查 | H17 |
| 16 | 为 `DaemonClient`/`ConversationClient` 添加 `dispose()` | M3 |
| 17 | 清理子进程退出后的监听器 | H3 |
| 18 | 移动端 HTTP 默认 TLS 或至少警告非 TLS 连接 | H11 |

---

## 五、已确认的良好实践

以下安全实践值得肯定：

- SQL 查询全部使用参数化（除 `ensureColumn` 外）
- 路径遍历防护到位（`safeResolve` + `startsWith` 检查）
- Token 使用 `crypto.timingSafeEqual` 进行时间安全比较
- Token 哈希存储（非明文存储）
- 通过 `assertNoV1TerminalRequest` 显式拒绝 shell 注入字段
- 进程启动使用参数数组（未使用 `shell: true`）
- 审计日志和诊断包中对敏感字段进行了脱敏
- 对话 reducer 模式设计良好，使用不可变状态转换

---

*本报告由并行代码审查代理生成，覆盖 daemon 服务端 20+ 个源文件和 mobile 客户端 30+ 个 Dart 文件。*
