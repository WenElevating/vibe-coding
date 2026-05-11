# Auth Token Lifecycle Design

Date: 2026-05-11

## Context

The daemon/mobile authentication model currently uses a paired device identity,
random access tokens, random refresh tokens, and daemon-side token hashes. The
model is appropriate for a local LAN control surface, but the lifecycle was
incomplete:

- The mobile client stored token strings without expiry metadata.
- `ensurePaired()` trusted any locally stored access token.
- Access tokens could expire while the app still displayed cached authenticated
  state.
- Refresh previously depended on an access token that might already be expired.
- A workspace delete request exposed the gap: the daemon rejected the request as
  `invalid bearer token`, so logical deletion never ran.

This design replaces the patch-level behavior with an explicit token lifecycle.
There is no compatibility requirement for older local token storage because the
product has not shipped a formal release yet.

## Goals

- Keep the current local-first trust model: pairing creates a trusted device;
  daemon stores only token hashes; mobile stores secrets locally.
- Make normal use stable for at least seven days without surprise auth failures.
- Refresh access tokens before they expire when possible.
- Keep a server-authoritative fallback for revoked, expired, or rotated tokens.
- Return to the connection/pairing flow when the trust relationship is broken.
- Avoid logging or exporting token secrets.

## Non-Goals

- Do not introduce OAuth, JWT, browser login, or external identity providers.
- Do not support old pre-lifecycle local token records.
- Do not silently auto-pair after auth failure.
- Do not expose token values in diagnostics, logs, UI, or crash reports.
- Do not redesign workspace authorization or device management UI beyond the
  auth-expired transition required here.

## Threat Model

This system is a local LAN control surface for a trusted desktop daemon. The
primary defended assets are workspace execution authority, pairing trust, and
stored mobile credentials.

Accepted risk for this phase:

- A stolen access token remains usable until it expires, with a default maximum
  window of 7 days.
- This is acceptable for the current local/LAN product stage because token values
  are stored locally, never logged, and daemon pairing is scoped to trusted
  devices.
- Device revocation still invalidates access because every authenticated request
  resolves the active device before allowing API use.

Future hardening options if the daemon is exposed beyond the current LAN trust
boundary:

- Lower `ACCESS_TOKEN_TTL_MS`.
- Add a short grace-period access-token revocation strategy during refresh.
- Bind device sessions to additional low-risk context such as expected LAN CIDR
  or observed client address range.
- Require explicit LAN exposure acknowledgement when binding outside localhost.

## Token Policy

Default daemon token lifetimes:

- Access token: 7 days.
- Refresh token: 30 days.
- Mobile refresh skew: 10 minutes.

The daemon should keep these values configurable through constructor options and
environment variables. The defaults should be used by `createApp()` when no
override is provided.

Recommended env names:

- `ACCESS_TOKEN_TTL_MS`
- `REFRESH_TOKEN_TTL_MS`
- `REFRESH_SKEW_MS`

The mobile client should treat an access token as needing refresh when:

- `now >= accessTokenExpiresAt - refreshSkew`, or
- a server request returns `401 AUTH_REQUIRED`.

The server remains authoritative. Client-side expiry checks are an optimization,
not a security decision.

## API Contract

`POST /api/pair` returns:

```json
{
  "deviceId": "device-1",
  "token": "access-token",
  "refreshToken": "refresh-token",
  "accessTokenExpiresAt": "2026-05-18T08:00:00.000Z",
  "refreshTokenExpiresAt": "2026-06-10T08:00:00.000Z"
}
```

`POST /api/token/refresh` accepts:

```json
{
  "deviceId": "device-1",
  "refreshToken": "refresh-token"
}
```

`POST /api/token/refresh` returns the same session shape as `POST /api/pair`.
The endpoint must not require the old access token to still be valid. It must
validate the requested device and the refresh token hash stored for that device.

Error behavior:

- Invalid, expired, reused, or revoked refresh token returns `401 AUTH_REQUIRED`.
- Revoked or missing device returns `401 AUTH_REQUIRED`.
- Device ID format errors return `401 AUTH_REQUIRED` with a safe message.
- Token values are never returned in error details.

## Daemon Storage

The existing `devices` and `device_tokens` tables remain the source of truth.
No schema change is required.

For each pair or refresh operation, the daemon stores:

- access token hash
- access token expiry
- refresh token hash
- refresh token expiry
- token type
- revocation timestamp when revoked

Refresh behavior:

1. Normalize and validate `deviceId`.
2. Load the active device by `deviceId`.
3. Load the latest valid refresh token for that device.
4. Verify the presented refresh token against the stored hash.
5. Generate a new access token and refresh token.
6. Revoke the used refresh token.
7. Store both new token hashes with expiry timestamps.
8. Return the new session payload with expiry timestamps.

Old access tokens should not be revoked immediately during refresh. They should
expire naturally. This avoids breaking concurrent requests that were already in
flight when refresh started. Device revocation still invalidates all access
because authenticated requests require the device to remain active.

## Mobile Token Model

Replace string-only access/refresh storage with a session model:

```dart
class StoredAuthSession {
  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final DateTime refreshTokenExpiresAt;
  final DateTime issuedAt;
  final DateTime updatedAt;
}
```

`SecureTokenStore` should expose session-oriented methods:

- `writeSession(StoredAuthSession session)`
- `readSession(String deviceId)`
- `deleteSession(String deviceId)`

The existing token-string helper methods may be removed or kept only as internal
delegates if that reduces churn. The implementation does not need to read old
token-only records.

`MemoryTokenStore` and the secure persistent token store must both implement the
same session contract so tests and production behavior match.

## Mobile Request Flow

All authorized daemon requests should use one shared request path:

1. Resolve current device ID from `DeviceIdentityStore`.
2. Load `StoredAuthSession`.
3. If no session exists, perform pairing.
4. If refresh token is expired, clear the session and throw `AuthExpiredException`.
5. If access token is expired or within the refresh skew, refresh before sending
   the business request.
6. Send the request with `Authorization: Bearer <accessToken>`.
7. If the response is not `401`, decode normally.
8. If the response is `401`, refresh once and retry the original request once.
9. If refresh returns `401 AUTH_REQUIRED` or the retry returns `401`, clear the
   session and throw `AuthExpiredException`.
10. If refresh fails transiently, keep the session and surface the connection
    failure so the caller can retry after reconnecting.

Refresh failure classification:

- Refresh `401 AUTH_REQUIRED` means the trust relationship is broken. Clear the
  session and throw `AuthExpiredException`.
- Refresh network errors, timeouts, daemon restart interruptions, and `5xx`
  responses are transient connection failures. Do not clear the session. Surface
  the original connection error so the caller can retry after reconnecting.
- After a transient refresh failure, `_refreshInFlight` is cleared in `finally`.
  The next authorized request may attempt refresh again.

Route authentication should be explicit at the daemon route definition level,
not maintained as an ad hoc string whitelist in the mobile request flow. Public
routes must be marked as `requiresAuth: false`; all other routes default to
authenticated. Current public routes are `/api/health`, `/api/version`,
`/api/pairing-code`, and `/api/pair`.

## Refresh Concurrency

`DaemonClient` should deduplicate concurrent refresh work with one in-flight
future:

- If request A starts refresh, request B waits for the same refresh future.
- Only one `/api/token/refresh` request is sent for a given burst.
- When refresh completes, all waiting requests use the same updated session.
- If refresh fails with `401 AUTH_REQUIRED`, all waiting requests receive the
  same auth-expired result.
- If refresh fails transiently, all waiting requests receive the same transient
  failure and the stored session remains intact.

The in-flight refresh state must be cleared in `finally` so a later refresh can
run.

## Auth-Expired UI State

Auth expiration is a connection-level failure, not a workspace or run error.

When mobile catches `AuthExpiredException`:

1. Clear local session data.
2. Leave cached workspace/run state behind in memory; do not present it as
   actionable.
3. Navigate back to the connection/pairing page.
4. Show a clear message: "Authorization expired. Please pair this device again."

The app must not silently auto-pair. Re-pairing requires the normal daemon
pairing-code flow.

`AuthExpiredException` propagation rule:

- Business operations such as workspace delete, run creation, conversation send,
  and polling must not swallow `AuthExpiredException`.
- Feature-level code may add context, but it must rethrow the auth-expired
  signal to the app shell.
- The app shell/root connection controller owns navigation back to the
  connection/pairing page.
- Background tasks must report auth expiration through the same root-level
  signal instead of leaving stale UI visible.

## Logging And Diagnostics

Daemon logs and diagnostic bundles must continue to redact secrets:

- Do not log access tokens.
- Do not log refresh tokens.
- Do not include authorization headers in exception records.
- Log only safe metadata such as method, path, status, code, trace ID, device ID,
  and token type when useful.
- Log refresh success/failure events with safe metadata: device ID, status,
  failure class, and trace ID. Never log token values or token hashes.

Expected auth failures such as expired access tokens should not become noisy
terminal errors. They can still be recorded with trace IDs when they cause API
failure responses.

## Testing Plan

Daemon tests:

- Pair returns access and refresh expiry timestamps.
- Pair stores only token hashes.
- Refresh works after the access token expires.
- Refresh rotates both access and refresh token values.
- Reusing the old refresh token fails.
- Expired refresh token fails.
- Revoked device cannot refresh or access APIs.
- Refresh response never includes token hashes.
- Refresh success/failure logs contain no token values.

Mobile client tests:

- Pair persists a complete `StoredAuthSession`.
- `ensurePaired()` reuses a valid session.
- `ensurePaired()` pairs when no session exists.
- Authorized requests refresh proactively inside the skew window.
- Authorized requests do not refresh when access token is still comfortably valid.
- A `401` response refreshes and retries the original request once.
- Refresh `401 AUTH_REQUIRED` clears the session and throws
  `AuthExpiredException`.
- Transient refresh failure does not clear the session.
- Concurrent authorized requests share a single refresh call.
- Concurrent requests in the refresh skew window do not reuse an already rotated
  refresh token.
- Workspace delete succeeds after refresh.

Widget/workflow tests:

- Auth expiration from a workbench request returns to the connection page.
- The connection page shows a re-pair message.
- Stale workspace UI is not left actionable after auth expiration.

## Rollout Notes

Because there is no formal released version, local token-only records do not need
to be migrated. Existing developer installations can re-pair after this change.

Developer reset guidance:

- Stop the mobile app.
- Clear the app's stored credentials, or uninstall/reinstall the debug app.
- If daemon-side pairing state also needs reset, delete the local runtime DB at
  `data/app/app.sqlite` while the daemon is stopped. This also removes runtime
  workspaces, conversations, and diagnostics, so it is a development-only reset.
- Restart the daemon and pair again from the mobile connection flow.

The current patch-level 401 retry can be replaced or folded into the new shared
request flow. The final implementation should avoid having both old token-string
helpers and new session helpers as parallel public APIs unless needed for a short
transition inside the same change.
