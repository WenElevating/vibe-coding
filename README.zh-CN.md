<!-- DREAMFIELD_README_HEADER_START -->

<p align="center">
  <a href="https://www.dreamfield.top">
    <img src="https://www.dreamfield.top/dream-field/contest-readme/assets/dreamseed-readme-banner.png" alt="DreamSeed 种梦计划参赛作品" width="100%" />
  </a>
</p>

<!-- DREAMFIELD_README_HEADER_END -->

# LAN AI CLI Control

[English](README.md)

LAN AI CLI Control 是一个本地优先的移动端 AI 编程 CLI 控制面。它让手机或同一局域网内的设备可以启动、继续、查看和停止受边界约束的编程会话，但真正的 Claude Code、Codex CLI 或 OpenCode 进程仍然运行在受信任的桌面机器上。

这个项目不是远程终端。daemon 负责工作区授权、CLI 启动、附件校验、事件持久化、诊断和安全边界；Flutter 客户端负责提供适合移动端使用的编程会话工作台。

## 效果图

| Codex 会话 | 带图片提问 |
| --- | --- |
| ![移动端 Codex 会话工作台](images/output/zh/chat-codex.png) | ![移动端图片附件提问效果](images/output/zh/chat-with-image.png) |

## 为什么做这个项目

AI 编程 CLI 很强，但执行上下文非常重要。直接从手机暴露一个远程 shell 太宽泛，也不适合日常高频使用；在设备之间复制 prompt 又会丢掉状态和上下文。这个项目把危险部分留在本机：daemon 运行在开发机上，只允许在授权工作区内执行，并且只暴露编程工作流所需的 HTTP API。

适合这些场景：

- 离开键盘时查看或继续一个正在运行的 AI 编程会话。
- 给 Claude Code 或 Codex CLI 发送后续 prompt，但不暴露任意 shell 执行。
- 在移动端清楚看到 workspace、adapter、model、approval 和 diagnostics 状态。
- 给会话附加支持的图片或文本文件，同时保留 daemon 侧校验、脱敏和清理机制。
- 在同一个控制面查看会话历史、工具输出、命令活动、诊断和工作区状态。

## 当前能力

- 使用 access token 和 refresh token 完成移动端与本地 daemon 配对。
- 按设备注册、重命名、列出和逻辑删除受信任工作区。
- 为 Claude Code 和 Codex CLI 创建、继续和取消会话式编程任务。
- 当检测到的 CLI 支持 model flag 时，在移动端选择模型。
- 通过 capability 校验后的 multipart 请求发送文本 prompt、图片附件和文本附件。
- 在 Flutter 工作台中渲染用户消息、图片预览、assistant 消息、thinking block、工具输出、approval card、task progress 和 run error。
- 使用 SQLite 持久化会话状态和事件历史，应用重启后仍可恢复。
- 将底层生命周期事件保留在事件日志中，同时在主对话 UI 中隐藏低价值协议噪声。
- 导出带 trace id 的脱敏 diagnostics，覆盖 daemon 和 mobile 侧异常。
- 为移动端语音输入提供可选 ASR 模型元数据和断点下载接口。
- 保留旧的受限 task-runner API，用于 run queue、command template、Git status 和 Git diff。

## Adapter 支持矩阵

| Adapter | Conversation | Resume | 模型选择 | 附件 | 说明 |
| --- | --- | --- | --- | --- | --- |
| Claude Code | 支持 | 支持 | 当 `claude` 检测结果报告支持 model flag 时可用 | 原生图片、文本抽取；不分发 PDF | 图片在 base64 转换前限制为 5 MB。CLI 发出 input 或 approval 事件时，移动端可响应。 |
| Codex CLI | 支持 | 通过 `codex exec resume --json` 支持 | 当 `exec` 和 `resume` help 都暴露 model flag 时可用 | 只有当 `exec` 和 `resume` 都支持 image flag 时才启用原生图片；支持文本抽取；不分发 PDF | Codex run adapter 需要显式开启才会出现在 adapter 列表中。conversation adapter 会先校验 CLI JSON 能力。 |
| OpenCode | 仅 attach/run 接口 | run follow-up 需要 session id | 当前路径没有移动端 model picker | 取决于 OpenCode server 能力 | `/api/conversations` 的 OpenCode conversation adapter 目前没有实现。使用 `OPENCODE_SERVER_URL` 走 attach-style adapter。 |
| Synthetic adapters | 仅开发测试 | 测试行为 | 无 | 测试 fixture | 只有 `DEV_ADAPTERS=1` 时启用，用于 daemon 和 UI 的一致性测试。 |

附件能力由 adapter 和选中 model 的 capability 决定。移动端先读取当前 adapter/model capability projection，再决定文件是否允许发送；daemon 会再次校验 multipart payload，嗅探真实文件类型，写入受作用域限制的 scratch 文件，只把附件元数据提交到事件日志，并在终端会话事件后清理 scratch 数据。

## 架构

```text
Flutter mobile app
  -> 带 pairing-token auth 的 daemon HTTP API
    -> Workspace registry 和 SQLite persistence
      -> ConversationManager / RunManager
        -> Claude Code、Codex CLI、OpenCode 或 synthetic adapter
          -> 已授权的桌面 workspace path
```

仓库由两个主要应用组成：

- `daemon/`: Node.js HTTP daemon、认证、workspace ACL、adapter 编排、multipart 附件处理、事件存储、诊断、任务队列和 Git/workspace inspection API。
- `mobile/`: Flutter 应用、连接流程、配对/token 持久化、工作台 UI、reducer、repository、语音输入、附件选择器、本地化和 widget/unit 测试。

重要辅助目录：

- `scripts/`: Node 回归测试 runner 和静态检查。
- `docs/`: PRD、发布说明、实现计划和架构记录。
- `images/output/`: README 效果图。
- `data/`: 本地 SQLite 和运行时数据。不要提交运行时文件。
- `.omx/`: 本地 agent/runtime 产物，按生成文件处理。

## 安全模型

daemon 的设计目标是缩小控制面，而不是暴露终端：

- 移动端不能发送任意 shell 命令。
- 移动端不能指定任意 `cwd`。
- 移动端不能透传任意 CLI 参数。
- API 不暴露持久 PTY session。
- CLI 只能在 daemon 授权过的 workspace path 内运行。
- workspace 访问按 paired device 隔离。
- 配对使用短期 pairing code，设备身份以 hash 形式存储。
- 附件上传必须携带 capability version 和 client message id。
- 附件 diagnostics 和 adapter error 会在返回移动端或进入 diagnostic bundle 前脱敏。
- release mode 会禁用开发 smoke endpoint。

如果把 daemon 绑定到 LAN 网卡，请只在可信网络内使用。这个 daemon 是本地控制面，不应该直接暴露到公网。

## 环境要求

- Node.js 20 或更高版本。
- Flutter SDK，Dart 版本范围为 `>=3.3.0 <4.0.0`。
- 真实会话至少需要安装一个本地 CLI：
  - Claude Code，可通过 `claude` 调用。
  - Codex CLI，可通过 `codex` 调用。
  - OpenCode server，使用 attach/run 路径时需要。
- 语音输入可选：daemon ASR 资产接口期望的 Sherpa ONNX 模型 ZIP。

## 快速开始

安装 daemon 依赖：

```powershell
npm install
```

以 loopback 模式启动 daemon：

```powershell
npm run start:daemon
```

如果要使用 Codex CLI，在 adapter 列表中显式开启 Codex：

```powershell
$env:CODEX_ENABLED='1'
$env:CODEX_COMMAND='codex'
npm run start:daemon
```

只有手机需要连接桌面 daemon 时，才绑定 LAN 地址：

```powershell
$env:DAEMON_HOST='0.0.0.0'
$env:PORT='4317'
npm run start:daemon
```

启用 LAN 模式时，Windows Firewall 可能会弹窗。请只在可信网络内使用，并在 Flutter 应用里连接 `http://<desktop-lan-ip>:4317`。

从 `mobile/` 运行 Flutter 应用：

```powershell
cd mobile
flutter pub get
flutter run -d windows
```

如果你在中国大陆网络环境下开发，Flutter/Dart 命令建议使用镜像：

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter pub get
flutter test
```

## 配置参考

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `DAEMON_HOST` | `127.0.0.1` | HTTP 绑定 host。只有可信 LAN 访问时才使用 `0.0.0.0`。 |
| `PORT` | `4317` | HTTP daemon 端口。 |
| `DAEMON_MODE` | `dev` | 运行模式。release mode 会禁用开发 smoke API。 |
| `APP_DB_PATH` | app data 默认路径 | SQLite 路径，保存 app data、conversation、workspace、auth、exception 等状态。 |
| `CONVERSATION_DB_PATH` | 未设置 | 兼容旧版本的别名，仅在未设置 `APP_DB_PATH` 时使用。 |
| `AUTH_TOKEN_SECRET` | 自动生成的文件 secret | token 签名 secret。未设置时会在 app DB 附近生成 `.daemon-secrets.json`。 |
| `DEVICE_ID_PEPPER` | 自动生成的文件 secret | 设备身份 hash 使用的 pepper。 |
| `CLAUDE_COMMAND` | `claude` | Claude Code 命令或 shim 路径。 |
| `CODEX_ENABLED` | 未启用 | 设置为 `1` 后，在 adapter listing 中暴露 Codex run adapter。 |
| `CODEX_COMMAND` | `codex` | Codex CLI 命令或 shim 路径。 |
| `OPENCODE_SERVER_URL` | `http://127.0.0.1:4096` | OpenCode attach/run adapter 使用的 server 地址。 |
| `DEV_ADAPTERS` | 未启用 | 设置为 `1` 后加入 synthetic adapters，用于开发测试。 |
| `CONVERSATION_IDLE_TTL_MS` | `600000` | conversation 管理使用的 idle TTL。 |

## API 概览

公开的未认证接口：

- `GET /api/health`
- `GET /api/version`
- `POST /api/e2e/smoke`，仅 development mode 可用
- `POST /api/pairing-code`
- `POST /api/pair`
- `POST /api/token/refresh`

需要设备 token 的接口：

- `GET /api/adapters`
- `GET /api/extensions`
- `GET /api/workspaces`
- `POST /api/workspaces`
- `PATCH /api/workspaces/:workspaceId`
- `DELETE /api/workspaces/:workspaceId`
- `GET /api/fs/roots`
- `GET /api/fs/children`
- `GET /api/workspaces/:workspaceId/overview`
- `GET /api/workspaces/:workspaceId/files/tree`
- `GET /api/workspaces/:workspaceId/files/content`
- `GET /api/workspaces/:workspaceId/diagnostics/code`
- `GET /api/workspaces/:workspaceId/git/status`
- `GET /api/workspaces/:workspaceId/git/diff`
- `GET /api/workspaces/:workspaceId/git/commits`
- `GET /api/conversations`
- `POST /api/conversations`
- `PATCH /api/conversations/:conversationId/model`
- `GET /api/conversations/:conversationId/events?afterSeq=0`
- `POST /api/conversations/:conversationId/messages`
- `POST /api/conversations/:conversationId/questions/respond`
- `POST /api/conversations/:conversationId/approvals/:approvalId/respond`
- `POST /api/conversations/:conversationId/cancel`
- `GET /api/runs`
- `POST /api/runs`
- `GET /api/runs/:runId/events?afterSeq=0`
- `POST /api/runs/:runId/input`
- `POST /api/runs/:runId/cancel`
- `POST /api/approvals/:approvalId/respond`
- `GET /api/queue`
- `GET /api/shortcuts`
- `POST /api/shortcuts`
- `GET /api/command-templates`
- `POST /api/command-templates`
- `POST /api/command-templates/:templateId/invoke`
- `POST /api/diagnostics/export`
- `POST /api/exceptions`
- `GET /api/asr-model`
- `GET /api/asr-model/download`
- `POST /api/devices/{deviceId}/revoke`，用于撤销当前认证设备

`/api/conversations` 是移动端编程会话的主接口。`/api/runs` 保留为受边界约束的兼容 task-runner 接口。

## 附件处理链路

conversation message endpoint 对纯文本消息使用 JSON，对带附件消息使用 `multipart/form-data`。multipart 发送包含：

- `clientMessageId`，用于幂等和移动端 optimistic message 对齐。
- `capabilityVersion`，用于拒绝客户端基于过期 adapter/model capability 的发送。
- 声明的附件元数据。
- 按协议顺序上传的文件 bytes。

当前校验包括：

- 文件展示名必须是 flat、已 normalize 的名称，不能包含路径分隔符、控制字符、bidi 控制符、尾随空格/点，不能使用 Windows 保留设备名。
- 支持嗅探 PNG、JPEG、WebP、PDF 和受支持的文本格式。
- 图片尺寸限制为 16,384 x 16,384，最多 4,000 万像素。
- 移动端大小限制：Claude 图片 5 MB，其他支持图片的路径 10 MB，文本附件 1 MB，单次 multipart 总选择 20 MB。
- unsupported kind、payload 格式错误、stale capability version、缺失文件、过大或非法 bytes 都会在 commit 前拒绝。
- terminal conversation event、取消和相关失败路径会触发 scratch 清理。

## 开发命令

在仓库根目录运行 daemon 检查：

```powershell
npm run lint
npm test
```

在 `mobile/` 目录运行 Flutter 检查：

```powershell
flutter analyze
flutter test
dart run tool/check_architecture_imports.dart
```

本地 Windows desktop debug build：

```powershell
cd mobile
flutter build windows --debug
```

## 测试策略

- daemon 协议、adapter、auth、attachment、persistence 和安全边界行为放在 `scripts/run-tests.js` 和 `daemon/test/`。
- Flutter model parsing、reducer、ViewModel、widget 行为和架构导入检查放在 `mobile/test/`。
- 附件类回归如果跨越 HTTP 边界，应同时覆盖 daemon multipart 行为和 mobile 渲染/状态行为。
- 测试应贴近失败层级：daemon 负责 committed protocol 行为，mobile 负责 projection 和 UI 行为。

## ASR 和语音输入

移动端包含基于 Sherpa ONNX 的语音输入路径。daemon 通过以下接口提供模型元数据和 Range 下载：

- `GET /api/asr-model`
- `GET /api/asr-model/download`

默认情况下，daemon 期望模型文件位于 `daemon/asset/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20-mobile.zip`。如果文件缺失，API 会返回结构化的 `ASR_MODEL_UNAVAILABLE` 错误和用户操作建议，而不是静默失败。

## 当前状态和限制

- 应用主要面向 LAN 和本地开发工作流。
- Claude 和 Codex conversation path 是当前主要的编程会话入口。
- OpenCode 目前是 attach/run adapter，不是完整 conversation adapter。
- PDF 元数据和校验已经存在，但当前生产 conversation dispatch 不会把 PDF 发送给 Claude 或 Codex。
- daemon 自身不提供 TLS。请放在可信 LAN 或你自己控制的传输层后面。
- SQLite runtime data、pairing secret、`.omx/`、diagnostic bundle 和构建产物不要提交到 Git。

## 仓库维护约定

提交代码前，按改动层级运行对应检查。Flutter 架构相关改动至少包含：

```powershell
cd mobile
dart run tool/check_architecture_imports.dart
flutter analyze
flutter test
```

daemon API、adapter、attachment、auth 或 persistence 相关改动至少包含：

```powershell
npm run lint
npm test
```

保持运行时生成数据不进 Git，并保留围绕 `cwd`、permissions、stdin handling、event replay、attachment redaction 和 protocol filtering 的测试。
