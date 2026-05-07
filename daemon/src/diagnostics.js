'use strict';

const os = require('node:os');

class DiagnosticsService {
  constructor({ config, adapterRegistry, auditLog, auth, workspaces, runs, runQueue, migrationService, versionInfo }) {
    this.config = config;
    this.adapterRegistry = adapterRegistry;
    this.auditLog = auditLog;
    this.auth = auth;
    this.workspaces = workspaces;
    this.runs = runs;
    this.runQueue = runQueue;
    this.migrationService = migrationService;
    this.versionInfo = versionInfo;
  }

  async status({ includeAdapters = false } = {}) {
    const adapters = includeAdapters
      ? await this.adapterRegistry.listCapabilities()
      : [];
    const runs = this.runs.publicSummaries ? this.runs.publicSummaries() : [];
    return {
      status: 'ok',
      daemonVersion: this.versionInfo.daemonVersion,
      apiVersion: this.versionInfo.apiVersion,
      platform: process.platform === 'win32' ? 'windows' : process.platform,
      os: { type: os.type(), release: os.release(), arch: os.arch() },
      mode: this.versionInfo.mode,
      lanMode: this.config.host !== '127.0.0.1',
      bindAddress: this.config.host,
      port: this.config.port,
      database: this.migrationService.getStatus(),
      counts: {
        workspaces: this.workspaces.workspaces.size,
        pairedDevices: Array.from(this.auth.devices.values()).filter((device) => !device.revoked).length,
        activeRuns: runs.filter((run) => run.status === 'running').length,
        queuedRuns: this.runQueue.list().length
      },
      security: { ptyEnabled: false, rawCommandApiEnabled: false, tokenHashing: true },
      ...(includeAdapters ? { adapters } : {}),
      auditRecords: this.auditLog.list().length
    };
  }
}

module.exports = { DiagnosticsService };
