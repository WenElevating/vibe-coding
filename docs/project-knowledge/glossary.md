# Glossary

- Status: active seed
- Last verified: 2026-05-22

## Conversation

Stable product object for a coding session in the daemon/mobile product model.
Conversation metadata and events are daemon-owned.

## conversationId

Stable product identifier for a conversation.

## cliSessionId

Adapter resume token for a provider CLI. It is not a user-facing display title
and should not drive conversation identity.

## sessionBinding

State describing how the product conversation is bound to a CLI session/resume
token.

## AppSnapshot

Mobile startup/shell snapshot containing daemon health, workspaces,
conversations, runs, adapters, and other current app data.

## WorkbenchViewModel

Mobile feature ViewModel that owns workbench route state, active conversation
identity, conversation event projection, composer state, operation state, and
event trace metadata.

## Conversation title

Daemon-owned metadata derived from the first real user message. See
[stable conversation title decision](decisions/2026-05-22-stable-conversation-title.md).

## Bottom anchored transcript

Workbench transcript rendering mode where the latest message is the initial
visible anchor. Implemented through reversed ListView rendering in the UI layer.
