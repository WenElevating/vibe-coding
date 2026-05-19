'use strict';

const crypto = require('node:crypto');
const canonicalize = require('canonicalize');

function canonicalizeForHash(value) {
  const normalized = normalizeHashValue(value);
  const serialized = canonicalize(normalized);
  if (typeof serialized !== 'string') {
    throw new Error('canonicalization failed');
  }
  return serialized;
}

function sha256Hex(canonicalJson) {
  if (typeof canonicalJson !== 'string') {
    throw new TypeError('canonicalJson must be a string');
  }
  return crypto
    .createHash('sha256')
    .update(Buffer.from(canonicalJson, 'utf8'))
    .digest('hex');
}

function sha256PrefixHex(canonicalJson, byteCount) {
  if (!Number.isSafeInteger(byteCount) || byteCount <= 0) {
    throw new TypeError('byteCount must be a positive safe integer');
  }
  return sha256Hex(canonicalJson).slice(0, byteCount * 2);
}

function normalizeHashValue(value) {
  if (value === null) return null;
  if (value === undefined) {
    throw new TypeError('hash inputs may not contain undefined');
  }
  if (typeof value === 'string') return value.normalize('NFC');
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) {
      throw new TypeError('hash inputs may contain only safe integer numbers');
    }
    return value;
  }
  if (Array.isArray(value)) return value.map(normalizeHashValue);
  if (typeof value === 'object') {
    if (!isPlainObject(value)) {
      throw new TypeError('hash inputs may contain only plain objects');
    }
    const output = {};
    for (const key of Object.keys(value)) {
      const normalized = normalizeHashValue(value[key]);
      const normalizedKey = key.normalize('NFC');
      if (Object.prototype.hasOwnProperty.call(output, normalizedKey)) {
        throw new TypeError('hash inputs may not contain duplicate object keys after NFC normalization');
      }
      output[normalizedKey] = normalized;
    }
    return output;
  }
  throw new TypeError(`unsupported hash value type: ${typeof value}`);
}

function isPlainObject(value) {
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

module.exports = {
  canonicalizeForHash,
  sha256Hex,
  sha256PrefixHex,
  normalizeHashValue
};
