'use strict';

const { performance } = require('node:perf_hooks');

function defaultMonoUs() {
  return Math.trunc(performance.now() * 1000);
}

class PerfTracer {
  constructor({
    enabled = false,
    writer = null,
    nowWallMs = () => Date.now(),
    nowMonoUs = defaultMonoUs
  } = {}) {
    this.enabled = enabled === true;
    this.writer = writer;
    this.nowWallMs = nowWallMs;
    this.nowMonoUs = nowMonoUs;
  }

  isEnabled() {
    return this.enabled === true;
  }

  mark(input = {}) {
    if (!this.isEnabled()) return;
    if (!this.writer || typeof this.writer.writeDaemonMark !== 'function') return;
    try {
      this.writer.writeDaemonMark({
        source: 'daemon',
        name: input.name,
        wallTimeMs: this.nowWallMs(),
        monotonicUs: this.nowMonoUs(),
        conversationId: input.conversationId ?? null,
        seq: input.seq ?? null,
        eventType: input.eventType ?? null,
        correlationId: input.correlationId ?? null,
        metadata: input.metadata ?? {}
      });
    } catch {
      // Perf tracing is diagnostic only and must never affect business behavior.
    }
  }
}

module.exports = { PerfTracer, defaultMonoUs };
