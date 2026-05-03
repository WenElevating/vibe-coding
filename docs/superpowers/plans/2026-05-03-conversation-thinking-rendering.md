# Conversation Thinking Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Claude thinking content as a collapsible mobile message while keeping final assistant answers complete.

**Architecture:** Add `assistant.thinking` to the daemon conversation protocol and Claude conversation adapter. Extend the Flutter conversation reducer and workbench message rendering with a thinking role controlled by a setting that defaults collapsed.

**Tech Stack:** Node.js daemon, Flutter/Dart mobile UI, existing test suites.

---

## Tasks

### Task 1: Backend Thinking Event

- [ ] Add `ASSISTANT_THINKING: 'assistant.thinking'` to `daemon/src/conversation-protocol.js`.
- [ ] Add Node test using raw Claude assistant content with `thinking` and `text` blocks.
- [ ] Update `daemon/src/claude-conversation-adapter.js` to emit `assistant.thinking` and `assistant.partial` from assistant content blocks.
- [ ] Run `npm test`.

### Task 2: Flutter Reducer Thinking Role

- [ ] Add reducer tests for `assistant.thinking` and complete final `assistant.message`.
- [ ] Update `mobile/lib/src/state/conversation_reducer.dart` to preserve thinking separately.
- [ ] Run `flutter test test/conversation_reducer_test.dart`.

### Task 3: Workbench Thinking UI and Setting

- [ ] Add workbench setting/state for thinking expanded by default false.
- [ ] Map `ConversationMessage.role == 'thinking'` to a collapsible `思考过程` card.
- [ ] Ensure final assistant message is still rendered as normal Markdown.
- [ ] Run `flutter analyze` and `flutter test`.

### Task 4: Final Verification

- [ ] Run `npm test`.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter test`.
