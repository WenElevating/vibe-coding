'use strict';

class RunQueue {
  constructor() {
    this.activeWorkspaceRuns = new Map();
    this.queue = [];
  }

  submit(run) {
    if (this.activeWorkspaceRuns.has(run.workspaceId)) {
      run.status = 'queued';
      const item = {
        id: `queue_${run.id}`,
        runId: run.id,
        workspaceId: run.workspaceId,
        position: this.queue.filter((queued) => queued.workspaceId === run.workspaceId).length + 1,
        status: 'queued',
        reason: 'workspace_write_run_active',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };
      this.queue.push(item);
      return { state: 'queued', item };
    }
    this.activeWorkspaceRuns.set(run.workspaceId, run.id);
    return { state: 'ready' };
  }

  complete(run) {
    if (this.activeWorkspaceRuns.get(run.workspaceId) === run.id) this.activeWorkspaceRuns.delete(run.workspaceId);
    const index = this.queue.findIndex((item) => item.workspaceId === run.workspaceId && item.status === 'queued');
    if (index === -1) return null;
    const [item] = this.queue.splice(index, 1);
    item.status = 'dequeued';
    item.updatedAt = new Date().toISOString();
    for (const queued of this.queue.filter((candidate) => candidate.workspaceId === run.workspaceId)) queued.position -= 1;
    this.activeWorkspaceRuns.set(item.workspaceId, item.runId);
    return item;
  }

  cancel(runId) {
    const index = this.queue.findIndex((item) => item.runId === runId);
    if (index === -1) return null;
    const [item] = this.queue.splice(index, 1);
    item.status = 'cancelled';
    item.updatedAt = new Date().toISOString();
    for (const queued of this.queue.filter((candidate) => candidate.workspaceId === item.workspaceId && candidate.position > item.position)) {
      queued.position -= 1;
      queued.updatedAt = new Date().toISOString();
    }
    return item;
  }

  list() {
    return [...this.queue];
  }
}

module.exports = { RunQueue };
