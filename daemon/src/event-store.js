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
      ...payload,
      type,
      seq,
      runId,
      createdAt: new Date().toISOString()
    };
    if (!this.eventsByRun.has(runId)) this.eventsByRun.set(runId, []);
    const events = this.eventsByRun.get(runId);
    events.push(event);
    if (events.length > 10_000) events.splice(0, events.length - 10_000);
    return event;
  }

  list(runId, afterSeq = 0) {
    return (this.eventsByRun.get(runId) || []).filter((event) => event.seq > afterSeq);
  }

  deleteRun(runId) {
    this.eventsByRun.delete(runId);
    this.nextSeqByRun.delete(runId);
  }
}

module.exports = { EventStore };
