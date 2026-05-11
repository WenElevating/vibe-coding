'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { AuthManager, hashDeviceId, verifyToken } = require('../src/auth');
const { validateRunCreate, assertNoV1TerminalRequest } = require('../src/protocol');
const { EventStore } = require('../src/event-store');
const { WorkspaceRegistry } = require('../src/workspace');
const { AuditLog, redact } = require('../src/audit');

test('pairing issues a token and stores only token hash', () => {
  const auth = new AuthManager({ now: () => 1000 });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone');
  const device = auth.authenticate(`Bearer ${paired.token}`);

  assert.equal(device.id, paired.deviceId);
  assert.equal(device.tokenHash.includes(paired.token), false);
  assert.equal(verifyToken(paired.token, device.tokenHash), true);
});

test('pairing returns lifecycle expiry timestamps', () => {
  const auth = new AuthManager({ now: () => Date.parse('2026-05-11T08:00:00.000Z') });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone', 'device-123');

  assert.equal(paired.accessTokenExpiresAt, '2026-05-18T08:00:00.000Z');
  assert.equal(paired.refreshTokenExpiresAt, '2026-06-10T08:00:00.000Z');
  assert.equal(Object.hasOwn(paired, 'createdAt'), false);
});

test('pairing can reuse a fixed device id', () => {
  const auth = new AuthManager({ now: () => 1000 });
  const pairing1 = auth.createPairingCode();
  const first = auth.pair(pairing1.code, 'phone', 'device-123');
  const firstDevice = auth.authenticate(`Bearer ${first.token}`);

  const pairing2 = auth.createPairingCode();
  const second = auth.pair(pairing2.code, 'phone', 'device-123');
  const secondDevice = auth.authenticate(`Bearer ${second.token}`);

  assert.equal(first.deviceId, 'device-123');
  assert.equal(second.deviceId, 'device-123');
  assert.equal(firstDevice.id, 'device-123');
  assert.equal(secondDevice.id, 'device-123');
  assert.notEqual(first.token, second.token);
  assert.equal(verifyToken(second.token, secondDevice.tokenHash), true);
});

test('pairing stores hashed device identity without plaintext credentials', () => {
  const auth = new AuthManager({ now: () => 1000, deviceIdPepper: 'test-pepper' });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone', 'device-123');
  const device = auth.authenticate(`Bearer ${paired.token}`);

  assert.equal(device.deviceIdHash, hashDeviceId('device-123', 'test-pepper'));
  assert.notEqual(device.deviceIdHash, 'device-123');
  assert.equal(device.deviceIdHash.includes('device-123'), false);
  assert.equal(device.tokenHash.includes(paired.token), false);
  assert.equal(device.refreshTokenHash.includes(paired.refreshToken), false);
});

test('refresh rotates refresh token without changing device id', () => {
  const auth = new AuthManager({ now: () => 1000 });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone', 'device-123');

  const refreshed = auth.refresh(
    `Bearer ${paired.token}`,
    paired.refreshToken,
    'device-123'
  );

  assert.equal(refreshed.deviceId, 'device-123');
  assert.notEqual(refreshed.token, paired.token);
  assert.notEqual(refreshed.refreshToken, paired.refreshToken);
  assert.equal(auth.authenticate(`Bearer ${refreshed.token}`).id, 'device-123');
  assert.throws(
    () => auth.refresh(`Bearer ${refreshed.token}`, paired.refreshToken, 'device-123'),
    /invalid refresh token/
  );
});

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
  assert.notEqual(refreshed.refreshToken, paired.refreshToken);
  assert.equal(refreshed.accessTokenExpiresAt, '2026-05-11T08:00:00.030Z');
});

test('refresh rejects invalid device ids as auth failures', () => {
  const auth = new AuthManager({ now: () => Date.parse('2026-05-11T08:00:00.000Z') });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone', 'device-123');

  assert.throws(() => auth.refresh(null, paired.refreshToken, '../bad'), /invalid device id/);
});

test('expired pairing code fails', () => {
  let now = 1000;
  const auth = new AuthManager({ now: () => now });
  const pairing = auth.createPairingCode(10);
  now = 2000;
  assert.throws(() => auth.pair(pairing.code), /expired/);
});

test('V1 rejects arbitrary shell and PTY payloads', () => {
  assert.throws(() => assertNoV1TerminalRequest({ command: 'dir' }), /V1\.2 rejects/);
  assert.throws(() => assertNoV1TerminalRequest({ cwd: 'C:\\Users' }), /V1\.2 rejects/);
  assert.throws(() => assertNoV1TerminalRequest({ pty: true }), /V1\.2 rejects/);
  assert.doesNotThrow(() => validateRunCreate({ tool: 'claude', workspaceId: 'w1', prompt: 'hello' }));
});

test('workspace object authorization is enforced', () => {
  const registry = new WorkspaceRegistry();
  registry.add({ id: 'w1', name: 'one', workspacePath: '.' });
  const device = { id: 'd1', allowedWorkspaceIds: new Set() };

  assert.throws(() => registry.getAuthorized('w1', device), /not authorized/);
  device.allowedWorkspaceIds.add('w1');
  assert.equal(registry.getAuthorized('w1', device).id, 'w1');
});

test('workspace add can derive id and name from path', () => {
  const registry = new WorkspaceRegistry();
  const workspace = registry.add({ workspacePath: '.' });

  assert.match(workspace.id, /^workspace_[a-f0-9]{12}$/);
  assert.ok(workspace.name.length > 0);
  assert.ok(workspace.path.length > 0);
});

test('event replay returns ordered events after sequence', () => {
  const store = new EventStore();
  store.append('run1', 'run.started');
  store.append('run1', 'assistant.delta', { text: 'a' });
  store.append('run1', 'run.completed');

  assert.deepEqual(store.list('run1', 1).map((event) => event.seq), [2, 3]);
});

test('audit redacts token-like fields', () => {
  const audit = new AuditLog();
  const record = audit.record('pair', { token: 'secret', nested: { apiKey: 'abc', ok: true } });

  assert.equal(record.token, '[REDACTED]');
  assert.equal(record.nested.apiKey, '[REDACTED]');
  assert.equal(redact({ password: 'x' }).password, '[REDACTED]');
});
