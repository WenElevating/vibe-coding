# Decision: Conversation Title Is Daemon-Owned Metadata

- Status: verified
- Date: 2026-05-22
- Last verified: 2026-05-22

## Context

Conversation list rows were showing UUID-like labels, and conversation detail
titles could change after later messages. The desired behavior is a stable title
based on the first real user input.

## Decision

Persist `conversation.title` on the daemon. Derive it from the first committed
real user message when the title is empty. Backfill existing SQLite
conversations from their first `user.message`. Mobile consumes the title and
only falls back for missing/legacy data.

`cliSessionId` remains an adapter resume token and must not drive display title.

## Alternatives

- Mobile-only title derived from visible messages: rejected because detail title
  can drift as messages change and session list lacks a stable authority.
- Use `cliSessionId` or UUID labels: rejected because they are implementation
  identifiers, not product copy.

## Evidence

- Commit: `19d80fb Persist stable conversation titles`
- Files:
  - [conversation-title.js](../../../daemon/src/conversation-title.js)
  - [conversation-manager.js](../../../daemon/src/conversation-manager.js)
  - [app-sqlite-store.js](../../../daemon/src/app-sqlite-store.js)
  - [conversation_models.dart](../../../mobile/lib/src/data/models/conversation_models.dart)
  - [coding_session_list_page.dart](../../../mobile/lib/src/ui/features/sessions/coding_session_list_page.dart)
  - [coding_workbench_page.dart](../../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart)

## Verification

```powershell
node scripts/run-tests.js
cd mobile
flutter test --no-pub test\daemon_client_test.dart test\widget_test.dart -r expanded --plain-name "stable conversation title"
dart run tool\check_architecture_imports.dart
```

## Re-evaluate When

- Conversation titles need model/provider-generated summaries.
- The daemon exposes user-editable conversation titles.
- The product introduces multi-user collaborative title editing.
