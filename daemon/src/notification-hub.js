'use strict';

const crypto = require('node:crypto');
const { WebSocket, WebSocketServer } = require('ws');
const {
  notificationTopics,
  notificationErrorCodes,
  parseClientFrame,
  subscriptionKey,
  createHelloFrame,
  createSubscribedFrame,
  createEventFrame,
  createErrorFrame
} = require('./notification-protocol');

function createWebSocketConnectionId() {
  return `ws_${crypto.randomUUID()}`;
}

class NotificationHub {
  constructor({
    auth,
    conversations,
    conversationEventStore,
    version,
    heartbeatIntervalMs = 25000,
    maxReplayEvents = 1000,
    replayBatchSize = 100,
    maxBufferedBytes = 1024 * 1024,
    maxQueuedFrames = 500,
    websocketMaxConnectionAgeMs = 60 * 60 * 1000,
    now = () => new Date()
  }) {
    this.auth = auth;
    this.conversations = conversations;
    this.conversationEventStore = conversationEventStore;
    this.version = version;
    this.heartbeatIntervalMs = heartbeatIntervalMs;
    this.maxReplayEvents = maxReplayEvents;
    this.replayBatchSize = replayBatchSize;
    this.maxBufferedBytes = maxBufferedBytes;
    this.maxQueuedFrames = maxQueuedFrames;
    this.websocketMaxConnectionAgeMs = websocketMaxConnectionAgeMs;
    this.now = now;
    this.connections = new Map();
    this.conversationSubscriptions = new Map();
    this.serializedFrames = new WeakMap();
    this.wss = new WebSocketServer({ noServer: true });
    this.unsubscribeAppend = null;
    this.heartbeatTimer = null;
    this.onReplayBatchSent = null;
  }

  start() {
    if (!this.unsubscribeAppend) {
      this.unsubscribeAppend = this.conversationEventStore.onAppend((event) => {
        this.publishConversationEvent(event);
      });
    }
    if (!this.heartbeatTimer && this.heartbeatIntervalMs > 0) {
      this.heartbeatTimer = setInterval(() => {
        this.runHeartbeat();
      }, this.heartbeatIntervalMs);
      if (typeof this.heartbeatTimer.unref === 'function') {
        this.heartbeatTimer.unref();
      }
    }
  }

  attach(server) {
    server.on('upgrade', (req, socket, head) => {
      if (this.upgradePath(req) !== '/api/notifications/ws') {
        socket.destroy();
        return;
      }

      let device = null;
      try {
        device = this.auth.authenticate(req.headers.authorization);
      } catch {
        this.wss.handleUpgrade(req, socket, head, (ws) => {
          ws.close(1008, notificationErrorCodes.AUTH_REQUIRED);
        });
        return;
      }

      this.wss.handleUpgrade(req, socket, head, (ws) => {
        this.acceptConnection(ws, device);
      });
    });
  }

  upgradePath(req) {
    try {
      return new URL(req.url || '', `http://${req.headers.host || 'localhost'}`).pathname;
    } catch {
      return null;
    }
  }

  acceptConnection(ws, device) {
    const connection = {
      id: createWebSocketConnectionId(),
      ws,
      device,
      subscriptions: new Map(),
      pendingFrameCount: 0,
      generationCounter: 0,
      alive: true,
      closed: false,
      authAgeTimer: null,
      authExpiresAt: device.tokenExpiresAt || null
    };
    this.connections.set(connection.id, connection);
    ws.on('pong', () => { connection.alive = true; });
    ws.on('message', (raw) => this.handleMessage(connection, raw));
    ws.on('close', () => this.closeConnection(connection));
    ws.on('error', () => this.closeConnection(connection));
    connection.authAgeTimer = setTimeout(() => {
      try {
        this.sendError(connection, {
          code: notificationErrorCodes.TOKEN_EXPIRED,
          message: 'WebSocket authorization expired.'
        }, { bypassBackpressure: true });
      } finally {
        this.closeWebSocket(connection, 1008, notificationErrorCodes.TOKEN_EXPIRED);
      }
    }, this.connectionAuthTimeoutMs(connection.authExpiresAt));
    setImmediate(() => {
      this.send(connection, createHelloFrame({
        connectionId: connection.id,
        heartbeatIntervalMs: this.heartbeatIntervalMs,
        authExpiresAt: connection.authExpiresAt,
        daemonVersion: this.version.daemonVersion,
        topics: [notificationTopics.CONVERSATION_EVENTS],
        maxReplayEvents: this.maxReplayEvents
      }));
    });
  }

  closeConnection(connection) {
    if (connection.closed) return;
    connection.closed = true;
    if (connection.authAgeTimer) {
      clearTimeout(connection.authAgeTimer);
      connection.authAgeTimer = null;
    }
    this.connections.delete(connection.id);
    this.removeAllSubscriptions(connection);
  }

  runHeartbeat() {
    for (const connection of this.connections.values()) {
      if (connection.closed) continue;
      if (!connection.alive) {
        this.terminateConnection(connection);
        continue;
      }
      connection.alive = false;
      try {
        if (typeof connection.ws.ping === 'function') {
          connection.ws.ping();
        }
      } catch {
        this.terminateConnection(connection);
      }
    }
  }

  terminateConnection(connection) {
    try {
      if (typeof connection.ws.terminate === 'function') {
        connection.ws.terminate();
      } else if (
        connection.ws.readyState === WebSocket.OPEN ||
        connection.ws.readyState === WebSocket.CONNECTING
      ) {
        connection.ws.close(1001, 'Heartbeat missed');
      }
    } catch {
      // Termination is best-effort; closeConnection performs local cleanup.
    } finally {
      this.closeConnection(connection);
    }
  }

  close() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    if (this.unsubscribeAppend) {
      this.unsubscribeAppend();
      this.unsubscribeAppend = null;
    }
    for (const connection of this.connections.values()) {
      this.closeConnection(connection);
      try {
        if (connection.ws.readyState === WebSocket.OPEN || connection.ws.readyState === WebSocket.CONNECTING) {
          connection.ws.close(1001, 'Notification hub shutting down');
        } else if (connection.ws.readyState === WebSocket.CLOSING) {
          connection.ws.terminate();
        }
      } catch {
        // Shutdown must remain best-effort during test and daemon teardown.
      }
    }
    this.connections.clear();
    this.conversationSubscriptions.clear();
    try {
      this.wss.close();
    } catch {
      // ws.close() may throw if the server is already closing or closed.
    }
  }

  closeWebSocket(connection, code, reason) {
    try {
      if (connection.ws.readyState === WebSocket.OPEN || connection.ws.readyState === WebSocket.CONNECTING) {
        connection.ws.close(code, reason);
      }
    } catch {
      // Closing is best-effort; close/error handlers perform final cleanup.
    }
  }

  send(connection, frame, { bypassBackpressure = false } = {}) {
    if (connection.ws.readyState !== WebSocket.OPEN) return false;
    if (
      !bypassBackpressure &&
      (
        connection.ws.bufferedAmount > this.maxBufferedBytes ||
        connection.pendingFrameCount >= this.maxQueuedFrames
      )
    ) {
      this.sendError(connection, {
        code: notificationErrorCodes.BACKPRESSURE,
        message: 'WebSocket client is not keeping up with notification traffic.'
      }, { bypassBackpressure: true });
      this.closeWebSocket(connection, 1013, 'BACKPRESSURE');
      return false;
    }
    connection.pendingFrameCount = (connection.pendingFrameCount || 0) + 1;
    try {
      connection.ws.send(this.serializeFrame(frame), () => {
        connection.pendingFrameCount = Math.max(0, (connection.pendingFrameCount || 0) - 1);
      });
    } catch (error) {
      connection.pendingFrameCount = Math.max(0, (connection.pendingFrameCount || 0) - 1);
      throw error;
    }
    return true;
  }

  serializeFrame(frame) {
    let serialized = this.serializedFrames.get(frame);
    if (!serialized) {
      serialized = JSON.stringify(frame);
      this.serializedFrames.set(frame, serialized);
    }
    return serialized;
  }

  sendError(connection, options, sendOptions = {}) {
    this.send(connection, createErrorFrame(options), sendOptions);
  }

  handleMessage(connection, raw) {
    let frame;
    try {
      frame = parseClientFrame(raw);
    } catch (error) {
      this.sendError(connection, {
        code: error.code || notificationErrorCodes.INVALID_MESSAGE,
        message: error.message
      });
      return;
    }
    if (frame.type === 'subscribe') {
      this.subscribe(connection, frame).catch((error) => {
        const code = this.notificationErrorCodeFor(error);
        this.sendError(connection, {
          id: frame.id,
          topic: frame.topic,
          scope: frame.scope,
          code,
          message: error.message
        });
        if (code === notificationErrorCodes.INTERNAL_ERROR) {
          this.closeWebSocket(connection, 1011, notificationErrorCodes.INTERNAL_ERROR);
        }
      });
      return;
    }
    if (frame.type === 'unsubscribe') {
      this.removeSubscription(connection, subscriptionKey(frame.topic, frame.scope));
    }
  }

  connectionAuthTimeoutMs(authExpiresAt) {
    const maxAge = Number.isFinite(this.websocketMaxConnectionAgeMs)
      ? Math.max(0, this.websocketMaxConnectionAgeMs)
      : 0;
    const expiresAtMs = Date.parse(authExpiresAt || '');
    if (!Number.isFinite(expiresAtMs)) return maxAge;
    const now = this.now();
    const nowMs = now instanceof Date ? now.getTime() : Number(now);
    if (!Number.isFinite(nowMs)) return maxAge;
    return Math.min(maxAge, Math.max(0, expiresAtMs - nowMs));
  }

  notificationErrorCodeFor(error) {
    if (
      error?.code === 'NOT_FOUND' ||
      error?.status === 403 ||
      error?.status === 404
    ) {
      return notificationErrorCodes.FORBIDDEN;
    }
    if (Object.values(notificationErrorCodes).includes(error?.code)) {
      return error.code;
    }
    return notificationErrorCodes.INTERNAL_ERROR;
  }

  async subscribe(connection, frame) {
    const conversation = this.conversations.requireConversation(frame.scope.conversationId, connection.device);
    const key = subscriptionKey(frame.topic, frame.scope);
    const generation = ++connection.generationCounter;
    const subscription = {
      key,
      generation,
      topic: frame.topic,
      scope: frame.scope,
      conversationId: conversation.id,
      replaying: true,
      queuedLiveEvents: []
    };
    this.addSubscription(connection, subscription);
    try {
      this.send(connection, createSubscribedFrame(frame));
      const replayEvents = this.conversations.listEvents(conversation.id, frame.afterSeq, connection.device);
      if (replayEvents.length > this.maxReplayEvents) {
        this.removeSubscription(connection, key);
        this.sendError(connection, {
          id: frame.id,
          topic: frame.topic,
          scope: frame.scope,
          code: notificationErrorCodes.REPLAY_TRUNCATED,
          message: `Replay has ${replayEvents.length} events, which exceeds ${this.maxReplayEvents}.`
        });
        return;
      }
      await this.sendReplayBatches(connection, subscription, replayEvents);
    } catch (error) {
      this.removeSubscription(connection, key);
      throw error;
    }
  }

  async sendReplayBatches(connection, subscription, events) {
    const sentSeqs = new Set();
    for (let index = 0; index < events.length; index += this.replayBatchSize) {
      if (!this.isCurrentSubscription(connection, subscription)) return;
      for (const event of events.slice(index, index + this.replayBatchSize)) {
        sentSeqs.add(event.seq);
        this.send(connection, createEventFrame({ topic: subscription.topic, scope: subscription.scope, event }));
      }
      if (this.onReplayBatchSent) {
        try {
          this.onReplayBatchSent({ connection, subscription });
        } catch {
          // Test hooks must not change production replay behavior.
        }
      }
      await new Promise((resolve) => setImmediate(resolve));
    }
    if (!this.isCurrentSubscription(connection, subscription)) return;
    subscription.replaying = false;
    const queued = subscription.queuedLiveEvents
      .filter((event) => !sentSeqs.has(event.seq))
      .sort((a, b) => a.seq - b.seq);
    subscription.queuedLiveEvents = [];
    for (const event of queued) {
      if (!this.isCurrentSubscription(connection, subscription)) return;
      if (!this.isLiveSubscriptionAuthorized(connection, subscription)) return;
      this.send(connection, createEventFrame({ topic: subscription.topic, scope: subscription.scope, event }));
    }
  }

  isCurrentSubscription(connection, subscription) {
    return connection.subscriptions.get(subscription.key)?.generation === subscription.generation;
  }

  publishConversationEvent(event) {
    const subscriptions = this.conversationSubscriptions.get(event.conversationId);
    if (!subscriptions || subscriptions.size === 0) return;
    const frame = createEventFrame({
      topic: notificationTopics.CONVERSATION_EVENTS,
      scope: { conversationId: event.conversationId },
      event
    });
    for (const subscription of subscriptions) {
      const connection = subscription.connection;
      if (!connection || connection.closed) continue;
      if (!this.isCurrentSubscription(connection, subscription)) continue;
      if (!this.isLiveSubscriptionAuthorized(connection, subscription)) continue;
      if (subscription.replaying) {
        subscription.queuedLiveEvents.push(event);
        continue;
      }
      this.send(connection, frame);
    }
  }

  isLiveSubscriptionAuthorized(connection, subscription) {
    try {
      this.conversations.requireConversation(subscription.conversationId, connection.device);
      return true;
    } catch {
      this.removeSubscription(connection, subscription.key);
      this.sendError(connection, {
        topic: subscription.topic,
        scope: subscription.scope,
        code: notificationErrorCodes.FORBIDDEN,
        message: 'Device is not authorized for this conversation.'
      });
      return false;
    }
  }

  addSubscription(connection, subscription) {
    this.removeSubscription(connection, subscription.key);
    subscription.connection = connection;
    connection.subscriptions.set(subscription.key, subscription);
    let subscriptions = this.conversationSubscriptions.get(subscription.conversationId);
    if (!subscriptions) {
      subscriptions = new Set();
      this.conversationSubscriptions.set(subscription.conversationId, subscriptions);
    }
    subscriptions.add(subscription);
  }

  removeSubscription(connection, key) {
    const subscription = connection.subscriptions.get(key);
    if (!subscription) return false;
    connection.subscriptions.delete(key);
    const subscriptions = this.conversationSubscriptions.get(subscription.conversationId);
    if (subscriptions) {
      subscriptions.delete(subscription);
      if (subscriptions.size === 0) {
        this.conversationSubscriptions.delete(subscription.conversationId);
      }
    }
    subscription.connection = null;
    return true;
  }

  removeAllSubscriptions(connection) {
    for (const key of Array.from(connection.subscriptions.keys())) {
      this.removeSubscription(connection, key);
    }
    connection.subscriptions.clear();
  }
}

module.exports = { NotificationHub };
