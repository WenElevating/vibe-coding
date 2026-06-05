'use strict';

const CODEX_APP_SERVER_STREAMING_POLICY = Object.freeze({
  persistRawDeltas: true,
  semanticCompression: false,
  rawDeltaRetentionDays: 30,
  derivedSnapshotAfterEvents: 500,
  durableSnapshotTriggers: Object.freeze(['turn/completed', 'derivedSnapshotAfterEvents']),
  maxWebSocketQueueEvents: 2000,
  slowConsumerSignal: 'conversation.replay_required'
});

module.exports = { CODEX_APP_SERVER_STREAMING_POLICY };
