# Decision: Existing Workbench Transcripts Are Bottom Anchored

- Status: active; runtime verification pending for the 2026-05-22 scope refinement
- Date: 2026-05-22
- Last verified: 2026-05-22

## Context

Opening an existing conversation could show the transcript above the latest
message. A post-frame `jumpTo(maxScrollExtent)` can run before a lazy
`ListView.builder` has a stable extent, especially with historical tool/code
blocks.

## Decision

When opening an existing session from the session list, render the workbench
transcript with `ListView.builder(reverse: true)` and map builder indexes back
to the original logical message order. The latest message becomes the natural
initial visual anchor. `_scrollToBottom()` targets `minScrollExtent` for this
mode.

If the reversed transcript does not overflow its viewport, switch that render
pass back to normal order. This prevents short existing conversations from
floating above the composer with a large empty band at the top. If later content
grows enough to overflow, the UI can resume reverse rendering for bottom
anchoring.

Brand-new conversations should not use reverse rendering while the transcript is
short. They render in normal order so the first prompt, status row, and running
card begin near the top of the transcript area instead of floating above the
composer. For normal-order live transcripts, `_scrollToBottom()` targets
`maxScrollExtent`.

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
- Scope refinement: `CodingWorkbenchPageState._bottomAnchorTranscript` is set
  only when opening an existing session; new sessions keep normal transcript
  order.
- Underflow refinement: `CodingWorkbenchPageState._bottomAnchorTranscriptUnderflow`
  disables reverse rendering when the existing-session transcript has no scroll
  overflow.
- Files:
  - [coding_workbench_page.dart](../../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart)
  - [widget_test.dart](../../../mobile/test/widget_test.dart)

## Verification

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "opening existing conversation scrolls to latest message"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "opening short existing conversation keeps transcript near top"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "new conversation keeps short transcript near top while running"
dart analyze lib\src\ui\features\workbench\coding_workbench_page.dart test\widget_test.dart
```

Agent caveat on 2026-05-22: the targeted Flutter test and the targeted Dart
analysis command both timed out after 120 seconds in Codex. The short existing
conversation test also timed out after 120 seconds in Codex when added for the
underflow refinement. Re-run the commands manually before treating the scope
refinement as runtime-verified.

## Re-evaluate When

- The transcript moves to a virtualized chat list package.
- The UI adds bidirectional pagination or prepend-history loading.
- Reverse rendering causes accessibility, keyboard navigation, or semantic order
  problems.
