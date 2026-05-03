'use strict';

const profiles = Object.freeze({
  claude: {
    adapterId: 'claude',
    invocationMode: 'process-jsonl',
    cwdPolicy: 'workspace-root',
    capabilities: {
      supportsStreaming: true,
      supportsStructuredEvents: true,
      supportsRawOutput: true,
      supportsResume: true,
      supportsCancel: 'process-kill',
      supportsApproval: 'partial',
      supportsDiff: 'partial',
      supportsServerMode: false,
      supportsNonInteractive: true
    }
  },
  codex: {
    adapterId: 'codex',
    invocationMode: 'process-jsonl',
    cwdPolicy: 'workspace-root',
    capabilities: {
      supportsStreaming: true,
      supportsStructuredEvents: 'partial',
      supportsRawOutput: true,
      supportsResume: 'partial',
      supportsCancel: 'process-kill',
      supportsApproval: 'partial',
      supportsDiff: 'partial',
      supportsServerMode: false,
      supportsNonInteractive: true
    }
  },
  opencode: {
    adapterId: 'opencode',
    invocationMode: 'http-server',
    cwdPolicy: 'server-managed',
    capabilities: {
      supportsStreaming: 'partial',
      supportsStructuredEvents: 'partial',
      supportsRawOutput: true,
      supportsResume: 'partial',
      supportsCancel: 'api',
      supportsApproval: 'partial',
      supportsDiff: 'partial',
      supportsServerMode: true,
      supportsNonInteractive: true
    }
  },
  synthetic: {
    adapterId: 'synthetic',
    invocationMode: 'process-jsonl',
    cwdPolicy: 'workspace-root',
    capabilities: {
      supportsStreaming: true,
      supportsStructuredEvents: true,
      supportsRawOutput: true,
      supportsResume: false,
      supportsCancel: 'process-kill',
      supportsApproval: true,
      supportsDiff: true,
      supportsServerMode: false,
      supportsNonInteractive: true
    }
  }
});

function profileFor(adapterId) {
  if (adapterId.startsWith('synthetic-')) return profiles.synthetic;
  return profiles[adapterId] || null;
}

module.exports = { profiles, profileFor };
