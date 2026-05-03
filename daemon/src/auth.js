'use strict';

const crypto = require('node:crypto');

function generateToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashToken(token, salt = crypto.randomBytes(16).toString('base64url')) {
  const hash = crypto.scryptSync(token, salt, 32).toString('base64url');
  return `${salt}:${hash}`;
}

function verifyToken(token, storedHash) {
  if (!token || !storedHash || !storedHash.includes(':')) return false;
  const [salt, expected] = storedHash.split(':');
  const actual = crypto.scryptSync(token, salt, 32).toString('base64url');
  return crypto.timingSafeEqual(Buffer.from(actual), Buffer.from(expected));
}

class AuthManager {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.pairing = null;
    this.devices = new Map();
  }

  createPairingCode(ttlMs = 5 * 60 * 1000) {
    const code = String(crypto.randomInt(100000, 999999));
    this.pairing = { code, expiresAt: this.now() + ttlMs, used: false };
    return { code, expiresAt: this.pairing.expiresAt };
  }

  pair(code, label = 'Android device') {
    if (!this.pairing || this.pairing.used) throw authError('pairing code is not active');
    if (this.now() > this.pairing.expiresAt) throw authError('pairing code expired');
    if (code !== this.pairing.code) throw authError('invalid pairing code');
    this.pairing.used = true;
    const token = generateToken();
    const deviceId = crypto.randomUUID();
    this.devices.set(deviceId, {
      id: deviceId,
      label,
      tokenHash: hashToken(token),
      revoked: false,
      createdAt: new Date(this.now()).toISOString(),
      allowedWorkspaceIds: new Set()
    });
    return { deviceId, token };
  }

  authenticate(authHeader) {
    const token = parseBearer(authHeader);
    if (!token) throw authError('missing bearer token');
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
    const device = this.devices.get(deviceId);
    if (!device) throw authError('device not found');
    device.revoked = true;
    return { deviceId, revoked: true };
  }

  allowWorkspace(deviceId, workspaceId) {
    const device = this.devices.get(deviceId);
    if (device) device.allowedWorkspaceIds.add(workspaceId);
  }
}

function parseBearer(header) {
  if (!header || typeof header !== 'string') return null;
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function authError(message) {
  const error = new Error(message);
  error.status = 401;
  error.code = 'AUTH_REQUIRED';
  return error;
}

module.exports = { AuthManager, generateToken, hashToken, verifyToken, parseBearer };
