# Decision: Workbench Transcript Is Bottom Anchored

- Status: verified
- Date: 2026-05-22
- Last verified: 2026-05-22

## Context

Opening an existing conversation could show the transcript above the latest
message. A post-frame `jumpTo(maxScrollExtent)` can run before a lazy
`ListView.builder` has a stable extent, especially with historical tool/code
blocks.

## Decision

Render the workbench transcript with `ListView.builder(reverse: true)` and map
builder indexes back to the original logical message order. The latest message
becomes the natural initial visual anchor. `_scrollToBottom()` targets
`minScrollExtent`.

The ViewModel keeps logical message order. Only the UI rendering layer is
inverted.

## Alternatives

- Repeated frame-following jumps to `maxScrollExtent`: rejected because it
  eventually corrects position but can still show a visible correction after
  entry.
- Reverse message order in ViewModel: rejected because it mixes presentation
  anchoring into state projection.

## Evidence

- Commit: `2fea5d8 Anchor conversation transcript at latest message`
- Files:
  - [coding_workbench_page.dart](../../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart)
  - [widget_test.dart](../../../mobile/test/widget_test.dart)

## Verification

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "opening existing conversation scrolls to latest message"
dart analyze lib\src\ui\features\workbench\coding_workbench_page.dart test\widget_test.dart
```

## Re-evaluate When

- The transcript moves to a virtualized chat list package.
- The UI adds bidirectional pagination or prepend-history loading.
- Reverse rendering causes accessibility, keyboard navigation, or semantic order
  problems.
