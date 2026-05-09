# LAN AI CLI Control

[English](README.md)

LAN AI CLI Control 是一个本地优先的 AI 编程 CLI 控制面。它让手机或同一局域网内的设备可以控制桌面端上的 AI CLI 编程会话，但真正的执行仍然留在受信任的桌面 daemon 内，并且只能在已经授权的工作区中运行。

当前项目支持面向会话的 Claude Code 和 Codex CLI 控制，也支持 OpenCode attach 模式以及仅用于开发测试的 synthetic adapter。项目目标是支持真实的编程工作流，同时不暴露原始远程 shell，也不允许移动端传入任意命令。

## 主要能力

- 使用 token 认证完成移动端和本地 daemon 配对。
- 在执行任何 CLI 前，先注册并选择受信任工作区。
- 为支持的 CLI adapter 创建和恢复编程会话。
- 将 assistant 文本、命令/工具调用、输出、状态变化和诊断事件流式同步到移动端。
- 在底层 CLI 支持时保存 CLI session/thread id，用于后续 resume。
- 生命周期和诊断事件会保留在事件日志里；低价值内部事件可以在主对话 UI 中隐藏。
- 提供 health、version 和脱敏 diagnostics export，方便排查问题。

## 安全边界

daemon 明确拒绝无限制终端能力：

- 移动端不能发送任意 shell 命令。
- 移动端不能指定任意 `cwd`。
- 移动端不能透传任意 CLI 参数。
- API 不暴露持久 PTY session。
- CLI 只能在 daemon 已授权的 workspace path 内执行。
- 移动端控制面不能暴露危险的 CLI bypass 模式。

这个项目是受边界约束的本地编程会话控制器，不是远程终端。

## 项目结构

- `daemon/`: Node.js daemon、HTTP API、工作区管理、adapter 编排、持久化和诊断。
- `mobile/`: Flutter 客户端、UI、models、services、reducers 和移动端测试。
- `scripts/`: Node 回归测试和 smoke test 入口。
- `docs/`: 设计说明、UI 参考、发布说明和实现计划。
- `data/`: 本地运行时数据，例如 SQLite 数据库。不要提交。
- `.omx/`: 本地 agent/runtime 产物，按生成文件处理。

## 环境要求

- Node.js 20 或更高版本。
- 用于移动端/客户端开发的 Flutter SDK。
- 如果要运行真实会话，需要至少安装一个支持的本地 AI CLI：
  - Claude Code
  - Codex CLI
  - OpenCode server，使用 attach 模式时需要

## Daemon 命令

在仓库根目录运行：

```powershell
npm test
npm run lint
npm run start:daemon
```

## 移动端命令

在 `mobile/` 目录运行：

```powershell
flutter analyze
flutter test
flutter build windows --debug
```

## Adapter 环境变量

Codex 支持需要显式启用：

```powershell
$env:CODEX_ENABLED='1'
$env:CODEX_COMMAND='codex'
npm run start:daemon
```

OpenCode 当前是 attach-only：

```powershell
$env:OPENCODE_SERVER_URL='http://127.0.0.1:4096'
npm run start:daemon
```

开发测试用 synthetic adapter 可以这样启用：

```powershell
$env:DEV_ADAPTERS='1'
npm run start:daemon
```

## API 范围

daemon 提供以下能力：

- 配对、token 认证和设备撤销。
- 工作区注册和授权。
- adapter capability diagnostics。
- conversation 创建、发送消息、事件重放、取消、输入响应，以及在 adapter 支持时处理 approval response。
- 旧的 run/task 接口和 command templates。
- health、version 和脱敏 diagnostic export。

`/api/runs` 仍然是受限制的 task-runner 接口。面向会话的 CLI 控制应使用 `/api/conversations`。

## 测试说明

adapter、协议、持久化和安全边界改动优先跑 daemon 测试：

```powershell
npm test
```

reducer、model 和 UI 状态改动优先跑 Flutter 测试：

```powershell
cd mobile
flutter test
```

回归测试应尽量贴近 bug 发生的层级。adapter 和 daemon 行为放在 `scripts/run-tests.js`；移动端事件渲染和状态行为放在 `mobile/test/`。

## 当前版本脉络

- V1 建立 LAN daemon、配对/token auth、workspace allowlist、事件持久化，以及 no-PTY/no-arbitrary-shell 边界。
- V1.1 增加 Claude、Codex、OpenCode adapter diagnostics、shortcut API、run filter、设备撤销和 diff summary。
- V1.2 增加 workspace 串行任务队列、adapter profile、Git status/diff endpoint 和 command template。
- V1.3 增加 health/version 元数据、脱敏 diagnostics export、开发模式 smoke endpoint 和发布准备相关模型。
- 当前 conversation 工作重点是 Claude/Codex session lifecycle、resume 行为、隐藏 lifecycle event，以及适合移动端阅读的事件渲染。

## 安全注意事项

不要提交 token、pairing secret、SQLite 运行时数据、`.omx/`、构建产物或手工 smoke artifact。CLI 执行必须保持在已授权 workspace path 内，并保留围绕 cwd、权限、stdin handling、事件重放和协议过滤的测试。
