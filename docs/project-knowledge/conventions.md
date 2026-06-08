# Conventions

- Status: active seed
- Last verified: 2026-06-08

## Editing

- Use `apply_patch` for manual source edits.
- Treat repo source/docs/tests as UTF-8.
- On Windows, avoid `Set-Content`, `Out-File`, or shell redirection for source
  rewrites unless UTF-8 without BOM is explicitly preserved and verified.
- Do not revert changes you did not make unless the user explicitly asks.
- Keep edits scoped to the requested module and established local patterns.

## Git

- Commit messages default to English unless the user explicitly asks for another
  language.
- If the user says `提交代码`, make a real commit attempt after verification.
- If the user asks to push, push after committing relevant local changes.
- `docs/` is ignored in this repo; use `git add -f` for intentional docs.

## Daemon Security

- Workspace path guards must enforce both lexical containment and real
  filesystem containment. For existing targets, compare `realpath(root)` and
  `realpath(target)`. For writes to new paths, validate the closest existing
  parent by realpath so symlinked directories cannot escape the authorized
  workspace. Regression coverage: `workspace inspector rejects symlinked files
  outside workspace` and `Codex app-server workspace path guard rejects symlink
  targets outside workspace`.

## Flutter

- Keep `main.dart` thin and use `src/app/` as composition root.
- Prefer ViewModel state snapshots and repository/use-case injection over direct
  concrete service calls from widgets.
- Keep pages thin. Do not pack a page widget and many meaningful child
  components into one file; move reusable or section-level UI into files near
  the owning UI area, typically a local `widgets/` directory, and keep
  presentation aggregation in the page.
- Long-running async `ChangeNotifier` flows must guard disposal before
  `notifyListeners`; disposal should cancel or suppress pending emissions.
- Fire-and-forget async work must consume Future errors after projecting failure
  into state; otherwise the same failure can surface as an unhandled async
  exception.
- ViewModel state `copyWith` methods with nullable fields need explicit clear
  semantics; `value ?? previousValue` silently preserves stale optional state.
- Local `ConversationSummary` status projections should use
  `ConversationSummary.copyWithStatus` so requested/effective adapter metadata,
  fallback notices, and capability maps stay intact.
- Active conversation controls that depend on adapter capabilities, such as
  model and attachment handling, should resolve status through
  `effectiveAdapter`; UI labels may still show the requested adapter. Fallback
  conversations keep `adapter` as the requested value while daemon dispatch uses
  `effectiveAdapter`.
- Adapter listing responses should expose a safe top-level `version` for mobile
  display when the adapter can determine one. Diagnostics may also include
  provider health/version details, but mobile picker rows read
  `AdapterStatus.version`.
- Conversation message clients should preserve `clientMessageId` and
  `capabilityVersion` on JSON and multipart sends. JSON sends must omit the
  `attachments` key; the daemon reserves attachments for multipart/form-data.
- OpenCode `system.notice` events with `visible: true` need explicit mobile
  notice-card localization. Provider telemetry notices should stay
  `visible: false` instead of surfacing raw event names such as
  `OpenCode event: session.diff`.
- Add focused widget/unit tests for user-visible UI behavior and reducer state.
- Before claiming architecture-sensitive Flutter work is complete, run
  `dart run tool\check_architecture_imports.dart` plus the relevant analyze/test
  target, or clearly state why it could not be run.

## UI Taste

- Dark, restrained, precise, and polished.
- Avoid oversized marketing-style layouts in operational tools.
- Use existing design primitives and local theme values.
- For workbench transcript behavior, prioritize repeated-use ergonomics over
  decorative motion.
