'use strict';

const { buildCodexAppServerAvailability } = require('./codex-app-server-availability');

class CodexAppServerListingAdapter {
  constructor({
    enabled = false,
    installed = false,
    protocolCompatible = false,
    transportHealthy = false,
    unavailableReason = 'probe_not_run',
    lastProbeAt = null
  } = {}) {
    this.name = 'codex-app-server';
    this.displayName = 'Codex App Server';
    this.enabled = enabled;
    this.installed = installed;
    this.protocolCompatible = protocolCompatible;
    this.transportHealthy = transportHealthy;
    this.unavailableReason = unavailableReason;
    this.lastProbeAt = lastProbeAt;
  }

  detectCapabilities() {
    return buildCodexAppServerAvailability({
      enabled: this.enabled,
      installed: this.installed,
      protocolCompatible: this.protocolCompatible,
      transportHealthy: this.transportHealthy,
      unavailableReason: this.unavailableReason,
      lastProbeAt: this.lastProbeAt
    });
  }

  getCapabilities() {
    return {};
  }
}

module.exports = {
  CodexAppServerListingAdapter
};
