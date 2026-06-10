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

## Risk: Codex App-Server Fail-Closed Requests Must Terminate Local Turn State

- Level: medium
- Impact: unsupported inbound app-server server requests such as interactive
  tool input and MCP elicitation are intentionally failed closed. If the
  adapter only returns a JSON-RPC error and emits `run.error` without clearing
  its local active turn and pending approval timers, the provider handle can
  keep stale turn or approval state alive after the conversation has already
  failed.
- Evidence:
  `daemon/src/codex-app-server-conversation-adapter.js` clears
  `activeTurnId`, cancels pending approvals, and records a post-turn-start
  run-error metric from the fail-closed server-request path.
  `scripts/run-tests.js` covers unsupported interactive server requests
  terminating local turn state and cancelling a pending approval.
- Mitigation: keep fail-closed inbound server requests on the same local
  termination boundary as provider terminal events and transport failures. Do
  not add new unsupported server-request branches that emit `run.error` without
  clearing active turn and blocking state.
- Last verified: 2026-06-10

## Risk: Codex App-Server Transport Warnings Must Not Carry Raw Responses

- Level: medium
- Impact: JSON-RPC responses can arrive after a request has timed out or after
  the local pending map has been cleared. If the transport forwards the entire
  orphan provider response through `protocol.warning`, delayed account,
  filesystem, config, or discovery payloads can leak sensitive provider data to
  paired mobile clients.
- Evidence:
  `daemon/src/codex-app-server-transport.js` emits only safe orphan-response
  metadata, currently the JSON-RPC id, and omits the raw response body.
  `scripts/run-tests.js` covers an orphan response containing a token-shaped
  value and a user-home path staying out of the protocol warning.
- Mitigation: keep transport protocol warnings diagnostic-only and
  allowlist-based. Do not attach raw app-server frames to warning events unless
  the frame has first gone through a provider-specific redaction contract.
- Last verified: 2026-06-10

## Risk: Codex App-Server Process Cleanup Is Platform Best-Effort

- Level: low
- Impact: app-server child shutdown can depend on Windows `taskkill`, process
  tree lookup, or platform `child.kill()` behavior. Those APIs can fail or
  throw while the daemon is already trying to dispose a probe, model-list, or
  conversation process. Letting those failures escape can interrupt daemon
  cleanup and leave lifecycle capacity accounting stale.
- Evidence:
  `daemon/src/codex-app-server-lifecycle.js` treats process-tree terminator
  failures and `child.kill()` failures as best-effort false results, while
  still deleting lifecycle handles when shutdown resolves.
  `scripts/run-tests.js` covers thrown process-tree termination and thrown
  child-kill cleanup paths for Codex app-server lifecycle.
- Mitigation: keep app-server shutdown cleanup exception-safe. Any new
  platform cleanup mechanism should fall back to the existing shutdown timers
  instead of replacing cleanup with a throwing path.
- Last verified: 2026-06-10

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

## Risk: Codex App-Server Config Reads Can Leak Credential Values

- Level: medium
- Impact: `/api/codex-app-server/config` returns local app-server config data
  to paired mobile clients. The upstream schema allows additional properties
  and raw layer config snapshots, so future provider or user config extensions
  can include credential-shaped values even when the stable schema does not
  name those fields.
- Evidence: `daemon/src/codex-app-server/routes.js` routes config reads through
  `normalizeConfigResponse()`, and
  `daemon/src/codex-app-server/dtos.js` redacts config keys such as `api_key`,
  `password`, and `secretKey` while preserving non-secret token policy/count
  fields such as `token_limit` and `model_auto_compact_token_limit`.
  `scripts/run-tests.js` covers config and layer config redaction on the
  discovery route.
- Mitigation: keep config read redaction separate from the generic discovery
  normalizer. Do not apply broad `token` substring redaction to all discovery
  responses; use config-specific credential-key matching so token budgets,
  limits, and usage counters remain visible.
- Last verified: 2026-06-10

## Risk: Codex App-Server File Writes Need Exact Payload Translation

- Level: medium
- Impact: `/api/codex-app-server/workspaces/:id/fs/write-file` accepts a
  mobile-facing `content` string, while the upstream app-server schema requires
  `dataBase64`. Reusing generic body-string parsing can trim valid leading or
  trailing file bytes, and forwarding `content` directly can send a payload the
  provider does not understand.
- Evidence: `daemon/src/codex-app-server/routes.js` preserves raw `content`
  before UTF-8 base64 encoding, and
  `daemon/src/codex-app-server/client.js` sends `fs/writeFile` with
  `dataBase64`. `scripts/run-tests.js` covers both the typed client payload and
  the approved high-risk route preserving leading/trailing whitespace through
  base64 translation.
- Mitigation: keep route-facing compatibility fields separate from upstream RPC
  schema fields. Do not use trimming helpers for file content, and do not add
  `encoding` or raw `content` back to the `fs/writeFile` JSON-RPC payload unless
  the generated schema changes and the fixture drift gate is updated.
- Last verified: 2026-06-10

## Risk: Codex App-Server File Watches Need Daemon-Owned Watch IDs

- Level: medium
- Impact: the mobile-facing `fs/watch` route only needs a workspace path, but
  the upstream app-server `FsWatchParams` schema requires a connection-scoped
  `watchId`. If the daemon forwards only `path`, provider watch setup can fail
  even though route authorization and workspace path resolution passed.
- Evidence: `daemon/src/codex-app-server/routes.js` generates `watch_<uuid>`
  before calling `watchFileSystem`, and
  `daemon/src/codex-app-server/client.js` forwards `watchId` in the `fs/watch`
  JSON-RPC payload. `scripts/run-tests.js` covers the workspace-scoped watch
  route passing a non-empty watch id to the typed service method and using that
  id for unwatch.
- Mitigation: keep provider-required IDs generated at the daemon boundary when
  the mobile API intentionally hides them. Any future watch route changes must
  preserve the invariant that `fs/watch` and `fs/unwatch` use the same
  provider watch id.
- Last verified: 2026-06-10

## Risk: Codex App-Server Fuzzy Search Routes Need Schema Roots

- Level: medium
- Impact: the mobile-facing fuzzy-search routes are workspace scoped, but the
  upstream app-server schema expects search roots and provider-owned session
  ids rather than `workspacePath` or `limit`. Forwarding the mobile route shape
  directly can make fuzzy search and session startup fail against the provider.
- Evidence: `daemon/src/codex-app-server/client.js` maps fuzzy search calls to
  `roots`, `sessionId`, and `query` only. `daemon/src/codex-app-server/routes.js`
  derives `roots` from the authorized workspace, generates `fuzzy_<uuid>` for
  session startup, and applies the initial mobile query with
  `fuzzyFileSearch/sessionUpdate` after `sessionStart`.
  `scripts/run-tests.js` covers the typed client payloads and route calls for
  search, session start, session update, and session stop.
- Mitigation: keep route-facing pagination/limit validation separate from
  upstream fuzzy-search payloads. If the provider schema later accepts limits or
  different root shapes, update the generated fixtures and route tests together.
- Last verified: 2026-06-10

## Risk: Codex App-Server Process Routes Need Schema Handles

- Level: medium
- Impact: mobile-facing process routes accept workspace-scoped command requests,
  but upstream `process/spawn`, `process/kill`, and `command/exec` use argv
  vectors and connection-scoped process identifiers. Forwarding route fields
  such as `args`, `workspacePath`, or `processId` directly can make high-risk
  process operations fail against the provider schema.
- Evidence: `daemon/src/codex-app-server/routes.js` combines route
  `command`/`args` fields into upstream argv vectors, generates
  `process_<uuid>` handles for `process/spawn`, and maps kill path ids to
  `processHandle`. `daemon/src/codex-app-server/client.js` sends only schema
  process fields. `scripts/run-tests.js` covers typed client payloads and
  high-risk route translation for process spawn, kill, and command exec.
- Mitigation: keep mobile route compatibility fields at the daemon boundary.
  Do not forward `args`, `workspacePath`, or route-level process ids directly
  to process RPC payloads unless the generated schema changes and route tests
  are updated together.
- Last verified: 2026-06-10

## Risk: Codex App-Server Config Routes Need Schema Edits

- Level: medium
- Impact: mobile-facing config and environment routes use compact compatibility
  bodies, while upstream app-server config writes require `keyPath`,
  `mergeStrategy`, and `edits[]`, and environment registration requires
  `environmentId` plus `execServerUrl`. Forwarding `key`, `values`, `name`, or
  `value` directly can make high-risk config mutations fail against the
  provider schema.
- Evidence: `daemon/src/codex-app-server/routes.js` maps legacy `key` to
  `keyPath`, defaults single-value and legacy batch writes to
  `mergeStrategy: replace`, expands legacy `values` objects into schema
  `edits[]`, and maps environment aliases to `environmentId`/`execServerUrl`.
  `daemon/src/codex-app-server/client.js` sends only schema config and
  environment fields. `scripts/run-tests.js` covers typed client payloads and
  high-risk route translation for config value, config batch, and environment
  add.
- Mitigation: keep mobile compatibility bodies at the daemon route boundary.
  Do not reintroduce raw `key`, `values`, `name`, or `value` fields into
  upstream config/environment RPC payloads unless schema fixtures and route
  tests change together.
- Last verified: 2026-06-10

## Risk: Codex App-Server Plugin Routes Need Provider Names

- Level: medium
- Impact: mobile-facing plugin, marketplace, and MCP resource routes historically
  used UI-oriented ids such as `pluginId`, `marketplaceId`, and `serverId`, but
  upstream app-server schemas use provider terms such as `pluginName`,
  `remotePluginId`, `remoteMarketplaceName`, `marketplaceName`, `source`, and
  `server`. Forwarding UI ids directly can make discovery and high-risk plugin
  mutations fail against the provider schema.
- Evidence: `daemon/src/codex-app-server/client.js` maps MCP resource reads,
  plugin discovery, plugin install, marketplace add/remove/upgrade, and plugin
  share listing to schema fields. `daemon/src/codex-app-server/routes.js`
  keeps legacy mobile aliases at the route boundary and requires
  `remoteMarketplaceName` for plugin skill reads before dispatching. `scripts/run-tests.js`
  covers typed client payloads, discovery route translation, high-risk plugin
  and marketplace mutation translation, and the missing-marketplace skill-read
  rejection path.
- Mitigation: treat UI ids as route compatibility aliases only. Do not forward
  `pluginId`, `marketplaceId`, `serverId`, or cursor-only plugin list/share
  fields to upstream plugin, marketplace, or MCP resource RPC payloads unless
  schema fixtures and route tests change together.
- Last verified: 2026-06-10

## Risk: Codex App-Server Skills And Remote Control Routes Need Schema Fields

- Level: medium
- Impact: mobile-facing skills, MCP reload, and remote-control routes use
  compatibility bodies and query fields that do not match the upstream
  app-server schemas. Forwarding route fields such as skills `cursor`, nested
  `config`, `roots`, remote pairing `timeoutSecs`, or client revoke requests
  without `environmentId` can make provider calls fail or silently target the
  wrong scope.
- Evidence: `daemon/src/codex-app-server/client.js` maps `skills/list` to
  `cwds` and `forceReload`, sends `config/mcpServer/reload` with `null`
  params, maps skills config writes to top-level `enabled`/`name`/`path`, maps
  extra roots to `extraRoots`, maps remote client list and revoke requests with
  `environmentId`, and maps pairing start to `manualCode`. The matching route
  translations and request validation live in
  `daemon/src/codex-app-server/routes.js`. `scripts/run-tests.js` covers typed
  client payloads, discovery route translation, high-risk route translation,
  and malformed-body rejection for these schema boundaries.
- Mitigation: keep mobile compatibility fields at the daemon route boundary.
  Do not forward skills `cursor`, nested `config`, `roots`, pairing
  `timeoutSecs`, or remote-control requests without `environmentId` into
  upstream app-server RPC payloads unless the schema fixtures and route tests
  change together.
- Last verified: 2026-06-10

## Risk: Codex App-Server Thread Routes Need Schema Thread Fields

- Level: medium
- Impact: mobile-facing thread history and mutation routes use compatibility
  names such as `workspacePath`, `query`, nested `settings`, `memoryMode`,
  nested `goal`, and legacy rollback `turnId`/`itemId`. The upstream
  app-server schemas expect `cwd`, `searchTerm`, flattened settings fields,
  `mode`, flattened goal fields, and rollback `numTurns`. Forwarding the route
  shapes directly can make thread list/search/mutation calls fail against the
  provider or ignore intended clear-to-null updates.
- Evidence: `daemon/src/codex-app-server/client.js` maps thread list/search,
  fork, rollback, metadata, settings, memory mode, and goal writes to schema
  fields. `daemon/src/codex-app-server/routes.js` translates route
  compatibility bodies, validates rollback `numTurns`, restricts metadata to
  schema `gitInfo`, validates memory mode values, and preserves explicit nulls
  for clearable thread metadata/settings/goal fields. `scripts/run-tests.js`
  covers typed client payloads, workspace-scoped route translation, and
  malformed legacy bodies.
- Mitigation: keep mobile compatibility aliases at the daemon route boundary.
  Do not forward `workspacePath`, `query`, nested `settings`, `memoryMode`,
  nested `goal`, or rollback `turnId`/`itemId` into upstream thread RPC
  payloads unless the generated schemas and route tests change together.
- Last verified: 2026-06-10

## Risk: Codex App-Server File Read Routes Must Not Forward Encoding

- Level: low
- Impact: the mobile-facing file read route can accept an `encoding` query for
  compatibility, but the upstream app-server `fs/readFile` schema only accepts
  `path`. Forwarding `encoding` can make otherwise valid workspace-scoped file
  reads fail provider validation.
- Evidence: `daemon/src/codex-app-server/client.js` sends `fs/readFile` with
  only `path`, and `daemon/src/codex-app-server/routes.js` validates but does
  not forward the compatibility `encoding` query. `scripts/run-tests.js`
  covers both the typed client payload and workspace file read route options.
- Mitigation: keep `encoding` as daemon/mobile compatibility metadata only.
  Do not add it back to the upstream `fs/readFile` payload unless generated
  schema fixtures and route tests change together.
- Last verified: 2026-06-10

## Risk: Codex App-Server Review Diagnostic Route Needs Thread Scope

- Level: medium
- Impact: `review/start` is diagnostic-only, but it still calls the upstream
  app-server method. The provider schema requires `threadId` and a structured
  `target`; workspace-only compatibility fields such as `workspacePath` and
  `maxItems` are not accepted. Calling review without verifying the thread's
  workspace can also run a diagnostic review against a thread outside the
  authorized mobile workspace.
- Evidence: `daemon/src/codex-app-server/client.js` sends `review/start` with
  only `threadId`, `target`, and optional `delivery`.
  `daemon/src/codex-app-server/routes.js` rejects legacy review bodies, parses
  schema targets, and runs the standard thread workspace ownership preflight
  before dispatch. `scripts/run-tests.js` covers typed client payloads,
  diagnostic route audit behavior, preflight read, and malformed request
  rejection.
- Mitigation: keep review diagnostics schema-first even while product review UX
  remains incomplete. Do not reintroduce `workspacePath` or `maxItems` into the
  upstream `review/start` payload unless generated schemas and route tests
  change together.
- Last verified: 2026-06-10

## Risk: Codex App-Server Route Capabilities Include Diagnostic Routes

- Level: low
- Impact: `/api/codex-app-server/capabilities` exposes server-route capability
  rows for both fully supported and diagnostic-only route-test methods. If route
  coverage checks only track `localStatus: supported`, mobile can see a
  diagnostic route in capabilities while the route registry misses the method.
- Evidence: `daemon/src/codex-app-server/capability-routes.js` selects all
  `daemonOwner: server route`, `direction: request`, `testRequirement: route test`
  rows, including diagnostic-only `review/start`, `attestation/generate`,
  filesystem watch routes, and realtime streaming diagnostics.
  `scripts/run-tests.js` now requires every advertised route-test method to be
  present in `SUPPORTED_ROUTE_METHODS`, and `daemon/src/codex-app-server/routes.js`
  includes the diagnostic-only methods in that coverage set.
- Mitigation: treat `SUPPORTED_ROUTE_METHODS` as the advertised route coverage
  registry, not only the fully-supported behavior registry. Diagnostic-only
  methods should remain present there when they are exposed through route
  capabilities.
- Last verified: 2026-06-10

## Risk: Codex App-Server Thread Detail Reads Need Ownership Preflight

- Level: high
- Impact: workspace-scoped thread detail read routes accept a workspace id in
  the URL but act on provider `threadId` values. If detail reads do not verify
  the provider thread's `workspacePath`, a caller authorized for one workspace
  could read turns, items, goals, or thread metadata from another workspace by
  supplying a known thread id.
- Evidence: `daemon/src/codex-app-server/routes.js` now checks thread
  workspace ownership for thread detail, turns, turn items, and goal reads
  before returning data or dispatching downstream list/get calls. The ownership
  check reuses the same provider `thread/read` workspacePath comparison used by
  thread mutations and `review/start`. `scripts/run-tests.js` covers the
  forbidden outside-workspace path and verifies turns/items/goal are not read
  after the failed preflight.
- Mitigation: keep all workspace-scoped routes that accept a provider
  `threadId` behind thread workspace ownership verification unless the upstream
  app-server adds a schema-level workspace-scoped read primitive.
- Last verified: 2026-06-10

## Risk: Codex App-Server Add-Credits Nudge Requires Credit Type

- Level: medium
- Impact: `account/sendAddCreditsNudgeEmail` looks like a no-argument account
  action at the mobile route level, but the upstream app-server schema requires
  `creditType`. Sending `{}` makes the provider reject an otherwise authorized
  account mutation.
- Evidence: `daemon/test/fixtures/codex-app-server/schema/v2/SendAddCreditsNudgeEmailParams.json`
  requires `creditType` with enum values `credits` or `usage_limit`.
  `daemon/src/codex-app-server/client.js` now forwards `creditType`, and
  `daemon/src/codex-app-server/routes.js` validates the enum before dispatch.
  `scripts/run-tests.js` covers typed client payloads, successful route
  forwarding, and missing/invalid body rejection before service access.
- Mitigation: keep account mutation routes schema-first. Do not treat
  add-credits nudge as a bodyless operation unless the generated schema changes.
- Last verified: 2026-06-10

## Risk: Codex App-Server Metrics Wrapping Must Not Mutate Cached Clients

- Level: medium
- Impact: discovery clients are intentionally cached and reused within TTL. If
  the metrics wrapper writes its "already wrapped" marker onto the raw cached
  client, later cache hits can bypass the proxy and silently stop recording
  method latency/error metrics for reused clients.
- Evidence: `daemon/src/codex-app-server/service.js` now stores metrics proxies
  in a `WeakMap` keyed by the raw client instead of defining marker properties
  through the proxy. `scripts/run-tests.js` verifies two cached
  `model/list` discovery calls emit two latency samples.
- Mitigation: keep service-level instrumentation side-effect-free on provider
  client instances. If instrumentation state is needed, store it outside the
  client object so cache reuse does not change observability behavior.
- Last verified: 2026-06-10

## Risk: Codex App-Server Cached Discovery Processes Need Service Shutdown

- Level: medium
- Impact: the route service owns cached discovery clients and their app-server
  process handles. If daemon shutdown only closes the HTTP server and shared
  stores, cached discovery app-server processes can survive past daemon
  shutdown.
- Evidence: `CodexAppServerService.shutdown()` now closes cached discovery
  entries, waits for in-flight discovery creation, closes remaining tracked
  handles, and rejects later service use with
  `CODEX_APP_SERVER_SERVICE_CLOSED`. `shutdownAppResources()` calls that
  service shutdown before closing stores. `scripts/run-tests.js` covers both
  the service-level cached-client cleanup and the daemon shutdown integration.
- Mitigation: keep app-server process ownership inside
  `CodexAppServerService`; daemon shutdown should call the service-level
  cleanup rather than trying to reach into lifecycle internals.
- Last verified: 2026-06-10

## Risk: Codex App-Server Selection Probe Failures Must Stay Redacted

- Level: medium
- Impact: conversation creation resolves the requested/effective adapter before
  provider side effects. If the app-server conversation adapter probe throws
  there and the raw exception escapes, HTTP error responses can expose local
  paths or provider diagnostics instead of falling back safely to Codex.
- Evidence: `ConversationManager.resolveAdapterSelection()` now treats thrown
  app-server `detectCapabilities()` results as a non-selectable
  `adapter_probe_failed` state. When Codex fallback is available, conversation
  creation continues with `effectiveAdapter: codex` and a stable fallback
  reason. `scripts/run-tests.js` covers path-bearing probe failures and
  verifies the public conversation JSON does not retain the path text.
- Mitigation: keep app-server adapter-selection probes exception-safe and use
  stable reason codes in fallback notices. Do not copy raw probe error messages
  into conversation summaries.
- Last verified: 2026-06-10

## Risk: Codex App-Server Timeout Policy Must Be Applied at the Client Boundary

- Level: high
- Impact: `timeouts.js` can correctly classify long-lived methods, but the
  daemon still times out long-running app-server turns if `CodexAppServerClient`
  does not pass the classified timeout to the JSONL transport. In that case
  `thread/start`, `thread/resume`, `turn/start`, `command/exec`, or
  `process/spawn` can inherit the normal instant-RPC timeout and fail during
  valid long-running work.
- Evidence: `daemon/src/codex-app-server/client.js` now applies
  `classifyCodexAppServerTimeout()` when callers do not provide an explicit
  timeout. Long-lived methods pass `timeoutMs: null`, and
  `daemon/src/codex-app-server-transport.js` treats null as no per-request
  timer. `scripts/run-tests.js` covers null transport timers, client timeout
  forwarding for `thread/start` and `turn/start`, and long-lived method
  classification for command/process methods.
- Mitigation: keep timeout policy wired at the client/transport boundary.
  Adding methods to `timeouts.js` is not sufficient unless client requests
  actually carry the effective timeout into the transport.
- Last verified: 2026-06-10

## Risk: Codex App-Server Risk Policy Can Drift from Capability Matrix

- Level: medium
- Impact: route capabilities expose risk from the capability matrix, while
  `risk-policy.js` provides method-level risk inference for other app-server
  decisions. If the two sources drift, diagnostics and future approval gates can
  classify the same method differently from the advertised route contract.
- Evidence: `risk-policy.js` now matches route-test matrix risk for
  `review/start`, `attestation/generate`, `config/mcpServer/reload`, and
  `thread/realtime/start`. `scripts/run-tests.js` verifies every advertised
  route-test method has the same risk in route capabilities, matrix rows, and
  `riskForCodexAppServerMethod()`.
- Mitigation: keep route capability risk and risk-policy inference covered by
  the same matrix-derived regression whenever app-server methods are added or
  reclassified.
- Last verified: 2026-06-10
