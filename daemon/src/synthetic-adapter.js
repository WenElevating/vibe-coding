'use strict';

const { eventTypes } = require('./protocol');
const { profileFor } = require('./adapter-profiles');

class SyntheticAdapter {
  constructor({ name = 'synthetic-jsonl', delayMs = 0 } = {}) {
    this.name = name;
    this.displayName = name;
    this.delayMs = delayMs;
  }

  async detectCapabilities() {
    return { adapter: this.name, available: true, status: 'available', version: 'synthetic', error: null };
  }

  getProfile() {
    return { ...profileFor('synthetic'), adapterId: this.name };
  }

  getCapabilities() {
    return this.getProfile().capabilities;
  }

  async startRun({ prompt, onEvent }) {
    if (this.name === 'synthetic-error') throw Object.assign(new Error('synthetic adapter error'), { code: 'ADAPTER_INVOCATION_FAILED' });
    const timer = this.delayMs ? setTimeout(() => emitSynthetic(prompt, onEvent), this.delayMs) : null;
    if (!timer) emitSynthetic(prompt, onEvent);
    return { kill() { if (timer) clearTimeout(timer); } };
  }
}

function emitSynthetic(prompt, onEvent) {
  onEvent({ type: eventTypes.ASSISTANT_DELTA, text: `synthetic response: ${prompt}` });
  onEvent({ type: eventTypes.DIFF_SUMMARY, filePath: 'synthetic.txt', additions: 1, deletions: 0, binary: false });
  onEvent({ type: eventTypes.RUN_COMPLETED, exitCode: 0 });
}

module.exports = { SyntheticAdapter };
