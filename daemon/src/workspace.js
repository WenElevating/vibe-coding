'use strict';

const path = require('node:path');
const crypto = require('node:crypto');

class WorkspaceRegistry {
  constructor({ store } = {}) {
    this.store = store || null;
    this.workspaces = new Map();
  }

  add({ id, name, workspacePath }, device = null) {
    if (!workspacePath) throw new Error('workspace path is required');
    if (this.store && device) {
      const workspace = this.store.saveWorkspaceForDevice({
        deviceId: device.id,
        id,
        name,
        workspacePath
      });
      this.authorizeDeviceForWorkspace(device, workspace.id);
      return workspace;
    }
    const resolved = path.resolve(workspacePath);
    id = id || `workspace_${crypto.createHash('sha1').update(resolved).digest('hex').slice(0, 12)}`;
    name = name || path.basename(resolved) || resolved;
    const workspace = { id, name, path: resolved };
    this.workspaces.set(id, workspace);
    return workspace;
  }

  seedDefault({ id, name, workspacePath }, device) {
    if (!this.store) {
      const workspace = this.add({ id, name, workspacePath });
      if (device) this.authorizeDeviceForWorkspace(device, workspace.id);
      return workspace;
    }
    if (this.store.hasAnyWorkspaces()) {
      const existing = this.store.listWorkspacesForDevice(device.id);
      if (existing.length > 0) return existing[0];
      return null;
    }
    return this.add({ id, name, workspacePath }, device);
  }

  authorizeDeviceForWorkspace(device, workspaceId) {
    if (!device || !workspaceId) return;
    if (this.store) this.store.authorizeWorkspaceForDevice(device.id, workspaceId);
    device.allowedWorkspaceIds.add(workspaceId);
  }

  authorizeExistingWorkspacesForDevice(device) {
    if (!device) return;
    for (const workspace of this.workspaces.values()) {
      this.authorizeDeviceForWorkspace(device, workspace.id);
    }
    if (this.store) {
      const existing = this.store.listWorkspaces();
      for (const workspace of existing) this.authorizeDeviceForWorkspace(device, workspace.id);
    }
  }

  listForDevice(device) {
    if (this.store) return this.store.listWorkspacesForDevice(device.id);
    return Array.from(this.workspaces.values()).filter((workspace) => device.allowedWorkspaceIds.has(workspace.id));
  }

  get(workspaceId) {
    return this.store ? this.store.getWorkspace(workspaceId) : this.workspaces.get(workspaceId);
  }

  getAuthorized(workspaceId, device) {
    const workspace = this.store
      ? this.store.getWorkspaceForDevice(workspaceId, device.id)
      : this.workspaces.get(workspaceId);
    if (!workspace || !device.allowedWorkspaceIds.has(workspaceId)) {
      const error = new Error('workspace not found or not authorized');
      error.status = 404;
      error.code = 'WORKSPACE_NOT_FOUND';
      throw error;
    }
    return workspace;
  }
}

module.exports = { WorkspaceRegistry };
