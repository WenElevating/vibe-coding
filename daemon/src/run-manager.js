'use strict';

const crypto = require('node:crypto');
const { eventTypes, validateRunCreate, assertNoV1TerminalRequest, normalizeAdapterError } = require('./protocol');

class RunManager {
  constructor({ workspaces, eventStore, adapterRegistry, auditLog, runQueue }) {
    this.workspaces = workspaces;
    this.eventStore = eventStore;
    this.adapterRegistry = adapterRegistry;
    this.auditLog = auditLog;
    this.runQueue = runQueue;
    this.runs = new Map();
  }

  createRun(payload, device) {
    const input = validateRunCreate(payload);
    const workspace = this.workspaces.getAuthorized(input.workspaceId, device);
    const runId = `run_${crypto.randomUUID()}`;
    const run = {
      id: runId,
      tool: input.tool,
      workspaceId: workspace.id,
      deviceId: device.id,
      prompt: input.prompt,
      pendingPrompts: [],
      cliSessionId: null,
      permissionMode: input.permissionMode || 'default',
      resumeRequested: false,
      status: 'created',
      createdAt: new Date().toISOString(),
      child: null
    };
    this.runs.set(runId, run);
    const queueResult = this.runQueue.submit(run);
    if (queueResult.state === 'queued') {
      this.eventStore.append(runId, eventTypes.RUN_QUEUED, { workspaceId: workspace.id, reason: queueResult.item.reason, position: queueResult.item.position });
      this.eventStore.append(runId, eventTypes.QUEUE_UPDATED, { queue: this.runQueue.list() });
      return publicRun(run);
    }
    this.startRunProcess(run, workspace);
    return publicRun(run);
  }

  startRunProcess(run, workspace) {
    const adapter = this.adapterRegistry.get(run.tool);
    run.status = 'running';
    this.eventStore.append(run.id, eventTypes.RUN_STARTED, { tool: run.tool, workspaceId: workspace.id });
    Promise.resolve(adapter.startRun({
      prompt: run.prompt,
      workspacePath: workspace.path,
      sessionId: run.resumeRequested === true ? run.cliSessionId : null,
      resume: run.resumeRequested === true,
      permissionMode: run.permissionMode || 'default',
      onEvent: (event) => this.recordAdapterEvent(run, event)
    })).then((child) => {
      run.resumeRequested = false;
      run.child = child;
    }).catch((error) => {
      run.status = 'failed';
      this.eventStore.append(run.id, eventTypes.ADAPTER_ERROR, normalizeAdapterError(run.tool, error));
      this.eventStore.append(run.id, eventTypes.RUN_FAILED, { error: error.message });
      this.releaseQueue(run);
    });
  }

  publicSummaries() {
    return Array.from(this.runs.values()).map(publicRun);
  }

  listRuns(device, filters = {}) {
    return Array.from(this.runs.values())
      .filter((run) => run.deviceId === device.id)
      .filter((run) => !filters.tool || run.tool === filters.tool)
      .filter((run) => !filters.workspaceId || run.workspaceId === filters.workspaceId)
      .filter((run) => !filters.status || run.status === filters.status)
      .map(publicRun);
  }

  getRun(runId, device) {
    const run = this.runs.get(runId);
    if (!run || run.deviceId !== device.id) throw notFound('run not found');
    return run;
  }

  activeWorkspaceRuns(workspaceId, device) {
    return Array.from(this.runs.values())
      .filter((run) => run.workspaceId === workspaceId)
      .filter((run) => run.deviceId === device.id)
      .filter((run) => run.status === 'running' || run.status === 'queued');
  }

  cancelWorkspaceRuns(workspaceId, device) {
    const active = this.activeWorkspaceRuns(workspaceId, device);
    for (const run of active) this.cancelRun(run.id, device);
    return active.map(publicRun);
  }

  cancelRun(runId, device) {
    const run = this.getRun(runId, device);
    if (run.status === 'queued') {
      this.runQueue.cancel(runId);
      run.status = 'cancelled';
      this.eventStore.append(runId, eventTypes.RUN_CANCELLED, { reason: 'queued_run_cancelled' });
      return publicRun(run);
    }
    if (run.status !== 'running') return publicRun(run);
    this.eventStore.append(runId, eventTypes.RUN_CANCELLING, {});
    if (run.child && typeof run.child.kill === 'function') run.child.kill('SIGTERM');
    run.status = 'cancelled';
    this.auditLog.record('run.cancel', { runId, deviceId: device.id });
    this.eventStore.append(runId, eventTypes.RUN_CANCELLED, { reason: 'user_cancelled' });
    this.releaseQueue(run);
    return publicRun(run);
  }

  followUp(runId, payload, device) {
    assertNoV1TerminalRequest(payload);
    const run = this.getRun(runId, device);
    const prompt = validateFollowUpPrompt(payload);
    this.auditLog.record('run.follow_up', { runId, deviceId: device.id, textLength: prompt.length });
    if (run.status === 'running' || run.status === 'queued') {
      run.pendingPrompts.push(prompt);
      this.eventStore.append(runId, eventTypes.RUN_BLOCKED, { reason: 'follow_up_queued', queuedInputs: run.pendingPrompts.length });
      return publicRun(run);
    }
    if (!['completed', 'failed', 'cancelled'].includes(run.status)) {
      const error = new Error('run is not ready for follow-up input');
      error.status = 409;
      error.code = 'RUN_NOT_READY';
      throw error;
    }
    run.prompt = prompt;
    run.resumeRequested = true;
    const workspace = this.workspaces.getAuthorized(run.workspaceId, device);
    this.startRunProcess(run, workspace);
    return publicRun(run);
  }

  respondApproval(approvalId, payload, device) {
    assertNoV1TerminalRequest(payload);
    if (!['allow', 'deny'].includes(payload.decision)) {
      const error = new Error('decision must be allow or deny');
      error.status = 400;
      throw error;
    }
    const run = Array.from(this.runs.values()).find((candidate) => candidate.deviceId === device.id && candidate.pendingApprovals?.has(approvalId));
    if (!run) throw notFound('approval not found');
    this.auditLog.record('approval.respond', { approvalId, decision: payload.decision, deviceId: device.id, runId: run.id });
    const approval = run.pendingApprovals.get(approvalId);
    run.pendingApprovals.delete(approvalId);
    if (approval && typeof approval.respond === 'function') approval.respond(payload.decision);
    this.eventStore.append(run.id, eventTypes.APPROVAL_RESPONDED, {
      approvalId,
      decision: payload.decision,
      toolName: approval?.toolName,
      input: approval?.input || {},
      toolUseId: approval?.toolUseId || null
    });
    return { approvalId, decision: payload.decision };
  }

  recordAdapterEvent(run, event) {
    if (event.type === eventTypes.APPROVAL_REQUIRED && event.approvalId && event.respond) {
      if (!run.pendingApprovals) run.pendingApprovals = new Map();
      run.pendingApprovals.set(event.approvalId, {
        respond: event.respond,
        toolName: event.toolName,
        input: event.input || {},
        toolUseId: event.toolUseId || null
      });
    }
    if (event.sessionId && !run.cliSessionId) {
      run.cliSessionId = event.sessionId;
      this.eventStore.append(run.id, eventTypes.RAW_OUTPUT, { text: '', sessionId: event.sessionId, reason: 'cli_session_captured' });
    }
    if ([eventTypes.RUN_COMPLETED, eventTypes.RUN_FAILED, eventTypes.RUN_CANCELLED].includes(event.type)) {
      run.status = event.type === eventTypes.RUN_COMPLETED ? 'completed' : event.type === eventTypes.RUN_CANCELLED ? 'cancelled' : 'failed';
    }
    const { type, respond, ...payload } = event;
    this.eventStore.append(run.id, type || eventTypes.RAW_OUTPUT, payload);
    if (event.type === eventTypes.RUN_COMPLETED && run.pendingPrompts.length > 0) {
      const nextPrompt = run.pendingPrompts.shift();
      run.prompt = nextPrompt;
      run.resumeRequested = true;
      const workspace = this.workspaces.get(run.workspaceId);
      this.startRunProcess(run, workspace);
      return;
    }
    if ([eventTypes.RUN_COMPLETED, eventTypes.RUN_FAILED, eventTypes.RUN_CANCELLED].includes(event.type)) this.releaseQueue(run);
  }

  releaseQueue(run) {
    const dequeued = this.runQueue.complete(run);
    if (!dequeued) return;
    const nextRun = this.runs.get(dequeued.runId);
    if (!nextRun) return;
    const workspace = this.workspaces.get(nextRun.workspaceId);
    this.eventStore.append(nextRun.id, eventTypes.RUN_DEQUEUED, { workspaceId: nextRun.workspaceId });
    this.startRunProcess(nextRun, workspace);
  }
}


function validateFollowUpPrompt(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  if (!payload.prompt || typeof payload.prompt !== 'string') throw badRequest('prompt is required');
  const prompt = payload.prompt.trim();
  if (!prompt) throw badRequest('prompt is required');
  return prompt;
}

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = 'BAD_REQUEST';
  return error;
}

function publicRun(run) {
  return {
    id: run.id,
    tool: run.tool,
    workspaceId: run.workspaceId,
    status: run.status,
    createdAt: run.createdAt,
    cliSessionId: run.cliSessionId || null,
    permissionMode: run.permissionMode || 'default'
  };
}

function notFound(message) {
  const error = new Error(message);
  error.status = 404;
  error.code = 'NOT_FOUND';
  return error;
}

module.exports = { RunManager };

