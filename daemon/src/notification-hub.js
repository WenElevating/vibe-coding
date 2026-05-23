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
    this.wss = new WebSocketServer({ noServer: true });
    this.unsubscribeAppend = null;
  }

  start() {
    if (this.unsubscribeAppend) return;
    this.unsubscribeAppend = this.conversationEventStore.onAppend((event) => {
      this.publishConversationEvent(event);
    });
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
          ws.close(1008, 'Bearer token required');
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
      id: `ws_${crypto.randomUUID()}`,
      ws,
      device,
      subscriptions: new Map(),
      pendingFrameCount: 0,
      generationCounter: 0,
      alive: true,
      closed: false,
      authAgeTimer: null,
      authExpiresAt: device.tokenExpiresAt || device.token_expires_at || null
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
        this.closeWebSocket(connection, 1008, 'TOKEN_EXPIRED');
      }
    }, this.websocketMaxConnectionAgeMs);
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
    connection.subscriptions.clear();
  }

  close() {
    if (this.unsubscribeAppend) {
      this.unsubscribeAppend();
      this.unsubscribeAppend = null;
    }
    for (const connection of Array.from(this.connections.values())) {
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
      connection.ws.send(JSON.stringify(frame), () => {
        connection.pendingFrameCount = Math.max(0, (connection.pendingFrameCount || 0) - 1);
      });
    } catch (error) {
      connection.pendingFrameCount = Math.max(0, (connection.pendingFrameCount || 0) - 1);
      throw error;
    }
    return true;
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
        this.sendError(connection, {
          id: frame.id,
          topic: frame.topic,
          scope: frame.scope,
          code: error.code || notificationErrorCodes.INTERNAL_ERROR,
          message: error.message
        });
      });
      return;
    }
    if (frame.type === 'unsubscribe') {
      connection.subscriptions.delete(subscriptionKey(frame.topic, frame.scope));
    }
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
    connection.subscriptions.set(key, subscription);
    this.send(connection, createSubscribedFrame(frame));
    const replayEvents = this.conversations.listEvents(conversation.id, frame.afterSeq, connection.device);
    if (replayEvents.length > this.maxReplayEvents) {
      connection.subscriptions.delete(key);
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
  }

  async sendReplayBatches(connection, subscription, events) {
    const sentSeqs = new Set();
    for (let index = 0; index < events.length; index += this.replayBatchSize) {
      if (!this.isCurrentSubscription(connection, subscription)) return;
      for (const event of events.slice(index, index + this.replayBatchSize)) {
        sentSeqs.add(event.seq);
        this.send(connection, createEventFrame({ topic: subscription.topic, scope: subscription.scope, event }));
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
    for (const connection of this.connections.values()) {
      const scope = { conversationId: event.conversationId };
      const key = subscriptionKey(notificationTopics.CONVERSATION_EVENTS, scope);
      const subscription = connection.subscriptions.get(key);
      if (!subscription) continue;
      if (!this.isLiveSubscriptionAuthorized(connection, subscription)) continue;
      if (subscription.replaying) {
        subscription.queuedLiveEvents.push(event);
        continue;
      }
      this.send(connection, createEventFrame({ topic: subscription.topic, scope: subscription.scope, event }));
    }
  }

  isLiveSubscriptionAuthorized(connection, subscription) {
    try {
      this.conversations.requireConversation(subscription.conversationId, connection.device);
      return true;
    } catch {
      connection.subscriptions.delete(subscription.key);
      this.sendError(connection, {
        topic: subscription.topic,
        scope: subscription.scope,
        code: notificationErrorCodes.FORBIDDEN,
        message: 'Device is not authorized for this conversation.'
      });
      return false;
    }
  }
}

module.exports = { NotificationHub };
