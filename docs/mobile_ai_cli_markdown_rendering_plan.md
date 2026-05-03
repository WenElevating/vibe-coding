# 移动端 AI CLI Markdown 渲染方案

## 0. 结论

当前问题不是视觉设计，而是 **assistant.message 没有经过 Markdown 渲染**。

截图里这类内容还原样显示：

```md
- **编码和调试代码**
- **阅读和分析文件**
- **执行命令行操作**
```

说明现在大概率是：

```dart
Text(event.payload.text)
```

正确方案是：

```text
只对 assistant.message / assistant.delta 聚合文本使用 Markdown 渲染；
tool call / diff / approval / console output 继续使用原生 Flutter 组件。
```

不要把整个 timeline 都交给 Markdown renderer。

---

## 1. 设计目标

1. 正确渲染 Claude Code / Codex / OpenCode 输出的常见 Markdown。
2. 不破坏当前 CLI 事件流 UI。
3. 不把 tool call、diff、approval 渲染成普通文本。
4. 移动端要紧凑、克制、可读。
5. 代码块、列表、粗体、inline code 必须好看。
6. 不允许 raw HTML、图片、iframe、script 等危险内容。
7. 长输出要可折叠，不能撑爆 timeline。
8. 后续可以支持代码高亮和复制按钮。

---

## 2. 总体架构

### 2.1 事件分流

```text
RunTimeline
├─ assistant.message     -> Markdown 渲染
├─ assistant.delta       -> 先聚合，再 Markdown 渲染
├─ tool.started          -> ToolCallCard
├─ tool.output           -> ToolOutputCard / ConsoleBlock
├─ diff.summary          -> DiffSummaryCard
├─ approval.required     -> ApprovalCard
├─ adapter.raw_stdout    -> RawConsoleBlock
├─ adapter.raw_stderr    -> RawConsoleBlock
├─ adapter.parse_error   -> ParserWarningCard
└─ pending sentinel      -> PendingSentinel
```

### 2.2 不要做的事情

不要：

```dart
MarkdownBody(data: wholeTimelineText)
```

不要：

```dart
Text(assistantMessage)
```

不要：

```dart
WebView(html: markdownToHtml(text))
```

不要：

```dart
HtmlWidget(rawModelOutput)
```

---

## 3. 推荐依赖

### 3.1 V1 推荐：flutter_markdown

优点：

- 成熟。
- `MarkdownBody` 是非滚动组件，适合放进你自己的 `ListView` / timeline card。
- 支持 GitHub Flavored Markdown。
- API 简单，落地快。

```yaml
dependencies:
  flutter_markdown: ^0.7.0
```

### 3.2 V2 可选：markdown_widget

适合后续需要：

- 代码高亮。
- TOC。
- 更强的自定义节点。
- 复杂 Markdown 扩展。

```yaml
dependencies:
  markdown_widget: ^2.3.0
```

### 3.3 当前建议

先用：

```text
flutter_markdown + MarkdownBody + 自定义 MarkdownStyleSheet
```

等第一版稳定后，再评估是否切到 `markdown_widget`。

---

## 4. AssistantMessageCard 结构

```text
AssistantMessageCard
├─ Header
│  ├─ Claude / Codex / OpenCode
│  └─ assistant.message · 14:33
├─ AssistantMarkdownBody
└─ Footer Actions
   ├─ Copy
   ├─ Collapse
   └─ Create Follow-up
```

示例 Flutter：

```dart
class AssistantMessageCard extends StatelessWidget {
  const AssistantMessageCard({
    super.key,
    required this.adapterLabel,
    required this.markdown,
    required this.createdAtLabel,
  });

  final String adapterLabel;
  final String markdown;
  final String createdAtLabel;

  @override
  Widget build(BuildContext context) {
    return TimelineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AssistantCardHeader(
            adapterLabel: adapterLabel,
            createdAtLabel: createdAtLabel,
          ),
          const SizedBox(height: 8),
          AssistantMarkdownBody(markdown: markdown),
          const SizedBox(height: 10),
          AssistantMessageActions(markdown: markdown),
        ],
      ),
    );
  }
}
```

---

## 5. MarkdownBody 封装

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AssistantMarkdownBody extends StatelessWidget {
  const AssistantMarkdownBody({
    super.key,
    required this.markdown,
  });

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final data = normalizeAssistantMarkdown(markdown);

    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: buildAssistantMarkdownStyleSheet(context),
      onTapLink: (text, href, title) {
        // V1：不要直接打开链接，弹确认。
        // showExternalLinkConfirmDialog(context, href);
      },
      imageBuilder: (uri, title, alt) {
        // V1：禁用图片，防止远程资源加载和布局撑爆。
        return const SizedBox.shrink();
      },
    );
  }
}
```

---

## 6. Markdown 样式

目标：**更像开发工具，不像博客文章。**

```dart
MarkdownStyleSheet buildAssistantMarkdownStyleSheet(BuildContext context) {
  const text = Color(0xFFDCE5F3);
  const muted = Color(0xFF8A96A8);
  const strong = Color(0xFFF2F5FB);
  const mint = Color(0xFF68D8B3);
  const codeBg = Color(0x22000000);
  const codeBorder = Color(0x14FFFFFF);

  return MarkdownStyleSheet(
    p: const TextStyle(
      fontSize: 13.5,
      height: 1.55,
      color: text,
      letterSpacing: -0.1,
    ),
    strong: const TextStyle(
      fontSize: 13.5,
      height: 1.55,
      fontWeight: FontWeight.w750,
      color: strong,
    ),
    em: const TextStyle(
      fontStyle: FontStyle.italic,
      color: muted,
    ),
    listBullet: const TextStyle(
      fontSize: 13.5,
      height: 1.45,
      color: mint,
    ),
    blockSpacing: 10,
    listIndent: 18,
    listBulletPadding: const EdgeInsets.only(right: 6),

    h1: const TextStyle(
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w800,
      color: strong,
    ),
    h2: const TextStyle(
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w800,
      color: strong,
    ),
    h3: const TextStyle(
      fontSize: 14,
      height: 1.35,
      fontWeight: FontWeight.w750,
      color: strong,
    ),

    code: const TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.2,
      height: 1.45,
      color: Color(0xFFA8F5D4),
      backgroundColor: codeBg,
    ),
    codeblockPadding: const EdgeInsets.all(10),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF070A0F),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: codeBorder),
    ),

    blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    blockquoteDecoration: BoxDecoration(
      color: const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(
          color: mint,
          width: 2,
        ),
      ),
    ),
  );
}
```

---

## 7. Markdown 清洗与 Normalize

AI CLI 输出常见问题：

- 中文冒号后直接跟列表。
- 多个空行。
- 列表前缺空行。
- Windows 换行。
- 模型输出 raw HTML。
- 模型输出超长 heading。
- 表格过宽。

需要在渲染前做轻量 normalize。

```dart
String normalizeAssistantMarkdown(String input) {
  var text = input.trim();

  // 统一换行
  text = text.replaceAll('\r\n', '\n');

  // 去除不可见控制字符，保留 \n 和 \t
  text = text.replaceAll(
    RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),
    '',
  );

  // 中文/英文冒号后紧接列表时补空行
  text = text.replaceAllMapped(
    RegExp(r'([：:])\n(- |\* |\+ |\d+\. )'),
    (m) => '${m.group(1)}\n\n${m.group(2)}',
  );

  // 过多空行压缩
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  // V1 禁用危险 HTML 片段
  text = text
      .replaceAll('<script', '&lt;script')
      .replaceAll('</script', '&lt;/script')
      .replaceAll('<iframe', '&lt;iframe')
      .replaceAll('</iframe', '&lt;/iframe');

  return text;
}
```

---

## 8. 支持的 Markdown 子集

V1 只支持这些：

| 类型 | 支持 | 说明 |
|---|---:|---|
| paragraph | yes | 主体文本 |
| bold | yes | 重点信息 |
| italic | yes | 次级强调 |
| bullet list | yes | 常见模型输出 |
| ordered list | yes | 步骤 |
| inline code | yes | 文件名、函数名、命令 |
| fenced code block | yes | 代码片段 |
| blockquote | yes | 备注/引用 |
| heading | limited | 降级字号 |
| table | partial | V1 建议转横向滚动或降级 |
| link | confirm | 点击前确认 |
| image | no | 禁用 |
| raw HTML | no | 禁用 |
| task list | optional | 可后续支持 |

---

## 9. 表格处理策略

Markdown 表格在移动端最容易炸布局。

### V1 推荐

表格不要直接渲染成宽表。改成：

```text
TableDetectedCard
  - 表格内容已折叠
  - 查看详情
  - 复制 Markdown
```

或转成 key-value card。

### 简单检测

```dart
bool looksLikeMarkdownTable(String text) {
  final lines = text.split('\n');
  for (var i = 0; i < lines.length - 1; i++) {
    final current = lines[i];
    final next = lines[i + 1];

    final hasPipes = current.contains('|') && next.contains('|');
    final isSeparator = RegExp(r'^\s*\|?\s*:?-{3,}:?\s*\|').hasMatch(next);

    if (hasPipes && isSeparator) return true;
  }
  return false;
}
```

### V1 处理

```dart
if (looksLikeMarkdownTable(markdown)) {
  return CollapsedMarkdownTable(markdown: markdown);
}
```

---

## 10. 代码块处理策略

默认 `MarkdownBody` 的 code block 可以先用，但建议 V1.1 做自定义代码块：

```text
CodeBlock
├─ Header
│  ├─ language
│  └─ Copy
└─ horizontal scroll code
```

样式：

```text
font: monospace
font size: 12
max height: 220
horizontal scroll: true
copy button: true
```

---

## 11. assistant.delta 聚合策略

不要每个 delta 都渲染一次 Markdown，否则性能和视觉都差。

### 推荐

```text
assistant.delta
assistant.delta
assistant.delta
    ↓ buffer
每 80–150ms 合并刷新一次
    ↓
AssistantStreamingMarkdownBlock
```

### 示例

```dart
class DeltaBuffer {
  final _buffer = StringBuffer();
  Timer? _timer;

  void add(String delta, void Function(String text) onFlush) {
    _buffer.write(delta);

    _timer ??= Timer(const Duration(milliseconds: 120), () {
      _timer = null;
      onFlush(_buffer.toString());
    });
  }

  String finish() {
    final text = _buffer.toString();
    _buffer.clear();
    _timer?.cancel();
    _timer = null;
    return text;
  }
}
```

---

## 12. 长内容折叠

assistant.message 很长时，不要直接撑满整个页面。

规则：

```text
超过 900 字符：默认显示前 520 字符 + 展开
超过 25 行：默认折叠
代码块超过 220px：内部滚动
```

示例：

```dart
class CollapsibleMarkdown extends StatefulWidget {
  const CollapsibleMarkdown({
    super.key,
    required this.markdown,
  });

  final String markdown;

  @override
  State<CollapsibleMarkdown> createState() => _CollapsibleMarkdownState();
}

class _CollapsibleMarkdownState extends State<CollapsibleMarkdown> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final shouldCollapse = widget.markdown.length > 900;
    final visible = !shouldCollapse || expanded
        ? widget.markdown
        : '${widget.markdown.substring(0, 520)}\n\n…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssistantMarkdownBody(markdown: visible),
        if (shouldCollapse)
          TextButton(
            onPressed: () => setState(() => expanded = !expanded),
            child: Text(expanded ? '收起' : '展开完整回复'),
          ),
      ],
    );
  }
}
```

---

## 13. 安全策略

### 13.1 禁用 raw HTML

AI 输出是外部模型内容，不能信任。

即使 Flutter 不是浏览器，也不要引入 WebView / HTML renderer 去渲染模型输出。

### 13.2 链接点击前确认

```dart
onTapLink: (text, href, title) {
  if (href == null) return;
  showDialog(
    context: context,
    builder: (_) => ExternalLinkConfirmDialog(url: href),
  );
}
```

### 13.3 禁用远程图片

```dart
imageBuilder: (_, __, ___) => const SizedBox.shrink()
```

### 13.4 日志不要记录完整 Markdown

尤其不要把模型输出里的 secrets、env、token 写进移动端日志。

---

## 14. Event Renderer 分发代码

```dart
Widget buildRunEventCard(RunEvent event) {
  switch (event.type) {
    case 'assistant.message':
      return AssistantMessageCard(
        adapterLabel: event.adapterLabel,
        markdown: event.payload.text,
        createdAtLabel: event.createdAtLabel,
      );

    case 'assistant.delta':
      // delta 不直接单独渲染，应由 streaming accumulator 聚合。
      return const SizedBox.shrink();

    case 'tool.started':
      return ToolCallCard(event: event);

    case 'tool.output':
      return ToolOutputCard(event: event);

    case 'diff.summary':
      return DiffSummaryCard(event: event);

    case 'approval.required':
      return ApprovalCard(event: event);

    case 'adapter.raw_stdout':
      return RawConsoleBlock(
        stream: 'stdout',
        text: event.payload.text,
      );

    case 'adapter.raw_stderr':
      return RawConsoleBlock(
        stream: 'stderr',
        text: event.payload.text,
      );

    default:
      return UnknownEventCard(event: event);
  }
}
```

---

## 15. 推荐实施步骤

### Step 1：接入 flutter_markdown

目标：

```text
assistant.message 能正确渲染 bold / list / code
```

改动：

```text
Text(event.payload.text)
  -> AssistantMarkdownBody(markdown: event.payload.text)
```

### Step 2：加 MarkdownStyleSheet

目标：

```text
让 Markdown 视觉和当前深色 UI 统一
```

### Step 3：加 normalizeAssistantMarkdown

目标：

```text
修复列表、空行、Windows 换行和 raw HTML
```

### Step 4：区分事件类型

目标：

```text
Markdown 只渲染 assistant 文本
tool/diff/approval 全部原生卡片
```

### Step 5：处理 streaming delta

目标：

```text
delta 聚合后再渲染
避免每 token 重建 Markdown 树
```

### Step 6：代码块和表格优化

目标：

```text
代码块可复制
表格不撑爆移动端
```

---

## 16. 验收标准

### Markdown 正确性

- `**bold**` 渲染为粗体。
- `- item` 渲染为列表。
- `` `inline code` `` 渲染为 inline code。
- fenced code block 渲染为代码块。
- raw HTML 不被执行。
- 图片不加载。
- 链接点击前确认。

### UI 一致性

- Markdown 字号和 timeline row 一致。
- heading 不会过大。
- 列表缩进不超过 18px。
- 代码块不会横向撑爆。
- 长文本可折叠。

### 架构一致性

- tool call 不进入 MarkdownBody。
- diff summary 不进入 MarkdownBody。
- approval 不进入 MarkdownBody。
- console output 使用 monospace raw block。
- pending sentinel 永远在 timeline 底部。

---

## 17. 推荐最终技术选型

```text
V1:
flutter_markdown
MarkdownBody
自定义 MarkdownStyleSheet
normalizeAssistantMarkdown
assistant.message only

V1.1:
自定义 code block
copy button
collapsed table
streaming delta buffer

V2:
markdown_widget
code highlighting
custom syntax nodes
advanced table renderer
```

---

## 18. 参考资料

- flutter_markdown MarkdownBody:
  - https://pub.dev/documentation/flutter_markdown/latest/flutter_markdown/MarkdownBody-class.html
- markdown_widget:
  - https://pub.dev/packages/markdown_widget
- Flutter AnimatedList:
  - https://api.flutter.dev/flutter/widgets/AnimatedList-class.html
- OWASP XSS Prevention Cheat Sheet:
  - https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
