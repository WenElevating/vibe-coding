'use strict';

const path = require('node:path');
const crypto = require('node:crypto');

class WorkspaceRegistry {
  constructor() {
    this.workspaces = new Map();
  }

  add({ id, name, workspacePath }) {
    if (!workspacePath) throw new Error('workspace path is required');
    const resolved = path.resolve(workspacePath);
    id = id || `workspace_${crypto.createHash('sha1').update(resolved).digest('hex').slice(0, 12)}`;
    name = name || path.basename(resolved) || resolved;
    const workspace = { id, name, path: resolved };
    this.workspaces.set(id, workspace);
    return workspace;
  }

  listForDevice(device) {
    return Array.from(this.workspaces.values()).filter((workspace) => device.allowedWorkspaceIds.has(workspace.id));
  }

  getAuthorized(workspaceId, device) {
    const workspace = this.workspaces.get(workspaceId);
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
