'use strict';

const crypto = require('node:crypto');

function generateToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashToken(token, secret = process.env.AUTH_TOKEN_SECRET || 'development-auth-token-secret') {
  return crypto.createHmac('blake2b512', secret).update(token).digest('hex');
}

function verifyToken(token, storedHash, secret) {
  if (!token || !storedHash) return false;
  return timingSafeEqualHex(hashToken(token, secret), storedHash);
}

function hashDeviceId(deviceId, pepper) {
  return crypto.createHmac('blake2b512', pepper).update(deviceId).digest('hex');
}

const DEFAULT_ACCESS_TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const DEFAULT_REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000;

class AuthManager {
  constructor({
    store,
    now = () => Date.now(),
    authTokenSecret = process.env.AUTH_TOKEN_SECRET || 'development-auth-token-secret',
    deviceIdPepper = process.env.DEVICE_ID_PEPPER || 'development-device-id-pepper',
    accessTokenTtlMs = readDurationEnv('ACCESS_TOKEN_TTL_MS', DEFAULT_ACCESS_TOKEN_TTL_MS),
    refreshTokenTtlMs = readDurationEnv('REFRESH_TOKEN_TTL_MS', DEFAULT_REFRESH_TOKEN_TTL_MS)
  } = {}) {
    this.store = store || null;
    this.now = now;
    this.authTokenSecret = authTokenSecret;
    this.deviceIdPepper = deviceIdPepper;
    this.accessTokenTtlMs = accessTokenTtlMs;
    this.refreshTokenTtlMs = refreshTokenTtlMs;
    this.pairing = null;
    this.devices = new Map();
  }

  createPairingCode(ttlMs = 5 * 60 * 1000) {
    const now = this.now();
    if (this.pairing && !this.pairing.used && this.pairing.expiresAt > now) {
      // Reuse the active code so retries within the TTL window succeed without 429.
      return { code: this.pairing.code, expiresAt: this.pairing.expiresAt };
    }
    const code = String(crypto.randomInt(100000, 999999));
    this.pairing = { code, expiresAt: now + ttlMs, used: false };
    return { code, expiresAt: this.pairing.expiresAt };
  }

  pair(code, label = 'Android device', requestedDeviceId = null) {
    if (!this.pairing || this.pairing.used) throw authError('pairing code is not active');
    if (this.now() > this.pairing.expiresAt) throw authError('pairing code expired');
    if (code !== this.pairing.code) throw authError('invalid pairing code');
    this.pairing.used = true;
    return this.registerDevice({ requestedDeviceId, label });
  }

  registerDevice({ requestedDeviceId, label }) {
    const deviceId = normalizeRequestedDeviceId(requestedDeviceId) || crypto.randomUUID();
    const deviceIdHash = hashDeviceId(deviceId, this.deviceIdPepper);
    const now = new Date(this.now()).toISOString();
    const existing = this.store ? this.store.getDeviceByHash(deviceIdHash) : this.devices.get(deviceId);
    const device = existing || {
      id: deviceId,
      deviceIdHash,
      label,
      status: 'active',
      createdAt: now,
      lastSeenAt: now,
      allowedWorkspaceIds: new Set()
    };

    const persisted = this.store
      ? this.store.upsertDevice({
          id: deviceId,
          deviceIdHash,
          label,
          status: device.status || 'active',
          createdAt: device.createdAt || now,
          lastSeenAt: now
        })
      : device;

    const session = this.createSessionTokens();
    if (this.store) {
      this.store.saveDeviceToken({
        id: `tok_${crypto.randomUUID()}`,
        deviceId: persisted.id,
        tokenType: 'access',
        tokenHash: hashToken(session.token, this.authTokenSecret),
        expiresAt: session.accessTokenExpiresAt,
        revokedAt: null,
        createdAt: session.createdAt
      });
      this.store.saveDeviceToken({
        id: `tok_${crypto.randomUUID()}`,
        deviceId: persisted.id,
        tokenType: 'refresh',
        tokenHash: hashToken(session.refreshToken, this.authTokenSecret),
        expiresAt: session.refreshTokenExpiresAt,
        revokedAt: null,
        createdAt: session.createdAt
      });
    } else {
      this.devices.set(deviceId, {
        ...persisted,
        tokenHash: hashToken(session.token, this.authTokenSecret),
        tokenExpiresAt: session.accessTokenExpiresAt,
        refreshTokenHash: hashToken(session.refreshToken, this.authTokenSecret),
        refreshTokenExpiresAt: session.refreshTokenExpiresAt
      });
    }

    return this.sessionResponse(persisted.id, session);
  }

  getDevice(deviceId) {
    if (this.store) return this.store.getDevice(deviceId);
    return this.devices.get(deviceId) || null;
  }

  activeDeviceCount() {
    if (this.store) return this.store.countActiveDevices();
    return Array.from(this.devices.values()).filter((device) => !device.revoked && device.status !== 'revoked').length;
  }

  refresh(authHeader, refreshToken, requestedDeviceId = null) {
    const requested = normalizeRequestedDeviceId(requestedDeviceId);
    const device = requested ? this.getDevice(requested) : this.authenticate(authHeader);
    if (!device || device.revoked || device.status === 'revoked') throw authError('device not active');
    if (!this.store) {
      if (device.refreshTokenExpiresAt) {
        const refreshMs = Date.parse(device.refreshTokenExpiresAt);
        if (Number.isNaN(refreshMs) || refreshMs <= this.now()) throw authError('invalid refresh token');
      }
      if (!device.refreshTokenHash || !verifyToken(refreshToken, device.refreshTokenHash, this.authTokenSecret)) throw authError('invalid refresh token');
      const session = this.createSessionTokens();
      this.devices.set(device.id, {
        ...device,
        tokenHash: hashToken(session.token, this.authTokenSecret),
        tokenExpiresAt: session.accessTokenExpiresAt,
        refreshTokenHash: hashToken(session.refreshToken, this.authTokenSecret),
        refreshTokenExpiresAt: session.refreshTokenExpiresAt
      });
      return this.sessionResponse(device.id, session);
    }
    const stored = this.store.getValidRefreshTokenForDevice(device.id);
    if (!stored || !verifyToken(refreshToken, stored.token_hash, this.authTokenSecret)) throw authError('invalid refresh token');
    const session = this.createSessionTokens();
    this.store.revokeToken(stored.id, session.createdAt);
    this.store.saveDeviceToken({
      id: `tok_${crypto.randomUUID()}`,
      deviceId: device.id,
      tokenType: 'access',
      tokenHash: hashToken(session.token, this.authTokenSecret),
      expiresAt: session.accessTokenExpiresAt,
      revokedAt: null,
      createdAt: session.createdAt
    });
    this.store.saveDeviceToken({
      id: `tok_${crypto.randomUUID()}`,
      deviceId: device.id,
      tokenType: 'refresh',
      tokenHash: hashToken(session.refreshToken, this.authTokenSecret),
      expiresAt: session.refreshTokenExpiresAt,
      revokedAt: null,
      createdAt: session.createdAt
    });
    return this.sessionResponse(device.id, session);
  }

  sessionResponse(deviceId, session) {
    return {
      deviceId,
      token: session.token,
      refreshToken: session.refreshToken,
      accessTokenExpiresAt: session.accessTokenExpiresAt,
      refreshTokenExpiresAt: session.refreshTokenExpiresAt
    };
  }

  createSessionTokens() {
    const now = this.now();
    return {
      createdAt: new Date(now).toISOString(),
      token: generateToken(),
      refreshToken: generateToken(),
      accessTokenExpiresAt: new Date(now + this.accessTokenTtlMs).toISOString(),
      refreshTokenExpiresAt: new Date(now + this.refreshTokenTtlMs).toISOString()
    };
  }

  authenticate(authHeader) {
    const token = parseBearer(authHeader);
    if (!token) throw authError('missing bearer token');
    if (this.store) {
      const device = this.store.getDeviceByAccessTokenHash(hashToken(token, this.authTokenSecret));
      if (device) return device;
      throw authError('invalid bearer token');
    }
    for (const device of this.devices.values()) {
      if (device.revoked || device.status === 'revoked') continue;
      if (device.tokenExpiresAt) {
        const expiresMs = Date.parse(device.tokenExpiresAt);
        if (Number.isNaN(expiresMs) || expiresMs <= this.now()) continue;
      }
      if (verifyToken(token, device.tokenHash, this.authTokenSecret)) return device;
    }
    throw authError('invalid bearer token');
  }

  revokeDevice(deviceId, actorDevice) {
    if (actorDevice.id !== deviceId) {
      const error = new Error('device revocation is limited to the authenticated device in V1.1');
      error.status = 403;
      error.code = 'FORBIDDEN';
      throw error;
    }
    if (this.store) {
      this.store.revokeDevice(deviceId, new Date(this.now()).toISOString());
      return { deviceId, revoked: true };
    }
    const device = this.devices.get(deviceId);
    if (!device) throw authError('device not found');
    this.devices.set(deviceId, { ...device, revoked: true, status: 'revoked' });
    return { deviceId, revoked: true };
  }

  allowWorkspace(deviceId, workspaceId) {
    if (this.store) {
      this.store.authorizeWorkspaceForDevice(deviceId, workspaceId);
      return;
    }
    const device = this.devices.get(deviceId);
    if (device) device.allowedWorkspaceIds.add(workspaceId);
  }
}

function normalizeRequestedDeviceId(deviceId) {
  if (typeof deviceId !== 'string') return null;
  const trimmed = deviceId.trim();
  if (!/^[a-zA-Z0-9._:-]{8,128}$/.test(trimmed)) throw authError('invalid device id');
  return trimmed;
}

function parseBearer(header) {
  if (!header || typeof header !== 'string') return null;
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function timingSafeEqualHex(actual, expected) {
  const actualBuffer = Buffer.from(String(actual), 'hex');
  const expectedBuffer = Buffer.from(String(expected), 'hex');
  if (actualBuffer.length !== expectedBuffer.length) return false;
  return crypto.timingSafeEqual(actualBuffer, expectedBuffer);
}

function authError(message) {
  const error = new Error(message);
  error.status = 401;
  error.code = 'AUTH_REQUIRED';
  return error;
}

function readDurationEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

module.exports = { AuthManager, generateToken, hashToken, verifyToken, parseBearer, hashDeviceId };
