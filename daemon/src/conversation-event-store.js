'use strict';

class ConversationEventStore {
  constructor({ now = () => new Date(), persistentStore = null } = {}) {
    this.now = now;
    this.persistentStore = persistentStore;
    this.events = new Map();
    this.appendListeners = new Set();
  }

  onAppend(listener) {
    this.appendListeners.add(listener);
    return () => this.appendListeners.delete(listener);
  }

  append(conversationId, type, payload = {}) {
    if (!conversationId) throw new Error('conversationId is required');
    if (!type) throw new Error('event type is required');
    const list = this.events.get(conversationId) || [];
    const seq = this.persistentStore
      ? this.persistentStore.nextEventSeq(conversationId)
      : list.length + 1;
    const event = {
      seq,
      conversationId,
      type,
      createdAt: this.now().toISOString(),
      ...payload
    };
    if (this.persistentStore) this.persistentStore.appendEvent(event);
    list.push(event);
    this.events.set(conversationId, list);
    for (const listener of this.appendListeners) {
      try {
        listener(event);
      } catch {
        // Append listeners are best-effort notifications after persistence.
      }
    }
    return event;
  }

  listAfter(conversationId, afterSeq = 0) {
    if (this.persistentStore) {
      if (typeof this.persistentStore.listEventsAfter === 'function') {
        return this.persistentStore.listEventsAfter(conversationId, afterSeq);
      }
      return this.persistentStore.listEvents(conversationId, afterSeq);
    }
    const seq = Number(afterSeq || 0);
    return (this.events.get(conversationId) || [])
      .filter((event) => event.seq > seq)
      .sort((left, right) => left.seq - right.seq);
  }

  listTail(conversationId, limit = 80) {
    if (this.persistentStore) {
      if (typeof this.persistentStore.listEventsTail === 'function') {
        return this.persistentStore.listEventsTail(conversationId, limit);
      }
      const allEvents = this.listAfter(conversationId, 0);
      const events = allEvents.slice(-clampEventPageLimit(limit));
      return eventPage(events, events[0] ? allEvents.some((event) => event.seq < events[0].seq) : false);
    }
    const events = (this.events.get(conversationId) || [])
      .slice()
      .sort((left, right) => right.seq - left.seq)
      .slice(0, clampEventPageLimit(limit))
      .reverse();
    return eventPage(events, this.hasEventsBefore(conversationId, events[0]?.seq));
  }

  listBefore(conversationId, beforeSeq, limit = 80) {
    if (this.persistentStore) {
      if (typeof this.persistentStore.listEventsBefore === 'function') {
        return this.persistentStore.listEventsBefore(conversationId, beforeSeq, limit);
      }
      const seq = Number(beforeSeq);
      const allEvents = this.listAfter(conversationId, 0);
      const events = allEvents
        .filter((event) => event.seq < seq)
        .slice(-clampEventPageLimit(limit));
      return eventPage(events, events[0] ? allEvents.some((event) => event.seq < events[0].seq) : false);
    }
    const seq = Number(beforeSeq);
    const events = (this.events.get(conversationId) || [])
      .filter((event) => event.seq < seq)
      .sort((left, right) => right.seq - left.seq)
      .slice(0, clampEventPageLimit(limit))
      .reverse();
    return eventPage(events, this.hasEventsBefore(conversationId, events[0]?.seq));
  }

  hasEventsBefore(conversationId, seq) {
    if (seq == null) return false;
    return (this.events.get(conversationId) || []).some((event) => event.seq < seq);
  }

  list(conversationId, afterSeq = 0) {
    return this.listAfter(conversationId, afterSeq);
  }
}

function clampEventPageLimit(limit) {
  const parsed = Number(limit);
  if (!Number.isFinite(parsed)) return 80;
  return Math.max(1, Math.min(Math.trunc(parsed), 200));
}

function eventPage(events, hasMoreBefore) {
  return {
    events,
    oldestSeq: events[0]?.seq ?? null,
    newestSeq: events.at(-1)?.seq ?? null,
    hasMoreBefore: Boolean(hasMoreBefore)
  };
}

module.exports = { ConversationEventStore };
