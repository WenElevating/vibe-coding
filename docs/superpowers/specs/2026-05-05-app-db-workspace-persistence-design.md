# App DB Workspace Persistence Design

Date: 2026-05-05

## Goal

Make saved workspaces a daemon-owned persistent resource backed by the application database, so the mobile workspace list always reflects what has been saved instead of relying on widget-local state or stale snapshots.

## Problem

Workspace creation currently returns a successful `WorkspaceSummary`, and the mobile UI shows `Workspace ready: <name>`. However, the daemon `WorkspaceRegistry` is an in-memory `Map`, while the mobile coding page also keeps a local `_workspaces` list copied from `AppSnapshot`.

That creates two bad outcomes:

- a workspace can appear to be created because the POST response succeeded, but the visible workspace list can still be overwritten by an older snapshot
- saved workspaces are not a durable daemon resource, even though migration status already claims `workspaces` are preserved

The root fix is not an optimistic UI cache. The root fix is making workspaces live in the daemon database and making the list query the daemon source of truth.

## Decision

Introduce an application-level SQLite database and store workspaces there.

### Database naming

Use an app-level database name, not a conversation-specific name:

```text
data/app/app.sqlite
```

Use `APP_DB_PATH` as the primary environment override.

Keep `CONVERSATION_DB_PATH` as a temporary compatibility alias during migration. `APP_DB_PATH` wins when both are set.

### Store boundary

Create an app database/store boundary that can own multiple persisted app resources:

- conversations and conversation events
- workspaces
- future app-level resources such as settings, templates, and device metadata

The existing conversation SQLite store can be adapted or wrapped during implementation, but the public naming should move toward app-level concepts such as `AppSqliteStore`, `appDbPath`, or `defaultAppDbPath`.

## Workspace Persistence Model

Add a `workspaces` table to the app database.

Required fields:

- `id` - stable workspace id, generated from the resolved path unless explicitly supplied
- `name` - display name
- `path` - resolved filesystem path
- `created_at` - ISO timestamp
- `updated_at` - ISO timestamp

Workspace identity is device-scoped in this pass. Do not make `path` globally unique, because the same path string can refer to different real locations across machines, mounted drives, containers, or OS users.

Recommended constraints:

- `id` primary key
- `(owner_device_id, path)` unique, so the same device does not create duplicate workspace rows for the same resolved path

Add a device/workspace authorization relation instead of storing authorization only in the workspace row:

- `device_id`
- `workspace_id`
- `created_at`

Recommended constraints:

- `(device_id, workspace_id)` primary key

This keeps the first implementation compatible with current per-device filtering while leaving room for later multi-device sharing semantics.

`updated_at` changes when mutable workspace metadata changes, such as a rename or a same-device duplicate-path create that updates the display name. On initial create, `created_at` and `updated_at` are equal. If the first implementation does not expose rename/archive yet, keep the field for the duplicate-path update path and future metadata updates.

## Daemon Data Flow

### Startup

1. Open the app database at `APP_DB_PATH` or `data/app/app.sqlite`.
2. Ensure app DB tables exist.
3. Seed the default current-project workspace only during first initialization, when the workspace table is empty.
4. Authorize the current device for the default workspace as today.

Do not silently recreate the default workspace on every restart. If a future delete/archive feature removes it, daemon restart must not undo that user action. A simple first-pass rule is: seed only when no workspace rows exist for the app database.

### `POST /api/workspaces`

1. Resolve the submitted path on the daemon side.
2. Insert or update the workspace by `(owner_device_id, path)`.
3. Write or confirm the `(device_id, workspace_id)` authorization relation for the current device.
4. Return the saved database row as `WorkspaceSummary`.

### `GET /api/workspaces`

1. Query workspaces from the database.
2. Join/filter through workspace authorization for the current device.
3. Return `{ workspaces: [...] }`.

The daemon registry can keep a small in-memory read-through cache if useful, but it must not be the source of truth. It must be rebuilt from or synchronized with the database.

## Mobile Data Flow

The mobile app should treat daemon workspace APIs as authoritative.

Creation flow:

1. User creates a workspace.
2. Mobile calls `POST /api/workspaces`.
3. On success, mobile refreshes workspaces from `GET /api/workspaces` or receives an updated app snapshot from a refreshed daemon query.
4. The workspace list displays the saved database result.
5. The success message is shown only after the list data has incorporated the saved workspace.

The UI may keep local state for selection and navigation mode, but it must not be responsible for making a newly-created workspace durable or for preserving it across stale snapshot syncs.

If creation succeeds but the follow-up list refresh fails, the UI should:

- stop the creating/loading state
- keep showing the previous workspace list
- show a warning that the workspace was saved but the list could not be refreshed
- provide a retry action that re-runs `GET /api/workspaces`, not `POST /api/workspaces`

The user should not need to create the workspace again after a successful POST.

## Compatibility and Migration

The implementation should support existing test and deployment overrides:

- Prefer `APP_DB_PATH`.
- If `APP_DB_PATH` is absent and `CONVERSATION_DB_PATH` is present, use `CONVERSATION_DB_PATH` as the app database path for compatibility.
- If neither is set, use `data/app/app.sqlite`.

Existing data under `data/conversations/conversations.sqlite` does not need to be migrated in the first implementation pass unless a compatibility test requires it. The main requirement is that new runtime data goes to the app-level database name.

## Error Handling

- Empty workspace path remains a client validation error.
- Invalid or inaccessible paths should produce a clear daemon error response.
- Database write failures should fail `POST /api/workspaces`; mobile must not show a success snackbar when the daemon write fails.
- If workspace creation succeeds but the follow-up list refresh fails, mobile should show a warning that the workspace was saved but the list could not be refreshed.

## Testing

Daemon tests should prove:

- `POST /api/workspaces` persists a workspace to the app database.
- A restarted daemon using the same `APP_DB_PATH` returns the workspace from `GET /api/workspaces`.
- Creating the same path twice for the same device does not create duplicate list rows.
- Creating the same path for different devices does not silently merge those devices into one workspace row.
- `APP_DB_PATH` overrides `CONVERSATION_DB_PATH`.
- `CONVERSATION_DB_PATH` still works as a temporary alias when `APP_DB_PATH` is absent.

Mobile tests should prove:

- The workspace creation flow refreshes or applies daemon-authoritative workspace data before showing success.
- A stale `AppSnapshot` does not remove a workspace that the daemon list confirms as saved.
- The visible workspace list includes the newly-created workspace after creation.

## Non-Goals

- Do not redesign workspace authorization in this pass.
- Do not replace device auth storage in this pass.
- Do not add a new frontend-only optimistic workspace cache as the primary fix.
- Do not introduce a second workspace-only database.
- Do not implement cross-device shared workspaces in this pass; the schema should avoid blocking that future capability.

## Acceptance Criteria

- Workspaces are persisted in the app database.
- Default DB naming is app-level: `data/app/app.sqlite`.
- `APP_DB_PATH` is the primary DB override.
- `CONVERSATION_DB_PATH` remains a temporary compatibility alias.
- `GET /api/workspaces` returns database-backed saved workspaces.
- Creating a workspace and restarting the daemon does not lose it.
- Same-device duplicate path creation does not duplicate list rows.
- Different devices using the same path string are not silently merged into a single workspace row.
- Mobile does not show `Workspace ready: <name>` while the visible daemon-backed list lacks that workspace.
- If list refresh fails after creation, mobile shows the old list with a retry-refresh path instead of asking the user to create again.
