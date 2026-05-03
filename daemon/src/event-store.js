'use strict';

class EventStore {
  constructor() {
    this.eventsByRun = new Map();
    this.nextSeqByRun = new Map();
  }

  append(runId, type, payload = {}) {
    const seq = this.nextSeqByRun.get(runId) || 1;
    this.nextSeqByRun.set(runId, seq + 1);
    const event = {
      type,
      seq,
      runId,
      createdAt: new Date().toISOString(),
      ...payload
    };
    if (!this.eventsByRun.has(runId)) this.eventsByRun.set(runId, []);
    this.eventsByRun.get(runId).push(event);
    return event;
  }

  list(runId, afterSeq = 0) {
    return (this.eventsByRun.get(runId) || []).filter((event) => event.seq > afterSeq);
  }
}

module.exports = { EventStore };
