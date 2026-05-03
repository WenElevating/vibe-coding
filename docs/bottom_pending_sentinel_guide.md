# Bottom Pending Sentinel 动效指南

## 1. 正确结构

这版采用 Claude Code / Codex 风格的 **事件流 + 底部运行态**：

```text
Submitted Prompt
Assistant output
Tool call
Tool output
Diff summary
Pending Sentinel   ← 对话未结束时永远在最底部
Composer
```

核心规则：

> CLI 运行中，pending sentinel 始终是 timeline 最后一项；所有新输出都插入到它上方。

这和“等待首条消息的大卡片”不同，也和“头像 typing bubble”不同。

---

## 2. UI 组成

### 2.1 Timeline Item

用于承载真实事件：

```text
assistant.delta
tool.started
tool.output
diff.summary
approval.required
command_template.output
```

每个事件独立成小卡片，不使用头像。

### 2.2 Pending Sentinel

固定在事件流末尾：

```text
spinner + Claude Code 正在运行 + 当前阶段 + pulse bars
```

示例：

```text
◌ Claude Code 正在运行
  正在读取 auth_service.dart…
```

### 2.3 Composer

Composer 在 sentinel 下方。

运行中时：

```text
运行中，输入将作为后续指令排队…
```

或者直接禁用输入。

---

## 3. 行为规则

### 3.1 新事件到达

不要替换 pending sentinel。

而是：

```text
insert event before pending sentinel
scroll to bottom
pending sentinel 更新状态文案
```

伪代码：

```ts
timeline.insertBefore(newEventCard, pendingSentinel);
pendingSentinel.status = nextStatus;
scrollToBottom();
```

### 3.2 任务继续运行

pending sentinel 保留。

```text
tool.started -> 插入 tool card
tool.output -> 插入 output card
assistant.delta -> 合并或插入 assistant card
diff.summary -> 插入 diff card
pending sentinel 仍在底部
```

### 3.3 任务完成

pending sentinel 变成 compact completion row，或移除后插入 completed card。

推荐：

```text
pending sentinel -> Run completed · 12.4s
```

再 600–1000ms 后淡出。

### 3.4 任务失败

pending sentinel 变成 error row。

```text
Codex 执行失败
查看 stderr / 重试 / 切换 adapter
```

---

## 4. Flutter 实现建议

## 4.1 数据结构

把 pending sentinel 当成 UI 层固定尾项，不写入后端事件列表。

```dart
final events = <RunEvent>[];
final isRunning = run.status == RunStatus.running;
```

渲染时：

```dart
ListView.builder(
  controller: scrollController,
  itemCount: events.length + (isRunning ? 1 : 0),
  itemBuilder: (context, index) {
    if (index == events.length && isRunning) {
      return PendingSentinel(
        adapter: run.adapter,
        statusText: run.currentStatusText,
      );
    }

    return RunEventCard(event: events[index]);
  },
)
```

---

## 4.2 用 AnimatedList 插入事件

Flutter 的 `AnimatedList` 支持在插入或删除 item 时播放动画，适合 CLI 事件流。  
新事件到达时：

```dart
events.add(event);
listKey.currentState?.insertItem(events.length - 1);
scrollToBottom();
```

注意：pending sentinel 不进入 `events`，否则插入 index 会混乱。

---

## 4.3 PendingSentinel Widget

```dart
class PendingSentinel extends StatelessWidget {
  const PendingSentinel({
    super.key,
    required this.adapter,
    required this.statusText,
  });

  final String adapter;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.04),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$adapter 正在运行'),
                Text(statusText),
              ],
            ),
          ),
          const PulseBars(),
        ],
      ),
    );
  }
}
```

---

## 5. 状态文案

推荐使用真实 adapter 阶段：

```text
等待下一条事件…
正在读取文件…
正在修改测试…
正在运行命令模板…
等待审批…
正在汇总 diff…
```

不要使用：

```text
AI 正在思考
小助手正在输入
机器人回复中
```

---

## 6. 动效参数

```text
event insert: 280–380ms
pending spinner: 800ms linear
pulse bars: 700–900ms
scroll to bottom: 220–320ms
completion fade: 600–1000ms
```

Material Design 的 indeterminate progress 适合进度和等待时间未知的任务；CLI 等待下一条事件就是未知时长。  
Flutter 的 AnimatedList 可以在插入 item 时播放动画，因此比手写整个 timeline 的动画更适合这里。

---

## 7. 边界情况

### 7.1 事件很频繁

合并同类型事件：

```text
assistant.delta 合并为一张 assistant card
tool.output 按 command 分组
raw_stdout 按 200–500ms buffer 合并
```

### 7.2 用户不在底部

如果用户向上滚动看历史，不要强制 scroll。

显示：

```text
3 条新事件
```

点击后滚到底部。

### 7.3 等待太久

pending sentinel 追加次级文案：

```text
已等待 28s · 可查看 raw stderr 或取消
```

---

## 8. Demo 文件

```text
bottom_pending_sentinel_demo.html
```

