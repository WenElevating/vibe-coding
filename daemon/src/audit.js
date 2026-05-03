'use strict';

class AuditLog {
  constructor() {
    this.records = [];
  }

  record(type, payload) {
    const record = { type, createdAt: new Date().toISOString(), ...redact(payload) };
    this.records.push(record);
    return record;
  }

  list() {
    return [...this.records];
  }
}

function redact(value) {
  if (!value || typeof value !== 'object') return value;
  const copy = Array.isArray(value) ? [] : {};
  for (const [key, item] of Object.entries(value)) {
    if (/token|secret|password|key/i.test(key)) copy[key] = '[REDACTED]';
    else copy[key] = item && typeof item === 'object' ? redact(item) : item;
  }
  return copy;
}

module.exports = { AuditLog, redact };
