# Conversation Session Lifecycle Design

Date: 2026-05-08

## Problem

The mobile coding workbench currently mixes product sessions, CLI process state,
and list-display summaries. After a user cancels a response and sends another
message, stopping again can clear the visible messages and leave an empty
session entry. The underlying design problem is that cancellation is treated as
if the conversation were destroyed, and a `ConversationSummary` can be degraded
into a `RunSummary` that no longer has a conversation id or event replay path.

Cancellation must stop only the current CLI executor. It must not destroy the
conversation, clear the message history, clear the conversation id, or break the
binding to the CLI resume session.

## Core Semantics

A mobile coding conversation has one stable product identity:

```text
conversationId <-> cliSessionId
```

`conversationId` is the product/API/UI id owned by this app. `cliSessionId` is
the adapter resume id returned by Claude Code, Codex, or OpenCode. Once the
binding is confirmed, every later message in the same mobile conversation must
resume the same CLI session.

The stop button means:

```text
Stop the current response/executor.
Keep the conversation.
Keep the messages.
Keep the conversationId.
Keep the cliSessionId if it is known.
Keep the session list item as a conversation item.
```

## Conversation Model

The backend conversation remains the only persistent session object.

```text
Conversation
- id
- workspaceId
- adapter
- status
- cliSessionId
- sessionBinding
- createdAt
- updatedAt
```

`sessionBinding` describes the reliability of the `conversationId` to
`cliSessionId` binding:

```text
unknown   - no CLI session id has been captured or assigned yet
confirmed - the conversation is bound to a CLI session id
drifted   - the CLI returned a different session id; keep the original binding
```

The current CLI process or handle is an in-memory executor resource. It is not a
product model and must not be persisted as a session.

Session id binding must be persisted before, or atomically with, the event that
exposes it. If persistence fails, the manager must emit `run.error`, keep
`sessionBinding = unknown`, and must not report the session as confirmed. This
prevents an event stream from showing `session_start` while the persisted
conversation summary still has no `cliSessionId` after restart.

## Status And Binding Combinations

`status` describes the latest executor state. `sessionBinding` describes whether
resume can be trusted. They are separate dimensions.

Common combinations:

```text
idle + confirmed
  The last executor finished normally. Next send should resume cliSessionId.

cancelled + confirmed
  The user stopped the latest response after the CLI session was known. Next
  send should resume cliSessionId.

failed + confirmed
  The latest executor failed or timed out, but the CLI session binding is still
  known. Next send should resume cliSessionId.

interrupted + unknown
  The executor stopped before any reliable CLI session id was captured. Next
  send can continue the product conversation, but the CLI run may be a fresh
  CLI session.

cancelled/failed + drifted
  The product conversation remains usable, but resume reliability is suspect.
  The UI should show a non-blocking recoverability warning and diagnostics
  should include the drift event.
```

`interrupted + confirmed` should be rare. It can happen only when the daemon
detects an interrupted process after a previous confirmed binding. In that case
the next send should still resume the confirmed `cliSessionId`.

## User Visible States

The UI should explain stopped states without implying the conversation has been
destroyed.

```text
cancelled
  Label: Stopped
  Meaning: the current response was stopped and the CLI session can resume
  Next step: the user can continue typing in the same conversation

interrupted
  Label: Interrupted; CLI session binding was not confirmed
  Meaning: the executor stopped before a reliable cliSessionId was captured
  Next step: the user can continue typing, but the next CLI run may be a fresh
  CLI session and may not recover the interrupted context

failed
  Label: Execution failed
  Meaning: the latest CLI executor failed or hit the no-progress watchdog
  Next step: the user can continue typing; if sessionBinding is confirmed, the
  next executor should resume the known cliSessionId

drifted binding warning
  Label: Session resume may have changed
  Meaning: the CLI returned a different session id than the one bound to this
  conversation
  Next step: continue with the original cliSessionId, but surface a warning and
  include the drift in diagnostics
```

## Status Groups

Conversation statuses should be interpreted in groups:

```text
Active
- running
- waiting_input
- waiting_approval

Reusable
- idle
- cancelled
- failed
- interrupted

Destroyed
- expired
- deleted, if added later
```

`cancelled`, `failed`, and `interrupted` are reusable states. They describe the
most recent executor outcome, not the end of the conversation.

## CLI Session Binding

Adapters normalize CLI session ids into `event.sessionId`. The conversation
manager owns the binding rule and does not need to know each CLI event shape.

Claude Code should capture the session id as early as possible:

```js
if (event.type === 'system' && event.subtype === 'session_start') {
  sessionId = event.session_id;
}

if (event.type === 'result') {
  sessionId = event.session_id;
}
```

Binding rules:

```text
If conversation.cliSessionId is empty:
  save event.sessionId
  set sessionBinding = confirmed

If conversation.cliSessionId equals event.sessionId:
  keep sessionBinding = confirmed

If conversation.cliSessionId differs from event.sessionId:
  keep the original cliSessionId
  set sessionBinding = drifted
  emit a structured protocol warning
```

The drift warning must contain enough information for diagnosis:

```json
{
  "warning": "session_id_drift",
  "conversationId": "conv_xxx",
  "adapter": "claude",
  "expectedSessionId": "A",
  "receivedSessionId": "B"
}
```

This warns that resume may not have taken effect and the user may be in a fresh
CLI session while believing they continued the old one.

After `sessionBinding = drifted`, the next send must still use the original
`cliSessionId`. The received drift id must never silently replace the original
binding. The frontend should show a non-blocking warning such as "Session resume
may have changed; continuing with the original session id." Diagnostics must
preserve both ids. If the original session file has been deleted and resume
keeps drifting or failing, the user can still continue, but the UI should make
the reduced recoverability visible instead of pretending the conversation was
cleanly resumed.

## Sending And Resume

When the user sends a message with an existing conversation:

```text
POST /api/conversations/:conversationId/messages
```

When there is no active conversation:

```text
POST /api/conversations
POST /api/conversations/:conversationId/messages
```

When starting a CLI executor:

```text
If cliSessionId is confirmed:
  use the adapter's resume argument
  Claude Code: --resume <cliSessionId>

If cliSessionId is empty:
  start as a first run
  wait for system/session_start or result to capture cliSessionId
```

The `--session-id <uuid>` style of active assignment is a separate adapter
capability. It should not be assumed until tested for each CLI:

```text
If --session-id <uuid> is passed and the uuid has no stored session file,
does the CLI create a new session with that id, or does it error?
Can a later resume restore that proactively assigned session?
```

If reliable, an adapter can advertise a `preassignSupported` capability and the
backend can generate `cliSessionId` before the first CLI launch.

Adapter verification task before enabling proactive session assignment:

```text
Run Claude Code with --session-id <uuid> where the uuid has no stored session
file.
Confirm whether Claude Code creates a new session with that id or fails.
Run Claude Code again with --resume <same uuid>.
Confirm that history is restored.
Only after these checks pass can the Claude adapter advertise
preassignSupported.
```

## Cancellation

On user stop:

```text
kill the current active executor
active executor = null
keep conversationId
keep cliSessionId if known
keep all events
keep all visible messages
```

Status depends on whether a reliable CLI session binding exists:

```text
If cliSessionId is confirmed:
  status = cancelled
  meaning: the current response was stopped and the conversation can resume

If cliSessionId is still empty:
  status = interrupted
  meaning: the current response stopped before a reliable CLI session id was captured
```

The frontend must not clear these fields after cancellation:

```text
_activeConversationId
_activeConversation
_messages
conversation-backed SessionItem
```

It should update the current conversation status, poll the cancellation event,
show the existing history, and re-enable the composer.

## No-Progress Watchdog

The five-minute watchdog belongs to the current CLI executor, not to the
conversation lifecycle. It starts when the executor is spawned or when the user
message is written, whichever comes first. It must reset on every valid progress
event, not only on the first event.

Progress events include:

```text
session_start / event.sessionId
assistant.partial
assistant.message
assistant.question
approval.requested
tool.started
tool.output
tool.completed
diff.summary
result / conversation.completed
run.error
conversation.cancelled
```

If there is no valid progress for five minutes:

```text
kill active executor
active executor = null

If cliSessionId is confirmed:
  status = failed
  emit run.error with reason = no_progress_timeout
  keep conversation reusable

If cliSessionId is empty:
  status = interrupted
  emit run.error with reason = no_progress_timeout_without_session
  keep conversation reusable but mark the missing session binding
```

This is not a total runtime limit. Long-running commands are allowed as long as
the CLI continues to emit progress.

When the conversation enters `waiting_input` or `waiting_approval`, the
watchdog should pause because the executor is waiting on the user, not stalled.
When the user answers the input request or approval request, the watchdog should
resume for the continued executor.

## Mobile State Rules

The mobile workbench should stop using a broad terminal-state concept to decide
whether a conversation can continue. Use explicit predicates instead:

```text
_isRunningCli =
  status in running / waiting_input / waiting_approval

_canSendMessage =
  daemonConnected
  && adapterAvailable
  && !_isRunningCli
  && (activeConversationId != null || selectedWorkspace != null)
```

If the daemon is disconnected or restarting:

```text
keep the input draft
disable send or show an explicit connection error
do not clear messages
do not create an empty conversation
```

If the mobile client has already added an optimistic user message but the send
fails before `user.message` is persisted by the daemon:

```text
keep the original text in the composer draft, or mark the optimistic message as
unsent
do not create a session list item
do not clear activeConversationId
do not silently drop the message text
```

## Session List Rules

`SessionItem` may use `RunSummary` for display compatibility, but a conversation
must remain a conversation-backed item:

```text
SessionItem.conversation = conversation
SessionItem.run = runSummaryFromConversation(conversation)
```

The session list must not degrade a cancelled or interrupted conversation into a
run-only item. Run-only items are legacy or non-conversation executions.

Empty drafts can be filtered, but the draft definition must not hide abnormal
or interrupted conversations:

```text
status == idle
&& cliSessionId == null
&& hasUserMessage == false
```

Checking only `idle && cliSessionId == null` is insufficient because a
conversation may have user messages but no confirmed CLI session yet. The
backend should maintain `hasUserMessage` or `userMessageCount` on the
conversation summary so the session list does not need a per-row event query.

Legacy or partially written data must be normalized on load:

```text
If a persisted conversation has user.message events but no cliSessionId:
  restore it as interrupted rather than as an idle empty draft

If a persisted conversation is cancelled, failed, or interrupted:
  keep it as a conversation-backed session item
```

This migration rule prevents older SQLite rows from disappearing from the
mobile session list just because they lack a confirmed CLI session id.

## Testing

Backend tests:

```text
session id binding persistence failure emits run.error and does not mark
sessionBinding confirmed
cancel with confirmed cliSessionId keeps conversation reusable and preserves cliSessionId
cancel before session_start marks conversation interrupted
next message after cancelled uses --resume <cliSessionId>
session id drift keeps original binding and emits structured warning
drifted conversation sends the next message with the original cliSessionId, not
the received drift id
no-progress watchdog resets on valid progress
no-progress watchdog resets on every progress event, including repeated tool
output or assistant partial events
no-progress watchdog pauses while waiting_input or waiting_approval
no-progress watchdog kills executor after five minutes and keeps conversation
```

Mobile tests:

```text
stopping an active conversation keeps messages visible
stopping does not clear _activeConversationId
cancelled conversation remains in session list as ConversationSummary
reopening after restart loads historical messages from events
composer is disabled when daemon is disconnected
send failure before daemon persistence keeps or restores the draft text
cancelled, failed, and interrupted conversations can send another message
legacy conversations with user.message events but no cliSessionId appear as
interrupted, not as empty drafts
```

## Non-Goals

This design does not introduce a persistent turn model. A turn-like object may
exist internally as an executor bookkeeping detail, but it is not a product
session and must not appear in the mobile session list.

This design does not require immediate support for proactive `--session-id`
assignment. That should be added only after adapter-specific behavior is tested.
