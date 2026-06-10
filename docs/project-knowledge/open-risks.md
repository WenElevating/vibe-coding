# Open Risks

- Status: active seed
- Last verified: 2026-05-22

## Risk: Local Flutter/Dart Commands May Timeout In Agent Runs

- Level: medium
- Impact: agent cannot always independently verify mobile changes.
- Evidence: targeted `flutter test` and `dart format` commands timed out in
  agent runs while the user later ran equivalent commands successfully.
- Mitigation: stop after first timeout, provide the exact mirror-configured
  command, and rely on user-run output only when explicitly provided.
- Related: [build-and-test.md](build-and-test.md)

## Risk: Project Knowledge Can Drift

- Level: medium
- Impact: agents may trust stale architecture or troubleshooting entries.
- Mitigation: every active entry carries `Last verified`; run
  `node scripts/check-project-knowledge.js` for cheap structural checks.
- Re-evaluate when: stale-date checks move from manual review to automation.

## Risk: Docs Are Ignored By Default

- Level: low
- Impact: intentional docs under `docs/` do not appear in normal `git status`.
- Evidence: `.gitignore` ignores `docs/`.
- Mitigation: use `git add -f` for intentional docs commits.

## Risk: Connection Bootstrap Perf Marks Need A Pre-Reporter Boundary

- Level: low
- Impact: `app.main.started` and `app.first_frame` use the two-slot startup
  buffer, but `daemon.health.loaded` and `workspace.list.loaded` occur during
  daemon connection before `MainPage` creates `PerformanceTraceReporter`.
  Recording those marks with exact timestamps needs an explicit connection
  bootstrap buffer or a narrower definition that records when data becomes
  available to the connected UI.
- Evidence: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart`
  loads health and initial data before `mobile/lib/src/ui/main/main_page.dart`
  creates the reporter; `docs/superpowers/specs/2026-06-06-performance-tracing-design.md`
  lists the marks, while the implementation intentionally keeps the startup
  buffer limited to two startup marks.
- Mitigation: do not expand the startup buffer casually. Add a dedicated
  connection bootstrap trace handoff if analysis later requires exact health
  and workspace-list timing.
- Last verified: 2026-06-07

## Risk: Codex App-Server Migration Is Not A Drop-In Adapter Swap

- Level: medium
- Impact: Codex mobile approval can be implemented through app-server, but a
  production default-route migration still needs conservative rollout and real
  file-change/permissions approval smoke evidence.
- Evidence: `daemon/src/codex-app-server-bridge.js` and
  `daemon/src/codex-app-server-conversation-adapter.js` validate
  protocol/request/event parity, fallback boundaries, lifecycle cleanup,
  approval timeout behavior, and structured provider session persistence.
  `docs/superpowers/fixtures/codex-app-server/smoke-report-2026-06-03.md`
  records real stdio smoke against installed `codex app-server`, including
  command approval, resume/rejoin with persisted thread id, and native
  `localImage` input.
- Mitigation: keep `codex-app-server` behind
  `CODEX_APP_SERVER_ENABLED=1`, `CODEX_APP_SERVER_EXPERIMENTAL_API=1`,
  stdio transport, and `CODEX_APP_SERVER_ROLLOUT_PERCENT>0`; keep
  `thread/start` and `thread/resume` read-only, and require remaining
  file-change/permissions approval smoke before making it the default `codex`
  route.
- Related: `docs/superpowers/specs/2026-06-03-codex-app-server-adapter-design.md`
- Last verified: 2026-06-03

## Risk: OpenCode Prompt Dispatch Can Race Provider Events

- Level: medium
- Impact: `opencode serve` emits turn events on the shared `/global/event`
  stream. If the daemon sends `prompt_async` before the SSE subscription is
  actually open, early `session.idle`, `permission.asked`, or error events can
  be missed and leave a conversation running or waiting incorrectly.
- Evidence: `daemon/src/opencode-server-client.js` exposes
  `subscription.opened`; `daemon/src/opencode-conversation-adapter.js` and
  `daemon/src/opencode-adapter.js` wait for that signal before prompt dispatch.
  `daemon/src/opencode-server-client.js` requires the SSE response content type
  to be `text/event-stream` before resolving `opened`; `scripts/run-tests.js`
  includes deterministic regression tests for the server client, conversation
  adapter, and legacy run path.
- Mitigation: preserve the SSE-open-before-prompt invariant when changing
  OpenCode client, adapter, lifecycle, or fake-server code.
- Last verified: 2026-06-09

## Risk: OpenCode Managed Shutdown Cleanup Can Fail By Platform API

- Level: low
- Impact: Windows process-tree cleanup (`taskkill`) or direct `child.kill` can
  fail during daemon shutdown. Those failures must not abort daemon resource
  cleanup or leave lifecycle status stuck in `stopping`.
- Evidence: `daemon/src/opencode-server-lifecycle.js` wraps process-tree
  termination and direct child kill as best-effort cleanup; `scripts/run-tests.js`
  covers thrown process-tree terminators and thrown `child.kill` calls.
- Mitigation: keep managed OpenCode child cleanup best-effort and preserve
  regression tests when changing lifecycle shutdown behavior.
- Last verified: 2026-06-09

## Risk: Provider IDs Can Contain URL-Reserved Characters

- Level: medium
- Impact: OpenCode permission ids and other provider-owned ids may contain
  characters such as `/`, spaces, or `%`. If mobile sends them as raw path text
  or daemon compares percent-encoded route captures directly, approvals can fail
  with a false id mismatch or miss the route entirely.
- Evidence: `daemon/src/server.js` decodes route path segments before comparing
  ids; `mobile/lib/src/services/daemon_client.dart` and
  `mobile/lib/src/services/conversation_client.dart` encode id path segments.
  `scripts/run-tests.js` covers an OpenCode approval id containing URL-reserved
  characters.
- Mitigation: encode every id inserted into mobile URL path segments and decode
  every daemon route segment before domain/service lookup.
- Last verified: 2026-06-09

## Risk: Provider Approval IDs Are Conversation Scoped

- Level: medium
- Impact: OpenCode permission ids are provider/session-owned identifiers, not
  mobile-global identifiers. If mobile notification or cache code de-dupes by
  bare approval id, a pending approval in one conversation can suppress or clear
  another conversation's notification when providers reuse ids.
- Evidence: `mobile/lib/src/services/approval_notification_handler.dart`
  scopes notified approval keys by `conversationId` and `approvalId`.
  `mobile/test/approval_notification_handler_test.dart` covers two background
  conversations with the same provider approval id producing separate
  notifications.
- Mitigation: compare or de-dupe provider approval ids only within their
  conversation/session scope. Preserve URL encoding for route path usage
  separately.
- Last verified: 2026-06-09

## Risk: Approval Composer State Can Outlive Provider Approval Options

- Level: medium
- Impact: the mobile approval composer is stateful while provider approval
  capabilities are event-owned. If a new approval replaces the previous one in
  the same widget position, stale local choices such as session scope can be
  submitted even when the new approval no longer supports that option.
- Evidence:
  `mobile/lib/src/ui/features/workbench/messages/approval_event_card.dart`
  resets the composer selection on provider approval id change and clamps a
  stale session selection when `supportsSessionScope` turns false.
  `mobile/test/widget_test.dart` covers replacing a session-capable approval
  with a once-only approval before submit.
- Mitigation: key or reset approval-composer local state by current provider
  approval identity, and clamp every local decision to the current
  `ApprovalRequestOptions` before submit.
- Last verified: 2026-06-09

## Risk: Service-Layer Notification Copy Can Bypass Localization

- Level: medium
- Impact: mobile service classes do not have `BuildContext` or locale access.
  If they synthesize user-visible notification text directly, paired devices in
  non-English locales can receive mixed-language approval notifications.
- Evidence:
  `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` injects the
  localized additional-approval formatter from `AppLocalizations`, while
  `mobile/lib/src/services/approval_notification_handler.dart` only appends
  grouped notification copy when the event provides a localized formatter.
  `mobile/test/approval_notification_handler_test.dart` covers grouped
  background approvals using localized extra-count copy and omitting the extra
  count when no localized copy is available.
- Mitigation: keep user-visible system notification strings generated in UI or
  localization-aware composition code, then pass them through event/service
  contracts. Do not add hardcoded English notification body suffixes in
  services.
- Last verified: 2026-06-10

## Risk: Approval Notification Show Failures Can Consume Pending Approvals

- Level: medium
- Impact: Android local notifications are best-effort, but a transient
  presenter/plugin failure must not mark an approval as already notified. If it
  does, or if the local presenter permanently caches a failed plugin
  initialization future, a background approval can stay pending in the app
  without any later retry opportunity.
- Evidence:
  `mobile/lib/src/services/approval_notification_handler.dart` marks provider
  approval ids as notified only after `showOrUpdateApproval` succeeds, keeps
  per-conversation show operations in flight to avoid duplicate notifications,
  and leaves failed or presenter-skipped approvals retryable on later
  background lifecycle changes.
  `mobile/lib/src/services/local_approval_notification_service.dart` clears a
  failed initialization future so the next show/cancel/initialize operation can
  retry the Flutter local-notifications plugin, and reports Android
  notification-permission denial as an unshown approval rather than a
  successful presentation.
  `mobile/test/approval_notification_handler_test.dart` covers failed
  background notification show retrying after the presenter recovers and
  silent presenter skips staying retryable, while
  `mobile/test/local_approval_notification_service_test.dart` covers retrying
  plugin initialization after a transient failure and permission denial
  returning an unshown result.
- Mitigation: keep "notified" as a successful presentation state, not an
  attempted presentation state. When changing notification presenter error
  handling, preserve retryability without introducing duplicate notification
  spam for the same provider approval id.
- Last verified: 2026-06-10

## Risk: Notification Taps Can Cross Workspace Boundaries

- Level: medium
- Impact: approval notification payloads carry provider-owned workspace and
  conversation ids. If tap routing falls back to the current or first workspace
  when the payload workspace is missing, a stale notification can open the wrong
  workspace session list and make the tap look valid.
- Evidence:
  `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` handles
  `openConversationFromNotification` with exact workspace matching before
  opening a session list, and only opens an existing conversation when both
  conversation id and workspace id match the notification payload.
  `mobile/test/widget_test.dart` covers a notification tap for a missing
  workspace staying on the workspace list instead of opening a fallback session
  list.
- Mitigation: keep notification tap routing strict. Use UI workspace fallback
  helpers only for interactive in-app navigation, not for external
  notification payload identity.
- Last verified: 2026-06-10

## Risk: Mobile Event Cache Files Are Not Authoritative

- Level: medium
- Impact: local read-through cache files can be corrupted, stale, or cleared
  while best-effort writes are still queued. Trusting file contents without key
  validation, or letting clear operations bypass the write queue, can replay
  another conversation's transcript or resurrect cleared events.
- Evidence:
  `mobile/lib/src/data/services/conversation_event_cache_store.dart` validates
  stored `namespace` and `conversationId` against the requested cache key,
  filters persisted events to the record conversation, ignores page upserts
  whose events all belong to other conversations before updating known-start
  metadata, and serializes `clearConversation` with upserts.
  `mobile/lib/src/services/daemon_notification_client.dart` also filters REST
  backfill rows to the requested route conversation before delivering them to
  active watchers, so a scoped backfill response cannot inject events into a
  different conversation route.
  `mobile/lib/src/data/repositories/cached_conversation_repository.dart`
  filters fetched event lists, event pages, cache hits, and live stream events
  to the requested conversation before returning them to UI callers or writing
  them into the read-through cache.
  `mobile/test/conversation_event_cache_store_test.dart` covers mismatched
  record identity deletion, mismatched page events not marking known history
  start, and clear-after-pending-write ordering;
  `mobile/test/cached_connected_repositories_test.dart` covers repository-level
  filtering for fetch, page, and stream event entry points;
  `mobile/test/daemon_notification_client_test.dart` covers scoped backfill
  ignoring events for other conversations.
- Mitigation: keep the daemon as the authoritative event store, treat local
  cache files as untrusted, and keep destructive cache operations in the same
  serialization path as writes. Any scoped replay/backfill response must be
  re-validated against its requested conversation before delivery or cache
  metadata updates.
- Last verified: 2026-06-09

## Risk: Notification Event Frames Need Scope-Payload Agreement

- Level: medium
- Impact: mobile multiplexes multiple conversation subscriptions over one
  WebSocket. If a malformed event frame is routed only by payload
  `conversationId`, a frame whose `scope.conversationId` names one
  conversation but whose payload names another can be delivered to the wrong
  watcher.
- Evidence: daemon `notification-protocol.createEventFrame` carries both
  `scope` and `payload`, and `daemon/src/notification-hub.js` creates live
  frames from the same event conversation id. Mobile
  `mobile/lib/src/services/daemon_notification_client.dart` now ignores event
  frames for unsupported topics and rejects frames whose explicit scope
  conversation id does not match the parsed payload. `mobile/test/daemon_notification_client_test.dart`
  covers mismatched scope/payload and unsupported-topic frames.
- Mitigation: keep daemon event-frame construction and mobile frame parsing in
  agreement. Treat `scope` and payload identity as a consistency check before
  delivery to a watcher.
- Last verified: 2026-06-09

## Risk: Notification Replay Authorization Can Drift Mid-Stream

- Level: medium
- Impact: WebSocket replay can span multiple async batches. If a paired device
  loses access to a conversation between replay batches, continuing to send
  historical events can expose conversation content after authorization has
  been revoked.
- Evidence: `daemon/src/notification-hub.js` revalidates subscription
  authorization before each replay batch as well as before live delivery.
  `scripts/run-tests.js` covers replay stopping with a `FORBIDDEN` error when
  access is revoked between batches.
- Mitigation: keep replay and live notification delivery on the same
  authorization boundary. Do not add awaits or replay batching paths that send
  events without rechecking current subscription authorization.
- Last verified: 2026-06-10

## Risk: Server-Side Notification Closes Can Leave Stale Subscriptions

- Level: medium
- Impact: when the daemon explicitly closes a notification WebSocket for
  reasons such as backpressure or token expiry, waiting only for the later
  socket close event can leave hub connection and conversation subscription
  indexes stale. The hub can then keep trying to deliver replay or live events
  to a connection that has already been rejected.
- Evidence: `daemon/src/notification-hub.js` now calls `closeConnection`
  immediately after initiating backpressure, token-expiry, and replay lookup
  internal-error closes, which removes the connection and all conversation
  subscription indexes synchronously. `scripts/run-tests.js` covers live
  publish hitting backpressure, token expiry, and replay lookup failure leaving
  no connection or subscription entries behind.
- Mitigation: every explicit server-side WebSocket close should either
  synchronously clean local hub indexes or prove that a later close handler
  cannot allow additional sends first.
- Last verified: 2026-06-10

## Risk: Workbench History Pagination Requires Cursor Progress

- Level: medium
- Impact: the Workbench initial history loader follows `hasMoreBefore` to pull
  enough older events for useful context. If a cache or daemon response repeats
  the same oldest sequence while still reporting `hasMoreBefore: true`, the
  loader can keep requesting older pages and never finish opening the
  conversation.
- Evidence:
  `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
  stops initial expansion and manual older-page loading when the returned
  oldest sequence does not move below the requested `beforeSeq`.
  `mobile/lib/src/data/models/conversation_models.dart` clamps parsed
  `hasMoreBefore` to false for empty explicit event pages, because an empty
  page has no cursor for older-history requests.
  `mobile/test/workbench_view_model_repository_state_test.dart` covers a
  repeated-page response and keeps dense partial-history expansion fixtures in
  realistic newest-to-oldest page order.
  `mobile/test/daemon_client_test.dart` covers empty daemon event pages not
  surfacing `hasMoreBefore: true` to Workbench.
- Mitigation: maintain the invariant that every `beforeSeq` page either returns
  no events, reports no more history, or advances the oldest loaded sequence
  lower than the requested cursor.
- Last verified: 2026-06-09

## Risk: V1 Run Follow-Ups Can Bypass Workspace Queue Serialization

- Level: medium
- Impact: follow-up prompts resume an existing run but still perform workspace
  writes. If a completed, failed, or cancelled V1 run starts its follow-up
  directly while another run is active in the same workspace, two adapter
  processes can run concurrently against a workspace that the queue contract
  intends to serialize.
- Evidence: `daemon/src/run-manager.js` submits eligible follow-up restarts
  through `RunQueue` before starting the adapter process. `scripts/run-tests.js`
  covers a completed run follow-up re-entering the workspace queue while a
  second run is active, then starting only after the active run completes.
- Mitigation: any path that restarts or resumes a V1 run after a terminal state
  must go through `RunQueue.submit` rather than calling `startRunProcess`
  directly.
- Last verified: 2026-06-10

## Risk: Approval Response Options Need Daemon-Side Enforcement

- Level: medium
- Impact: approval request options such as session scope support and
  deny-and-continue support are provider/request-owned capabilities. If the
  daemon trusts only mobile UI affordances, a stale or direct client can submit
  broader approval responses than the current request allowed.
- Evidence: `daemon/src/conversation-manager.js` validates approval responses
  against the current `blockingItem.approvalOptions` before writing
  `approval.resolved` or forwarding to the provider handle.
  `scripts/run-tests.js` covers rejecting unsupported session-scope approval
  and unsupported deny-and-continue responses without clearing the pending
  approval.
- Mitigation: when adding approval options, enforce them in
  `ConversationManager.respondApproval` or an equivalent daemon boundary before
  appending resolved events or calling adapter response methods.
- Last verified: 2026-06-09

## Risk: Blocking Response Event Persistence Can Strand Pending UI

- Level: medium
- Impact: answering a question or approval changes a conversation from
  `waiting_*` back to `running`. If that state change is persisted before the
  response event is durably appended, an event-store failure can make the
  client request fail while also clearing the pending blocking item, leaving the
  user unable to retry the same response.
- Evidence: `daemon/src/conversation-manager.js` snapshots blocking response
  state before `answerQuestion` and `respondApproval` pre-commit mutations, and
  rolls back when the `user.message` or `approval.resolved` response event
  append fails before provider dispatch.
  `scripts/run-tests.js` covers both response-event append failures preserving
  `waiting_input` / `waiting_approval` state and preventing provider calls.
- Mitigation: keep blocking response state transitions on the same pre-commit
  rollback boundary as their durable response events. If the response event has
  already been appended, treat later provider dispatch failures as committed
  dispatch failures rather than retryable pending responses.
- Last verified: 2026-06-10

## Risk: Conversation Control State Can Drift From Failed Persistence

- Level: medium
- Impact: live conversation controls such as permission mode changes can update
  daemon memory or provider state before the corresponding conversation record
  is durably saved. If the save fails and in-memory state is not restored, later
  summaries can report a setting that the failed request did not commit.
- Evidence: `daemon/src/conversation-manager.js` restores the previous
  permission-mode triple when `updatePermissionMode` persistence fails, and
  treats the follow-up `status_changed` notification as best-effort after the
  state has been committed. The legacy active-Claude `controlConversation`
  route uses the same rollback boundary for manager-owned permission mode and
  model updates when persistence fails after the provider handle accepts the
  control request.
  `scripts/run-tests.js` covers permission-mode persistence failure restoring
  `permissionMode`, `requestedPermissionMode`, and `effectivePermissionMode`,
  plus status event append failure preserving the committed mode while recording
  an audit entry. It also covers legacy control-route permission-mode and model
  persistence failures restoring the in-memory public conversation state.
- Mitigation: for conversation controls that persist manager-owned state,
  snapshot the previous public state before mutation. Roll back on persistence
  failure; once persistence succeeds, do not fail the user request solely
  because an auxiliary notification event could not be appended.
- Last verified: 2026-06-10

## Risk: Failed Conversation Creation Can Leave Ghost Sessions

- Level: medium
- Impact: creating a conversation registers a product object that mobile can
  list and later open. If the daemon exposes that object in memory before
  durable seed state is written, a failed create request can leave an
  in-memory-only ghost conversation with no reliable `conversation.started`
  event.
- Evidence: `daemon/src/conversation-manager.js` persists the conversation and
  appends `conversation.started` before adding the conversation to the
  manager's public in-memory index. `scripts/run-tests.js` covers
  `saveConversation` failure during `createConversation` leaving
  `listConversations()` empty.
- Mitigation: keep conversation creation visibility after durable seed writes.
  Do not add a new create-time side effect after in-memory registration unless
  it has a matching rollback path.
- Last verified: 2026-06-10

## Risk: Non-Current Approval Events Can Corrupt Mobile Waiting State

- Level: medium
- Impact: daemon may append `approval.resolved` or
  `blocking.request_cancelled` for a queued approval while another approval
  remains the active blocking item. If mobile summary caches or transcript
  reducers treat every resolved/cancelled approval as the active one, the
  conversation can appear `running` while the daemon is still waiting for user
  approval, or a late approval echo can resurrect an already terminal
  conversation.
- Evidence:
  `mobile/lib/src/data/repositories/cached_conversation_repository.dart` only
  maps `approval.resolved` to `running` when the current cached status can
  resume from an approval response and the event matches the current cached
  blocking item; `waiting_approval` without a current blocking item is left
  waiting rather than resumed from an uncorrelated approval echo.
  `mobile/lib/src/ui/features/workbench/conversation_reducer.dart` only clears
  waiting status when the current reducer status can resume and the
  resolved/cancelled event matches a pending blocking message; uncorrelated
  `approval.resolved` events do not resume a reducer that is already
  `waiting_approval`.
  `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
  applies the same correlation before updating the active conversation summary.
  `mobile/test/cached_connected_repositories_test.dart`,
  `mobile/test/conversation_reducer_test.dart`, and
  `mobile/test/coding_workbench_controller_test.dart` cover non-current and
  uncorrelated approval resolution preserving `waiting_approval`, plus late
  approval resolution preserving terminal `idle`.
- Mitigation: correlate blocking-state transitions by current approval/question
  id and resumable current status before changing mobile status. Do not infer
  state solely from event type, or from a missing current blocking item, when
  queued or late provider events are possible.
- Last verified: 2026-06-09

## Risk: OpenCode Public Error Surfaces Can Leak Provider Diagnostics

- Level: medium
- Impact: lifecycle, SSE, or provider-client errors may contain local paths,
  query strings, or provider response bodies. Copying raw `error.message` or
  recursive `error.details` into adapter status or conversation timeline events
  can expose those values to paired mobile clients and diagnostic exports.
- Evidence: `daemon/src/opencode-conversation-adapter.js` projects lifecycle
  diagnostics, stream-error causes, and missing-session HTTP error details
  through allowlists; `daemon/src/conversation-manager.js` redacts path-like
  session binding diagnostics before appending public helper events;
  `daemon/src/opencode-server-client.js` reads subscriber and transport error
  fields through descriptor-safe accessors before projecting public SSE/client
  errors;
  `daemon/src/opencode-event-mapper.js` treats local `file://` URLs as path
  diagnostics in both direct path metadata and provider diagnostic strings, and
  requires session ids on visible file-edit events;
  `daemon/src/opencode-conversation-adapter.js` projects startup, stream,
  abort, and session-missing errors through descriptor-safe allowlists;
  `daemon/src/opencode-adapter.js` applies the same descriptor-safe projection
  to legacy run startup, stream, listing, and SSE-open failures;
  `daemon/src/adapter-registry.js` sanitizes adapter capability detection
  fallback failures before exposing `/api/adapters` status;
  `daemon/src/opencode-server-lifecycle.js` reads provider/lifecycle error
  fields and nested diagnostic details through descriptor-safe accessors;
  `scripts/run-tests.js` covers lifecycle diagnostics exceptions, active-turn
  and idle-stream errors, abort warnings, session binding helper events, and
  stale provider session ids with secret path/body/query/file-URL fixtures, plus
  unsafe getter-backed lifecycle, conversation, client subscriber, registry, and
  legacy run errors.
- Mitigation: preserve allowlist projection for OpenCode public diagnostics and
  conversation event details. Do not add raw provider exception
  messages/details, local file URLs, or raw session binding diagnostics to
  public status, timeline, or diagnostic-export surfaces.
- Last verified: 2026-06-09

## Risk: OpenCode SSE Frames Are Provider-Controlled Payloads

- Level: medium
- Impact: `/global/event` frames arrive from the provider and can be complete
  but oversized, or oversized across multiple network chunks. Silently trimming
  an incomplete frame can drop provider events without error, while parsing an
  oversized complete frame can push unbounded payloads into mapper and
  conversation storage paths.
- Evidence: `daemon/src/opencode-server-client.js` enforces
  `MAX_SSE_EVENT_TEXT_LENGTH` before JSON parsing complete or still-pending SSE
  frames; `scripts/run-tests.js` covers oversized complete frame rejection,
  structured error details, and stream closure.
- Mitigation: keep SSE frame overflow fail-closed with
  `OPENCODE_SERVER_SSE_EVENT_TOO_LARGE`; do not restore silent buffer
  truncation for provider event frames.
- Last verified: 2026-06-09

## Risk: OpenCode SSE Subscribers Share One Transport Stream

- Level: medium
- Impact: multiple OpenCode conversation handles can share one
  `/global/event` stream. If one app-owned subscriber callback throws and the
  client lets it escape the response listener, it can interrupt delivery to
  other subscribers or surface as an uncaught process error.
- Evidence: `daemon/src/opencode-server-client.js` isolates throwing event and
  error callbacks, closes only the failing subscriber, and keeps remaining
  subscribers on the shared stream. `scripts/run-tests.js` covers a throwing
  event callback, a throwing error callback, and continued delivery to another
  subscriber without leaking the callback error message.
- Mitigation: preserve callback isolation when changing OpenCode SSE
  subscription, parser, or close/error fanout code. Do not call subscriber
  event or error handlers without an isolation boundary.
- Last verified: 2026-06-09

## Risk: OpenCode Session Directory Reconciliation Can Fail Open

- Level: medium
- Impact: OpenCode session reads are the only proof that a stored provider
  session still belongs to the authorized workspace. Accepting a missing
  directory, or treating a POSIX path with a literal backslash as a Windows path,
  can send a later prompt into an unverifiable or wrong workspace session.
- Evidence: `daemon/src/opencode-session-boundary.js` rejects missing session
  directories, recognizes `directory`, `cwd`, and `path` aliases, and keeps
  POSIX backslash siblings outside the workspace boundary. Its session id and
  directory extractors ignore inherited or getter-backed provider fields.
  Non-missing `realpath` failures fail closed as stable directory mismatches
  instead of exposing raw filesystem diagnostics.
  `scripts/run-tests.js` covers missing directory rejection before SSE
  subscription, POSIX backslash sibling containment, and safe own-field
  extraction for provider session metadata, plus path-bearing realpath
  failures. `scripts/smoke-opencode-server.js` reuses the production extractors
  and path containment helper so smoke evidence accepts the same session id,
  directory aliases, and path flavor rules as daemon runtime reconciliation.
- Mitigation: preserve fail-closed directory reconciliation before prompt
  dispatch. Do not add new OpenCode session-directory aliases or direct
  provider-field reads without matching containment, descriptor-safety, and
  smoke-helper drift tests.
- Last verified: 2026-06-09

## Risk: OpenCode Session ID Alias Drift Can Drop Events

- Level: medium
- Impact: `/global/event` session filtering happens before event mapping, so
  the conversation handle and mapper must recognize the same session id aliases.
  If the handle accepts a nested alias that the mapper treats as missing, a
  critical provider event can be converted to a non-dispatchable protocol
  warning and silently dropped for the active conversation.
- Evidence: `daemon/src/opencode-conversation-adapter.js` extracts nested
  `session.id`, `session.sessionId`, `session.sessionID`, and
  `session.session_id`; `daemon/src/opencode-event-mapper.js` now normalizes the
  same nested aliases and finite numeric provider ids. `scripts/run-tests.js`
  covers nested `session.sessionID` on `message.part.delta`, nested
  `session.session_id` on `session.updated`, direct numeric session ids through
  the conversation adapter, numeric permission ids through the mapper, and
  rejection of non-finite numeric session ids before binding/subscribing.
  `daemon/src/opencode-server-client.js` rejects unnormalized non-string route
  inputs before dispatching session, directory, or permission requests.
  `daemon/src/conversation-manager.js` drops drifted-session events after
  recording a `session_id_drift` warning so a providerSession from the wrong
  session cannot overwrite the current conversation binding.
- Mitigation: keep the OpenCode handle extraction and mapper session-id
  normalization alias sets aligned when adding provider event shapes.
- Last verified: 2026-06-09

## Risk: Session Binding Helper Events Are Part Of The State Transition

- Level: medium
- Impact: OpenCode missing-session and drift recovery clears or marks the
  conversation session binding before appending a public helper notice/warning.
  If the helper event append fails after state persistence, the conversation can
  lose its provider binding without a timeline explanation or audit trail.
- Evidence: `daemon/src/conversation-manager.js` rolls back and re-persists the
  previous session-binding state when `clearSessionBinding` or
  `markSessionBindingDrifted` cannot append its helper event.
  `scripts/run-tests.js` covers event append failures for both helpers.
- Mitigation: keep helper event append inside the same rollback boundary as the
  session binding mutation. Do not treat these helper events as optional logging.
- Last verified: 2026-06-09

## Risk: OpenCode Health Checks Can Pass Transport But Fail Semantics

- Level: medium
- Impact: `/global/health` can return a successful HTTP response whose body
  is malformed or reports `healthy: false` / `ok: false`. Treating any resolved
  health request as healthy can mark an external OpenCode server available or
  bind a managed child before the provider is actually ready.
- Evidence: `daemon/src/opencode-server-lifecycle.js` requires an own
  `healthy: true` or `ok: true` health field, reads those fields through
  descriptor-safe accessors, and validates unhealthy or malformed bodies as
  `OPENCODE_SERVER_HEALTH_UNAVAILABLE`; `daemon/src/opencode-adapter.js`
  applies the same semantic check to its listing-time health probe instead of
  trusting a lifecycle started state alone; `daemon/src/opencode-conversation-adapter.js`
  applies the same check to conversation capability detection; `scripts/run-tests.js`
  covers external malformed-body rejection, unsafe health getters, listing-time
  and conversation capability unhealthy/malformed responses, and managed
  retry/cleanup for false health bodies.
- Mitigation: preserve semantic health validation in lifecycle, listing-time,
  and conversation capability health probe code. Do not replace it with
  transport-only success checks unless the provider contract is re-smoked and
  tests are updated.
- Last verified: 2026-06-09

## Risk: Codex App-Server Account DTOs Can Leak Provider Credentials

- Level: medium
- Impact: `account/read` and `account/rateLimits/read` return provider-owned
  account objects to paired mobile clients. If DTO redaction only covers
  currently observed fields, future app-server schema drift can expose API
  keys, secrets, or passwords under snake, kebab, or camel-case names. Account
  mutation audit errors can leak the same credentials when provider error
  strings include key-value diagnostics.
- Evidence: `daemon/src/codex-app-server/dtos.js` redacts account DTO fields
  after normalizing key names, and
  `daemon/src/codex-app-server/routes.js` redacts credential-shaped account
  mutation error text before audit persistence. `scripts/run-tests.js` covers
  `api_key`, `secretKey`, `password`, and nested rate-limit `sessionSecret`
  fields returning `[REDACTED]` and not appearing in serialized account
  responses, plus mutation audit text redacting `api_key=`, `password=`, and
  `secret=` values.
- Mitigation: keep account DTO redaction based on normalized sensitive key
  semantics, not a narrow list of observed provider fields. Any new app-server
  account or rate-limit route must pass through the same redaction boundary
  before returning JSON. Any audit copy derived from account provider errors
  must redact credential key-value diagnostics before persistence.
- Last verified: 2026-06-10
