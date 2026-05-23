'use strict';

const crypto = require('node:crypto');
const { WebSocket, WebSocketServer } = require('ws');
const {
  notificationTopics,
  createHelloFrame,
  createErrorFrame
} = require('./notification-protocol');

class NotificationHub {
  constructor({
    auth,
    conversations,
    version,
    heartbeatIntervalMs = 25000,
    maxReplayEvents = 1000,
    now = () => new Date()
  }) {
    this.auth = auth;
    this.conversations = conversations;
    this.version = version;
    this.heartbeatIntervalMs = heartbeatIntervalMs;
    this.maxReplayEvents = maxReplayEvents;
    this.now = now;
    this.connections = new Map();
    this.wss = new WebSocketServer({ noServer: true });
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
      generationCounter: 0,
      alive: true,
      authExpiresAt: device.tokenExpiresAt || device.token_expires_at || null
    };
    this.connections.set(connection.id, connection);
    ws.on('pong', () => { connection.alive = true; });
    ws.on('close', () => this.closeConnection(connection));
    ws.on('error', () => this.closeConnection(connection));
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
    this.connections.delete(connection.id);
    connection.subscriptions.clear();
  }

  close() {
    for (const connection of this.connections.values()) {
      connection.subscriptions.clear();
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

  send(connection, frame) {
    if (connection.ws.readyState !== WebSocket.OPEN) return false;
    connection.ws.send(JSON.stringify(frame));
    return true;
  }

  sendError(connection, options) {
    this.send(connection, createErrorFrame(options));
  }
}

module.exports = { NotificationHub };
