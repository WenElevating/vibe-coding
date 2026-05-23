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
    for (const listener of this.appendListeners) listener(event);
    return event;
  }

  list(conversationId, afterSeq = 0) {
    if (this.persistentStore) return this.persistentStore.listEvents(conversationId, afterSeq);
    const seq = Number(afterSeq || 0);
    return (this.events.get(conversationId) || []).filter((event) => event.seq > seq);
  }
}

module.exports = { ConversationEventStore };
