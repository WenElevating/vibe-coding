# Mobile Review Remediation Design

Date: 2026-05-16

## Goal

Fix the full set of issues found in the mobile code review: security, stability, architecture boundaries, UI rendering performance, naming/maintainability concerns, and missing regression coverage.

The work will be delivered as small independently verifiable batches. Each batch should add or update regression tests before changing behavior where a practical test seam exists.

## Scope

In scope:

- Harden ASR model archive extraction, exception reporting, HTTP timeouts, stale client cleanup, and voice input lifecycle failure handling.
- Restore Flutter architecture boundaries across `domain`, `data`, `services`, `workflows`, `shell`, `app`, and `ui`.
- Improve workbench rendering for long conversations, markdown-heavy assistant messages, and large code/log blocks.
- Add targeted tests for architecture guards, daemon response parsing, ASR/voice lifecycle, page states, and notifier behavior.
- Keep public behavior and existing user flows unchanged unless a security warning is required.

Out of scope:

- A full redesign of the mobile UI.
- A full replacement of all protocol DTOs with domain models in one pass.
- New dependencies unless a later implementation plan explicitly justifies them and receives approval.
- Broad unrelated refactors outside the reviewed issue set.

## Delivery Strategy

Use five sequential phases:

0. Test infrastructure preparation.
1. Security and stability hardening.
2. Architecture boundary repair.
3. Workbench UI performance and rendering improvements.
4. Test coverage closeout and final verification.

Each phase should be independently reviewable, reversible, and verifiable. Prefer small commits per phase if commits are requested later.

Phase 0 exists to remove a planning contradiction: later phases require test-first work, so the test seams and fixture harnesses needed by those phases must exist before behavior changes begin.

## Approval and Ownership

Design approval means the product/engineering owner for this mobile remediation work has reviewed this spec and explicitly said the plan is acceptable in the chat or issue tracker. Implementation should not begin from this document alone.

- Approval owner role: mobile product/engineering owner or the repository maintainer acting in that role.
- Expected review window: before implementation planning starts in the current work session, or within one business day if reviewed asynchronously.
- Implementation plan owner: the coding agent or engineer assigned after approval.
- Implementation start: only after the design is approved and a separate implementation plan is written from this spec.

## Phase 0: Test Infrastructure Preparation

Phase 0 prepares test seams and fixtures required by the later test-first phases. It should not change production behavior except for adding injectable seams with current default implementations.

Requirements:

- Establish fake or mockable HTTP clients for daemon and ASR client tests.
- Establish fake permission, recorder, recognizer, and speech stream seams needed by ASR and voice lifecycle tests.
- Establish a temp-fixture harness for `mobile/tool/check_architecture_imports.dart`, including path normalization helpers for Windows-style paths.
- Confirm existing tests still pass after seam introduction.
- Phase 0 verification: run the existing relevant test suites after seam introduction; success means no existing behavior changed before hardening work begins.
- Rollback boundary: revert only the new test seam and fixture harness files/constructor additions; no behavior changes should depend on this phase yet.

## Phase 1: Security and Stability Hardening

### ASR ZIP Extraction

Replace direct archive extraction in `mobile/lib/src/services/asr_model_manager.dart` with a safe extraction routine.

Requirements:

- Iterate archive entries manually before writing files.
- Reject absolute paths, parent traversal, symlinks, and canonical destinations outside the staging directory.
- Enforce limits for uncompressed bytes and file count.
- Preserve the current staging/promote flow after validation succeeds.
- Add regression tests for path traversal, invalid entries, and successful extraction.

### Exception Redaction

Add a redaction boundary before exception diagnostics are sent to the daemon.

Requirements:

- Redact bearer tokens using an explicit case-insensitive `Authorization: Bearer <token>` / `Bearer <token>` matcher, where `<token>` is a contiguous non-whitespace credential segment.
- Redact key-value secrets only when the key name is secret-like, for example `api_key`, `apikey`, `access_token`, `refresh_token`, `password`, `secret`, or `token`; do not redact arbitrary UUIDs or hashes without a secret-like key.
- Strip URL query strings from `http://` and `https://` URLs before upload, replacing the query with a fixed redaction marker.
- Redact absolute Windows and POSIX user paths while preserving the basename or a relative workspace-safe suffix when useful.
- Define truncation thresholds as centralized code constants, initially `maxExceptionMessageChars = 4096`, `maxExceptionStackChars = 16384`, `maxExceptionMetadataChars = 8192`, and `maxExceptionMetadataEntries = 32`.
- Prefer relative or hashed paths when path context is still useful.
- Add focused tests for bearer tokens, secret-like key/value pairs, UUID/hash false positives, Windows paths, POSIX paths, URL query stripping, base64-like tokens, and truncation thresholds.
- Document in code that client-side redaction is irreversible and favors secret safety over perfect diagnostics.

### HTTP Timeout and Cancellation

Introduce a shared request timeout strategy for daemon and ASR client calls.

Requirements:

- Apply initial default timeouts from centralized constants: connect/request timeout of 10 seconds for normal daemon calls and read/download inactivity timeout of 30 seconds for long-running ASR downloads, unless an endpoint already has a narrower explicit timeout.
- Ensure ASR downloads can stop promptly when cancellation is requested, including stalled or slow streams where practical.
- Expose a close/cancel path for clients that own HTTP resources.
- Add tests using fake or mock clients for timeout and cancellation behavior.

### Stale Client Cleanup

Prevent timed-out connection attempts from leaving active clients behind.

Requirements:

- Add `DaemonClient.close()` or an equivalent lifecycle hook.
- Close abandoned clients when a connection attempt is superseded or times out.
- Preserve source compatibility by making `close()` additive and idempotent; existing callers that never close should keep current behavior until they are migrated.
- The implementation plan must list known `DaemonClient` owners/callers that never close their client, mark which are migrated in this remediation, and record every remaining caller as a follow-up item before Phase 4 closes.
- Preserve current successful connection behavior.
- Add tests around late-completing connection attempts.

### Voice Start Failure Cleanup

Make `SpeechInputService.start()` internally exception-safe.

Requirements:

- Set `_started` only after stream/listener setup succeeds.
- On setup failure, call cleanup before rethrowing.
- Add tests for start failure, permission denial, cancel, stop, and dispose cleanup using fakes or injectable seams.

Rollback boundary for Phase 1: revert the security/stability helper changes and their tests as one batch. If only one hardening subtask fails, keep independently passing subtasks only when their tests and public behavior remain isolated.

## Phase 2: Architecture Boundary Repair

### Legal Dependency Direction

The architecture guard should use this dependency direction as the authoritative reference:

```text
main.dart
  -> app
app
  -> shell, workflows, data, domain, services, ui
shell
  -> workflows, data, domain, services, ui
ui/views
  -> ui/view_models, ui/core, domain models/contracts
ui/view_models
  -> domain models/contracts, domain use cases/workflow-facing interfaces
workflows
  -> domain contracts/models, data repositories, services when coordinating side effects
data/repositories
  -> domain contracts/models, data models, services
data/models
  -> protocol/raw API shapes only when explicitly data-owned
services
  -> external packages, platform APIs, raw protocol clients/models
domain
  -> domain only; no Flutter, UI, app, shell, workflows, services, concrete data implementations, HTTP clients, shared preferences, or testing imports
testing
  -> may import production code; production code must not import testing
```

Allowed exceptions must be explicit in `check_architecture_imports.dart`, named in tests, and documented here or in a follow-up architecture note. UI access to `DaemonClient` should be treated as a temporary allowlist during migration, not as the target dependency direction.

### Domain to Workflow Dependency

Move `WorkspaceCreationClient` ownership into the domain layer or remove the separate interface if `CreateWorkspaceWorkflow` can depend directly on `WorkspaceRepository`.

Requirements:

- `domain/repositories/workspace_repository.dart` must not import `workflows`.
- Workflow code may import domain contracts.
- Existing create-workspace behavior and tests must continue to pass.

### Domain to Shell Dependency

Replace `DaemonInitialData = AppSnapshot` with a domain-owned value type.

Requirements:

- `domain/models/daemon_initial_data.dart` must not import `shell`.
- Mapping from `AppSnapshot` to `DaemonInitialData` belongs in shell, app, data, or workflow composition code.
- Existing consumers should receive equivalent data after mapping.

### Protocol DTO Isolation

Reduce direct protocol leakage from domain contracts without attempting a full model rewrite.

Requirements:

- Prioritize `DashboardState` and high-frequency repository contracts flagged in review.
- Introduce domain-owned projections where behavior depends on model shape.
- Keep compatibility barrels only when preserving an intentional public import surface.
- Document any protocol DTOs intentionally left for later migration in a short section of the implementation plan. If the leftover is expected to survive this remediation, create one ADR under `docs/adr/` as the single durable record; do not split this inventory across multiple docs.

### UI Composition Boundary

Move connected dependency creation out of presentation widgets.

Requirements:

- `MainTabsPage` should not directly assemble `ConnectedDataDependencies` from `DaemonClient`.
- Prefer `AppDependencies` as the composition boundary for page-level dependency creation; use feature factories only when the dependency is feature-local and does not expose infrastructure types to the page.
- Minimize constructor churn by keeping grouped dependency objects.

### ViewModel Infrastructure Leakage

Hide concrete data repositories and concrete clients behind domain or workflow-facing interfaces where practical.

Requirements:

- Connection ViewModels should not directly import concrete data repository implementations.
- Concrete `DaemonClient` usage in UI should be limited to explicit composition boundaries or removed from UI contracts.
- Tests should verify ViewModels against abstractions or fakes.

### Architecture Guard Updates

Add regression coverage for architecture import rules.

Requirements:

- Test domain import bans for workflow, shell, protocol, services, UI, and testing where applicable.
- Test production import bans for `src/testing`.
- Test UI daemon-client allowlist behavior.
- Ensure the checker fails with useful output when rules are violated.

Rollback boundary for Phase 2: each boundary repair should be revertible by feature slice. Do not mix domain model migration, UI dependency construction changes, and architecture guard rule changes in the same commit unless the implementation plan proves they are inseparable.

## Phase 3: Workbench UI Performance and Rendering

### Quantitative Acceptance Targets

Use concrete thresholds so implementation and review share the same meaning of large renderable content. These thresholds apply to virtualized conversation rendering, markdown normalization, and large code/log rendering. `Lifecycle Guard` is a correctness/stability fix in this phase, not a performance threshold item.

- A conversation with 500 messages should not eagerly build all message cards during initial render; tests should verify lazy construction behavior where practical.
- A single assistant markdown message over 5,000 characters is considered large and should avoid repeated normalization on unrelated rebuilds.
- A code block or command output over 200 lines or 20,000 characters is considered large and should use capped or chunked rendering.
- Normal-sized content below those thresholds should preserve the current visual path unless the lazy path is behaviorally identical.
- No formal frame-rate target is required for this pass, but the implementation should reduce widget construction and text layout work in ways that are directly testable.

### Virtualized Conversation Rendering

Replace eager conversation message rendering with lazy rendering.

Requirements:

- Use `ListView.builder`, `SliverList`, or an equivalent lazy list.
- Preserve scroll-to-bottom behavior and back/navigation semantics.
- Add stable keys for message rows.
- Add tests or widget instrumentation proving non-visible messages are not eagerly built where practical.

### Markdown Normalization Cache

Remove repeated markdown normalization from hot rebuild paths.

Requirements:

- Prefer precomputing normalized markdown in message projection or reducer code.
- If precomputation creates excessive churn, use keyed memoization inside `AssistantMarkdownBody`.
- Add tests proving unrelated rebuilds do not repeatedly normalize unchanged markdown.

### Large Code and Log Rendering

Limit full layout work for large command outputs and code blocks.

Requirements:

- Avoid unconstrained full-payload `SelectableText` for large content as defined above.
- Constrain height and use chunked or capped rendering for large logs.
- Provide a clear path to inspect more content when content is capped.
- Preserve readability for normal-sized code blocks.

### Lifecycle Guard

Add `mounted` checks to post-frame scroll callbacks and review nearby controller lifecycle paths.

Requirements:

- A post-frame callback must not access disposed state or controllers.
- Existing controller disposal behavior should remain intact.

Rollback boundary for Phase 3: preserve the old message projection and rendering path until lazy rendering tests pass. If virtualization breaks scroll behavior, revert only the list/rendering changes while keeping independent lifecycle guards.

## Phase 4: Test Coverage Closeout

Phase 4 is no longer the first place where tests appear. It closes remaining coverage gaps after the test-first work in Phases 0-3 and adds page/notifier coverage that is not required as a prerequisite for security or architecture changes.

### Architecture Tool Tests

Add temp-fixture tests for `mobile/tool/check_architecture_imports.dart`.

Coverage:

- Domain boundary violations.
- UI core and services boundary rules.
- Production code importing testing helpers.
- Daemon client allowlist cases.
- Windows-style and normalized paths.

### Daemon Client Parsing Tests

Add table-driven tests for daemon response parsing.

Coverage:

- `listAdapters`, `listShortcuts`, `listCommandTemplates`, `listQueue`, `gitDiff`, `listRuns`, `fetchEvents`, and conversation APIs.
- Successful responses.
- Missing keys, malformed collection values, and invalid item shapes.
- Error messages should be typed and actionable rather than raw cast failures.

### ASR and Voice Tests

Add lifecycle tests around ASR model and speech input services.

Phase 1 covers the core lifecycle seam tests needed for test-first hardening. Phase 4 adds integration-style and edge-case coverage beyond those seam tests, and verifies that the seams still represent production behavior after all phases.

Coverage:

- Permission denied.
- Start setup failure cleanup.
- Partial callback behavior.
- Stop finalization.
- Cancel and dispose cleanup.
- Download cancellation and invalid archive handling.

### Page State Widget Tests

Add focused widget tests for page states.

Coverage:

- `AdaptersPage`: populated, empty, unavailable, and back action.
- `RunsPage`: empty, populated rows, and detail callback.
- `QueuePage`: empty, populated rows, and callback behavior.
- `DiagnosticsPage`: loading, error, success bundle path, disabled loading action, and back action.

### Notifier Tests

Add small unit tests for simple ViewModels.

Coverage:

- `AdaptersViewModel` update behavior.
- `SessionListViewModel` update behavior.
- Listener notification counts.
- No unintended mutation of exposed state.

## Verification Matrix

Run focused verification after each phase, then full mobile verification at the end. The implementation plan must specify intermediate verification commands for each phase; this design only defines the minimum final verification floor.

Minimum final commands:

```powershell
cd mobile
dart run tool/check_architecture_imports.dart
flutter analyze
flutter test
```

Additional focused tests should be run as each phase changes files. If a command times out, capture the timeout, retry with a narrower target, and record any remaining verification gap.

## Risks and Mitigations

- Risk: Architecture cleanup grows into a full domain model rewrite. Mitigation: only migrate models needed for reviewed issues and document leftovers.
- Risk: Lazy list changes break scroll-to-bottom behavior. Mitigation: add targeted widget tests around message append and system back behavior.
- Risk: Safe ZIP extraction rejects legitimate archive structure. Mitigation: test current expected ASR archive layout and preserve staging/promote semantics.
- Risk: Redaction removes useful diagnostics. Mitigation: keep error category, relative context, and capped stack frames while stripping secrets and private paths.
- Risk: Redaction rules either miss unusual secrets or falsely redact useful identifiers such as UUIDs and hashes. Mitigation: use key-aware matching, explicit bearer-token matching, boundary-case tests, and centralized constants instead of scattered ad hoc regexes.
- Risk: Client-side redaction is irreversible and may reduce support/debugging value. Mitigation: document this tradeoff, preserve non-sensitive categories and capped stack context, and prefer opt-in server-side raw diagnostics only if a future security review approves it.
- Risk: Timeout changes break slow local daemons. Mitigation: choose conservative defaults and keep timeout values configurable within code-level constants.
- Risk: Phase sequencing drifts into test-after implementation. Mitigation: Phase 0 must land test seams first, and each later phase must list its test-first checks in the implementation plan before code edits.

## Implementation Handoff

After the approval owner approves this design, create a detailed implementation plan with small tasks grouped by phase. The plan should identify files touched, test-first steps, verification commands, owner for each phase, expected start point, and rollback boundaries for each phase.
