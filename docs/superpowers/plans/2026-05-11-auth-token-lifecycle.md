# Auth Token Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement explicit daemon/mobile access-token and refresh-token lifecycle with expiry metadata, refresh-before-expiry, and server-authoritative auth failure recovery.

**Architecture:** Keep daemon token state in existing `devices` and `device_tokens` storage, but make session creation return token expiry timestamps and allow refresh with only `deviceId` plus refresh token. Mobile persists token sessions instead of bare strings and refreshes before expiry or after a `401 AUTH_REQUIRED` response.

**Tech Stack:** Node.js CommonJS daemon, built-in `node:test`, Flutter/Dart client, `package:http`, existing `MemoryTokenStore` abstraction.

---

## File Structure

- Modify `daemon/src/auth.js`: default TTLs, env overrides, expiry-bearing session responses, refresh without access-token dependency, safe device-id validation.
- Modify `daemon/src/main.js`: pass env/constructor token policy through `createApp()`.
- Modify `mobile/lib/src/services/daemon_client.dart`: add `TokenSession`, expiry-aware token store methods, refresh skew, request retry on `401 AUTH_REQUIRED`.
- Modify `daemon/test/core.test.js`: daemon unit coverage for 7-day expiry metadata, expired access refresh, invalid refresh rejection.
- Modify `mobile/test/daemon_client_test.dart`: mobile coverage for session persistence, proactive refresh, and `401 AUTH_REQUIRED` fallback retry.

### Task 1: Daemon Session Expiry Contract

**Files:**
- Modify: `daemon/src/auth.js`
- Test: `daemon/test/core.test.js`

- [ ] **Step 1: Write failing daemon tests**

Add tests that assert `pair()` returns `accessTokenExpiresAt` and `refreshTokenExpiresAt`, defaults access expiry to seven days, and rejects expired access tokens.

```js
test('pairing returns lifecycle expiry timestamps', () => {
  const auth = new AuthManager({ now: () => Date.parse('2026-05-11T08:00:00.000Z') });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone', 'device-123');

  assert.equal(paired.accessTokenExpiresAt, '2026-05-18T08:00:00.000Z');
  assert.equal(paired.refreshTokenExpiresAt, '2026-06-10T08:00:00.000Z');
});
```

- [ ] **Step 2: Run failing daemon test**

Run: `node --test daemon/test/core.test.js --test-name-pattern "lifecycle"`
Expected: FAIL because expiry fields are missing or access expiry uses the old 15-minute default.

- [ ] **Step 3: Implement expiry metadata**

Set default access TTL to `7 * 24 * 60 * 60 * 1000`, default refresh TTL to `30 * 24 * 60 * 60 * 1000`, derive ISO timestamps once per session, store them, and return both timestamps from `registerDevice()` and `refresh()`.

- [ ] **Step 4: Run daemon lifecycle tests**

Run: `node --test daemon/test/core.test.js --test-name-pattern "lifecycle|pairing issues|refresh rotates"`
Expected: PASS.

### Task 2: Daemon Refresh Without Access Token

**Files:**
- Modify: `daemon/src/auth.js`
- Modify: `daemon/src/server.js`
- Test: `daemon/test/core.test.js`

- [ ] **Step 1: Write failing refresh tests**

Add tests proving `auth.refresh(null, refreshToken, deviceId)` succeeds after the access token has expired, rotates refresh tokens, and rejects invalid device ids with `AUTH_REQUIRED`.

```js
test('refresh accepts a valid refresh token after access expiry', () => {
  let now = Date.parse('2026-05-11T08:00:00.000Z');
  const auth = new AuthManager({ now: () => now, accessTokenTtlMs: 10, refreshTokenTtlMs: 100000 });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone', 'device-123');
  now += 20;

  assert.throws(() => auth.authenticate(`Bearer ${paired.token}`), /invalid bearer token/);
  const refreshed = auth.refresh(null, paired.refreshToken, 'device-123');

  assert.equal(refreshed.deviceId, 'device-123');
  assert.notEqual(refreshed.token, paired.token);
});
```

- [ ] **Step 2: Run failing refresh test**

Run: `node --test daemon/test/core.test.js --test-name-pattern "refresh accepts"`
Expected: FAIL because `refresh()` still calls `authenticate()`.

- [ ] **Step 3: Implement device-authoritative refresh**

Normalize `requestedDeviceId`, load the active device directly, validate the refresh token hash for that device, rotate refresh token, and never require the old bearer token.

- [ ] **Step 4: Update HTTP route**

Change `/api/token/refresh` to call `auth.refresh(null, body.refreshToken, body.deviceId)` and keep all refresh failures as `401 AUTH_REQUIRED` with safe messages.

- [ ] **Step 5: Run daemon auth tests**

Run: `node --test daemon/test/core.test.js daemon/test/server.test.js --test-name-pattern "refresh|pair"`
Expected: PASS.

### Task 3: Mobile Token Session Storage

**Files:**
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Test: `mobile/test/daemon_client_test.dart`

- [ ] **Step 1: Write failing mobile storage tests**

Update pair/refresh tests to expect `TokenSession` expiry persistence.

```dart
expect((await tokenStore.readAccessTokenSession('device-1'))!.expiresAt,
    DateTime.parse('2026-05-18T08:00:00.000Z'));
```

- [ ] **Step 2: Run failing mobile test**

Run: `cd mobile && flutter test test/daemon_client_test.dart --plain-name "pair stores access and refresh tokens separately"`
Expected: FAIL because `readAccessTokenSession()` does not exist.

- [ ] **Step 3: Implement `TokenSession` and store compatibility methods**

Add immutable `TokenSession`, `writeAccessTokenSession()`, `readAccessTokenSession()`, `writeRefreshTokenSession()`, and `readRefreshTokenSession()` to `SecureTokenStore`, keeping old token string methods as convenience wrappers.

- [ ] **Step 4: Persist expiry metadata from pair/refresh**

Parse `accessTokenExpiresAt` and `refreshTokenExpiresAt` from daemon responses and write session objects to the token store.

- [ ] **Step 5: Run mobile storage tests**

Run: `cd mobile && flutter test test/daemon_client_test.dart --plain-name "pair stores access and refresh tokens separately" --plain-name "refresh rotates tokens without changing device identity"`
Expected: PASS.

### Task 4: Mobile Proactive Refresh and 401 Fallback

**Files:**
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Test: `mobile/test/daemon_client_test.dart`

- [ ] **Step 1: Write failing refresh-behavior tests**

Add tests that `ensurePaired()` refreshes when `now >= accessTokenExpiresAt - refreshSkew`, and that an authorized GET receiving `401 AUTH_REQUIRED` refreshes and retries once.

```dart
expect(request.headers['authorization'], 'Bearer access-2');
```

- [ ] **Step 2: Run failing behavior tests**

Run: `cd mobile && flutter test test/daemon_client_test.dart --plain-name "ensurePaired refreshes" --plain-name "authorized request refreshes"`
Expected: FAIL because the client trusts stored access tokens and does not retry after auth failure.

- [ ] **Step 3: Add injectable clock and refresh skew**

Add `DateTime Function() now` and `Duration refreshSkew` constructor parameters with defaults of `DateTime.now` and ten minutes.

- [ ] **Step 4: Make `ensurePaired()` expiry-aware**

Read the access token session, use it only when not within skew, otherwise call `refreshToken()`. If refresh fails with `AUTH_REQUIRED`, delete stored tokens and pair again only through the existing explicit pairing path.

- [ ] **Step 5: Retry one authorized request after `401 AUTH_REQUIRED`**

Decode `401` responses, call `refreshToken()`, retry once with the new access token, and clear local auth state if refresh fails.

- [ ] **Step 6: Run mobile behavior tests**

Run: `cd mobile && flutter test test/daemon_client_test.dart`
Expected: PASS.

### Task 5: Full Verification

**Files:**
- Modify: no production files unless verification exposes a scoped defect.

- [ ] **Step 1: Run daemon tests**

Run: `npm test`
Expected: PASS.

- [ ] **Step 2: Run Flutter analysis**

Run: `cd mobile && flutter analyze`
Expected: PASS.

- [ ] **Step 3: Run Flutter tests**

Run: `cd mobile && flutter test`
Expected: PASS.

## Self-Review

- Spec coverage: daemon lifetimes, expiry response fields, refresh without access token, hash-only daemon storage, mobile expiry persistence, proactive refresh, and `401 AUTH_REQUIRED` fallback are covered.
- Placeholder scan: no `TBD`, `TODO`, or vague edge-case instructions remain.
- Type consistency: `TokenSession`, `accessTokenExpiresAt`, `refreshTokenExpiresAt`, and `AUTH_REQUIRED` names are consistent across daemon and mobile tasks.
