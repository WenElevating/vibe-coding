'use strict';

const crypto = require('node:crypto');

function createPerfConfig({
  env = process.env,
  now = () => new Date(),
  randomSuffix = () => crypto.randomBytes(3).toString('hex')
} = {}) {
  const enabled = env.VIBE_PERF_TRACE === '1';
  const state = { runId: null, startedAt: null };
  return {
    get enabled() { return enabled; },
    sampleRate: 1,
    maxQueueSize: 2000,
    maxBatchSize: 200,
    maxMetadataBytes: 1024,
    ensureRun() {
      if (!enabled) return null;
      if (state.runId == null) {
        const startedAt = now().toISOString();
        const timestamp = startedAt.replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
        state.runId = `perf_${timestamp}_${randomSuffix()}`;
        state.startedAt = startedAt;
      }
      return { id: state.runId, startedAt: state.startedAt };
    }
  };
}

module.exports = { createPerfConfig };
