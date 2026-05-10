'use strict';

const crypto = require('node:crypto');

function generateToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashToken(token, secret = process.env.AUTH_TOKEN_SECRET || 'development-auth-token-secret') {
  return crypto.createHmac('blake2b512', secret).update(token).digest('hex');
}

function verifyToken(token, storedHash) {
  if (!token || !storedHash) return false;
  return timingSafeEqualHex(hashToken(token), storedHash);
}

function hashDeviceId(deviceId, pepper) {
  return crypto.createHmac('blake2b512', pepper).update(deviceId).digest('hex');
}

class AuthManager {
  constructor({ store, now = () => Date.now(), deviceIdPepper = process.env.DEVICE_ID_PEPPER || 'development-device-id-pepper', accessTokenTtlMs = 15 * 60 * 1000, refreshTokenTtlMs = 30 * 24 * 60 * 60 * 1000 } = {}) {
    this.store = store || null;
    this.now = now;
    this.deviceIdPepper = deviceIdPepper;
    this.accessTokenTtlMs = accessTokenTtlMs;
    this.refreshTokenTtlMs = refreshTokenTtlMs;
    this.pairing = null;
    this.devices = new Map();
  }

  createPairingCode(ttlMs = 5 * 60 * 1000) {
    const code = String(crypto.randomInt(100000, 999999));
    this.pairing = { code, expiresAt: this.now() + ttlMs, used: false };
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

    const accessToken = generateToken();
    const refreshToken = generateToken();
    if (this.store) {
      this.store.saveDeviceToken({
        id: `tok_${crypto.randomUUID()}`,
        deviceId: persisted.id,
        tokenType: 'access',
        tokenHash: hashToken(accessToken),
        expiresAt: new Date(this.now() + this.accessTokenTtlMs).toISOString(),
        revokedAt: null,
        createdAt: now
      });
      this.store.saveDeviceToken({
        id: `tok_${crypto.randomUUID()}`,
        deviceId: persisted.id,
        tokenType: 'refresh',
        tokenHash: hashToken(refreshToken),
        expiresAt: new Date(this.now() + this.refreshTokenTtlMs).toISOString(),
        revokedAt: null,
        createdAt: now
      });
    } else {
      persisted.tokenHash = hashToken(accessToken);
      persisted.refreshTokenHash = hashToken(refreshToken);
      this.devices.set(deviceId, persisted);
    }

    return { deviceId: persisted.id, token: accessToken, refreshToken };
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
    const device = this.authenticate(authHeader);
    if (requestedDeviceId) {
      const requested = normalizeRequestedDeviceId(requestedDeviceId);
      if (requested !== device.id) throw authError('device mismatch');
    }
    if (!this.store) {
      if (!device.refreshTokenHash || !verifyToken(refreshToken, device.refreshTokenHash)) throw authError('invalid refresh token');
      const accessToken = generateToken();
      const nextRefreshToken = generateToken();
      device.tokenHash = hashToken(accessToken);
      device.refreshTokenHash = hashToken(nextRefreshToken);
      return { deviceId: device.id, token: accessToken, refreshToken: nextRefreshToken };
    }
    const stored = this.store.getValidRefreshTokenForDevice(device.id);
    if (!stored || !verifyToken(refreshToken, stored.token_hash)) throw authError('invalid refresh token');
    const accessToken = generateToken();
    const nextRefreshToken = generateToken();
    this.store.revokeToken(stored.id, new Date(this.now()).toISOString());
    this.store.saveDeviceToken({
      id: `tok_${crypto.randomUUID()}`,
      deviceId: device.id,
      tokenType: 'access',
      tokenHash: hashToken(accessToken),
      expiresAt: new Date(this.now() + this.accessTokenTtlMs).toISOString(),
      revokedAt: null,
      createdAt: new Date(this.now()).toISOString()
    });
    this.store.saveDeviceToken({
      id: `tok_${crypto.randomUUID()}`,
      deviceId: device.id,
      tokenType: 'refresh',
      tokenHash: hashToken(nextRefreshToken),
      expiresAt: new Date(this.now() + this.refreshTokenTtlMs).toISOString(),
      revokedAt: null,
      createdAt: new Date(this.now()).toISOString()
    });
    return { deviceId: device.id, token: accessToken, refreshToken: nextRefreshToken };
  }

  authenticate(authHeader) {
    const token = parseBearer(authHeader);
    if (!token) throw authError('missing bearer token');
    if (this.store) {
      const device = this.store.getDeviceByAccessTokenHash(hashToken(token));
      if (device) return device;
      throw authError('invalid bearer token');
    }
    for (const device of this.devices.values()) {
      if (!device.revoked && verifyToken(token, device.tokenHash)) return device;
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
    device.revoked = true;
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

module.exports = { AuthManager, generateToken, hashToken, verifyToken, parseBearer, hashDeviceId };
