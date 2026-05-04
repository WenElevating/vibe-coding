# Claude Code 命令执行结果获取指南

Date: 2026-05-04
Scope: Agent 如何从 Claude Code CLI 获取 Bash/工具执行结果

---

## 1. 结果获取的三条路径

### 路径 A：stream-json 事件流（最完整，推荐）

使用 `--input-format stream-json --output-format stream-json --include-partial-messages` 启动时，Claude Code 执行工具的全过程都会以事件流形式输出到 stdout。

时序如下：

```
tool_use_start  → 工具名称 + 输入参数
tool_use_delta  → 执行过程中的实时输出（需 --include-partial-messages）
tool_use_result → 完整输出 + exit_code + is_error
assistant       → Claude 对结果的文字描述
result          → 整轮结束，含 session_id
```

典型事件结构：

```json
// tool_use_start
{
  "type": "tool_use",
  "id": "toolu_abc123",
  "name": "Bash",
  "input": {
    "command": "npm test",
    "description": "运行单元测试"
  }
}

// tool_use_result（命令执行完成后）
{
  "type": "tool_result",
  "tool_use_id": "toolu_abc123",
  "content": "✓ 12 tests passed\n✗ 2 tests failed\n...",
  "exit_code": 1,
  "is_error": true
}
```

### 路径 B：result 事件（最终文字摘要）

每轮结束时 Claude 会输出一个 `result` 事件，包含它对整轮执行情况的**自然语言描述**：

```json
{
  "type": "result",
  "result": "运行了 npm test，共 14 个测试，12 个通过，2 个失败。失败原因是...",
  "session_id": "sess_xxx",
  "is_error": false
}
```

这是 Claude 的**语义总结**，不是原始命令输出。适合展示给用户，不适合机器解析。

### 路径 C：结构化 JSON 输出（单次查询场景）

非流式场景下，配合 `--output-format json` 和 `--json-schema` flag，可以让 Claude 把执行结果格式化成你定义的 schema：

```bash
claude -p "运行测试并报告结果" \
  --output-format json \
  --json-schema '{
    "type": "object",
    "properties": {
      "passed": { "type": "integer" },
      "failed": { "type": "integer" },
      "errors": { "type": "array", "items": { "type": "string" } }
    }
  }'
```

适合 CI/CD 等需要机器可读输出的无状态场景。

---

## 2. 各路径对比

| | 路径 A（事件流） | 路径 B（result 摘要） | 路径 C（json-schema） |
|---|---|---|---|
| 获取原始 stdout/stderr | ✅ | ❌ | ❌ |
| 获取 exit code | ✅（需显式提取） | ❌ | 取决于 prompt |
| 实时输出 | ✅ | ❌ | ❌ |
| 多工具调用追踪 | ✅ | ❌ | ❌ |
| 机器可读结构 | 需自行解析 | ❌ | ✅ |
| 适用场景 | 长期运行 agent | 用户展示 | 单次无状态查询 |

---

## 3. 当前常见实现的信息损失问题

许多 adapter 实现在翻译工具事件时只提取文本，丢掉了结构化字段：

```javascript
// ❌ 常见写法：信息损失严重
if (rawType.includes('tool')) {
  return {
    type: eventTypes.TOOL_OUTPUT,
    text: extractText(raw),  // 只拿了文本
    raw                      // raw 挂在这里但通常不被消费
  };
}
```

`tool_result` 事件里实际包含：

| 字段 | 含义 | 是否常被丢弃 |
|---|---|---|
| `content` | 命令输出文本 | 保留 |
| `exit_code` | 进程退出码 | **常被丢弃** |
| `is_error` | 是否执行失败 | **常被丢弃** |
| `tool_use_id` | 与 start 事件的关联 id | **常被丢弃** |

### 正确写法

```javascript
function mapToolResultEvent(raw) {
  return {
    type: eventTypes.TOOL_OUTPUT,
    toolUseId: raw.tool_use_id,
    text: extractText(raw),
    exitCode: raw.exit_code ?? null,
    isError: raw.is_error === true,
    raw
  };
}
```

---

## 4. 根据 exit code 判断命令是否成功

agent 判断命令执行结果时，**不应依赖 Claude 的文字描述**（它可能措辞不稳定），应直接读 `exit_code`：

```javascript
function handleToolOutput(event) {
  if (event.exitCode !== null && event.exitCode !== 0) {
    // 命令执行失败
    reportFailure({
      toolUseId: event.toolUseId,
      exitCode: event.exitCode,
      output: event.text
    });
  }
}
```

常见 exit code 含义（Bash 工具）：

| exit_code | 含义 |
|---|---|
| `0` | 成功 |
| `1` | 通用错误（测试失败、编译错误等） |
| `2` | 命令用法错误 |
| `127` | 命令未找到 |
| `128+N` | 被信号 N 终止 |
| `null` | Claude Code 未返回该字段（旧版本兼容） |

---

## 5. 多工具调用的关联追踪

一轮对话里 Claude 可能调用多次工具，通过 `tool_use_id` 把 start 和 result 配对：

```javascript
const pendingTools = new Map();

function onEvent(event) {
  if (event.type === eventTypes.TOOL_STARTED) {
    pendingTools.set(event.toolUseId, {
      name: event.name,
      input: event.input,
      startedAt: Date.now()
    });
  }

  if (event.type === eventTypes.TOOL_OUTPUT) {
    const started = pendingTools.get(event.toolUseId);
    if (started) {
      const duration = Date.now() - started.startedAt;
      recordToolExecution({
        name: started.name,
        input: started.input,
        output: event.text,
        exitCode: event.exitCode,
        isError: event.isError,
        durationMs: duration
      });
      pendingTools.delete(event.toolUseId);
    }
  }
}
```

---

## 6. stream_event 包装的处理

Claude Code 有时会把工具事件包在 `stream_event` 外层，解析前必须先拆包：

```javascript
function unwrapEvent(raw) {
  // 部分版本会把事件包在 stream_event 里
  if (raw.type === 'stream_event' && raw.event && typeof raw.event === 'object') {
    return {
      ...raw.event,
      session_id: raw.event.session_id || raw.session_id
    };
  }
  return raw;
}

function parseClaudeEvent(raw) {
  return mapClaudeEvent(unwrapEvent(raw));
}
```

---

## 7. 结构化输出的 prompt 设计（路径 C 补充）

使用 `--json-schema` 时，prompt 的设计对输出质量影响很大：

```bash
# 推荐：明确告诉 Claude 要做什么、输出什么
claude -p "
  运行 npm test。
  把结果整理成 JSON，包含：
  - passed: 通过的测试数
  - failed: 失败的测试数  
  - failedTests: 失败测试的名称列表
  - exitCode: 命令退出码
" \
  --output-format json \
  --allowedTools "Bash(npm test *)" \
  --json-schema '{...}'
```

注意事项：
- `--json-schema` 只在 print 模式（`-p`）下可用
- schema 验证由 Claude Code 完成，不匹配时会重试
- 复杂 schema 可能增加 token 消耗

---

## 8. 选型建议

| 场景 | 推荐方案 |
|---|---|
| 长期运行的交互式 agent，需要实时反馈 | 路径 A，显式提取 exit_code 和 is_error |
| CI/CD 流水线，单次任务，需要结构化结果 | 路径 C，配合 `--json-schema` |
| 只需要向用户展示执行摘要 | 路径 B，直接消费 result 事件的文字 |
| 需要审计每一个工具调用的输入输出 | 路径 A，用 tool_use_id 做关联追踪 |

---

*参考文档：https://code.claude.com/docs/en/agent-sdk/overview*
*工具输入输出类型：https://code.claude.com/docs/en/agent-sdk/python#tool-input-output-types*
