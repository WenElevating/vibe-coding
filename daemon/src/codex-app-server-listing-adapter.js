'use strict';

const { buildCodexAppServerAvailability } = require('./codex-app-server-availability');
const { summarizeCodexAppServerCapabilityMatrix } = require('./codex-app-server/capability-matrix');
const { discoverConfiguredModels } = require('./model-discovery');

class CodexAppServerListingAdapter {
  constructor({
    enabled = false,
    installed = false,
    protocolCompatible = false,
    transportHealthy = false,
    unavailableReason = 'probe_not_run',
    lastProbeAt = null,
    availabilityState = null,
    probe = null,
    metrics = null,
    modelLister = null,
    modelDiscoveryOptions = {}
  } = {}) {
    this.name = 'codex-app-server';
    this.displayName = 'Codex App Server';
    this.enabled = enabled;
    this.installed = installed;
    this.protocolCompatible = protocolCompatible;
    this.transportHealthy = transportHealthy;
    this.unavailableReason = unavailableReason;
    this.lastProbeAt = lastProbeAt;
    this.availabilityState = availabilityState;
    this.probe = typeof probe === 'function' ? probe : null;
    this.modelLister = typeof modelLister === 'function' ? modelLister : null;
    this.modelDiscoveryOptions = modelDiscoveryOptions || {};
    this.modelCapability = defaultModelCapability();
    this.metrics = metrics || {
      probeSuccess: 0,
      probeFailure: 0,
      spawnFailure: 0,
      initializeLatencyMs: null,
      fallbackBeforeFirstRequestCount: 0,
      approvalRequestedCount: 0,
      approvalTimeoutCount: 0,
      approvalRoundTripLatencyMs: [],
      transportCloseCount: 0,
      runErrorAfterTurnStartedCount: 0,
      orphanProcessCleanupCount: 0
    };
  }

  async detectCapabilities() {
    const current = this.currentInput();
    let availability = buildCodexAppServerAvailability(current);
    if (this.probe && shouldProbe(availability, current)) {
      const probed = await this.probe();
      const nextInput = {
        ...current,
        ...probed
      };
      availability = buildCodexAppServerAvailability(nextInput);
      if (this.availabilityState) this.availabilityState.current = nextInput;
      if (availability.selectable) this.metrics.probeSuccess += 1;
      else this.metrics.probeFailure += 1;
    }
    return {
      ...availability,
      diagnostics: {
        metrics: snapshotMetrics(this.metrics),
        capabilityMatrix: summarizeCodexAppServerCapabilityMatrix()
      }
    };
  }

  currentInput() {
    if (this.availabilityState && this.availabilityState.current) {
      return this.availabilityState.current;
    }
    return {
      enabled: this.enabled,
      installed: this.installed,
      protocolCompatible: this.protocolCompatible,
      transportHealthy: this.transportHealthy,
      unavailableReason: this.unavailableReason,
      lastProbeAt: this.lastProbeAt
    };
  }

  getCapabilities() {
    return {};
  }

  async getModelCapability(status = null) {
    const availability = status || buildCodexAppServerAvailability(this.currentInput());
    const appServerModels = availability.selectable && this.modelLister
      ? await this.modelLister().catch(() => null)
      : null;
    this.modelCapability = appServerModels || configuredModelCapability(this.modelDiscoveryOptions);
    return this.modelCapability;
  }
}

function snapshotMetrics(metrics) {
  const approvalRoundTripLatency = Array.isArray(metrics.approvalRoundTripLatencyMs)
    ? metrics.approvalRoundTripLatencyMs.slice(-20).filter(Number.isFinite)
    : [];
  return {
    app_server_probe_success: Number(metrics.probeSuccess || 0),
    app_server_probe_failure: Number(metrics.probeFailure || 0),
    app_server_spawn_failure: Number(metrics.spawnFailure || 0),
    app_server_initialize_latency: Number.isFinite(metrics.initializeLatencyMs) ? metrics.initializeLatencyMs : null,
    fallback_before_first_request_count: Number(metrics.fallbackBeforeFirstRequestCount || 0),
    run_error_after_side_effect_boundary_count: Number(metrics.runErrorAfterTurnStartedCount || 0),
    approval_requested_count: Number(metrics.approvalRequestedCount || 0),
    approval_timeout_count: Number(metrics.approvalTimeoutCount || 0),
    approval_round_trip_latency: approvalRoundTripLatency,
    transport_close_count: Number(metrics.transportCloseCount || 0),
    orphan_process_cleanup_count: Number(metrics.orphanProcessCleanupCount || 0)
  };
}

function shouldProbe(availability, input) {
  return input?.enabled === true &&
    input.installed === true &&
    input.protocolCompatible === true &&
    availability.selectable !== true &&
    availability.unavailableReason === 'probe_not_run';
}

function defaultModelCapability() {
  return { models: [], selectedModel: null, canSelectModel: true };
}

function configuredModelCapability(modelDiscoveryOptions) {
  return {
    ...discoverConfiguredModels({
      ...(modelDiscoveryOptions || {}),
      adapter: 'codex'
    }),
    canSelectModel: true
  };
}

module.exports = {
  CodexAppServerListingAdapter
};
