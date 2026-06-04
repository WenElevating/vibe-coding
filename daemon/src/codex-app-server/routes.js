'use strict';

const { summarizeCodexAppServerCapabilityMatrix } = require('./capability-matrix');
const { buildCodexAppServerRouteCapabilities } = require('./capability-routes');
const {
  normalizeDiscoveryResponse,
  normalizeGoalResponse,
  normalizeItemListResponse,
  normalizeThreadListResponse,
  normalizeThreadResponse,
  normalizeTurnListResponse
} = require('./dtos');

async function tryHandleCodexAppServerRoute({ method, url, json, readJson, context }) {
  void readJson;
  if (url.pathname !== '/api/codex-app-server' && !url.pathname.startsWith('/api/codex-app-server/')) return false;

  if (method === 'GET' && url.pathname === '/api/codex-app-server/capabilities') {
    json(200, {
      capabilityMatrix: summarizeCodexAppServerCapabilityMatrix(),
      routes: buildCodexAppServerRouteCapabilities()
    });
    return true;
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/config') {
    return discoveryRoute(context, json, (client) => client.readConfig(), {});
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/config/requirements') {
    return discoveryRoute(context, json, (client) => client.readConfigRequirements(), {});
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/mcp/servers') {
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listMcpServerStatus(compactObject({ cursor })),
      { collectionKey: 'servers', candidateKeys: ['servers', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/mcp/resources') {
    const serverId = parseRequiredQueryString(url.searchParams.get('serverId'), 'serverId');
    const uri = parseRequiredQueryString(url.searchParams.get('uri'), 'uri');
    return discoveryRoute(
      context,
      json,
      (client) => client.readMcpServerResource({ serverId, uri }),
      {}
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/skills') {
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listSkills(compactObject({ cursor })),
      { collectionKey: 'skills', candidateKeys: ['skills', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/plugins') {
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listPlugins(compactObject({ cursor })),
      { collectionKey: 'plugins', candidateKeys: ['plugins', 'data', 'items'] }
    );
  }

  const pluginRead = url.pathname.match(/^\/api\/codex-app-server\/plugins\/([^/]+)$/);
  if (method === 'GET' && pluginRead) {
    const pluginId = decodePathParam(pluginRead[1]);
    return discoveryRoute(
      context,
      json,
      (client) => client.readPlugin({ pluginId }),
      { objectKey: 'plugin' }
    );
  }

  const pluginSkillRead = url.pathname.match(/^\/api\/codex-app-server\/plugins\/([^/]+)\/skills\/([^/]+)$/);
  if (method === 'GET' && pluginSkillRead) {
    const pluginId = decodePathParam(pluginSkillRead[1]);
    const skillId = decodePathParam(pluginSkillRead[2]);
    return discoveryRoute(
      context,
      json,
      (client) => client.readPluginSkill({ pluginId, skillId }),
      { objectKey: 'skill' }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/plugin-shares') {
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listPluginShares(compactObject({ cursor })),
      { collectionKey: 'shares', candidateKeys: ['shares', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/apps') {
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listApps(compactObject({ cursor })),
      { collectionKey: 'apps', candidateKeys: ['apps', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/hooks') {
    return discoveryRoute(
      context,
      json,
      (client) => client.listHooks(),
      { collectionKey: 'hooks', candidateKeys: ['hooks', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/collaboration-modes') {
    return discoveryRoute(
      context,
      json,
      (client) => client.listCollaborationModes(),
      { collectionKey: 'modes', candidateKeys: ['modes', 'collaborationModes', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/experimental-features') {
    return discoveryRoute(
      context,
      json,
      (client) => client.listExperimentalFeatures(),
      { collectionKey: 'features', candidateKeys: ['features', 'experimentalFeatures', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/external-agent-config') {
    return discoveryRoute(context, json, (client) => client.detectExternalAgentConfig(), {});
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/permission-profiles') {
    return discoveryRoute(
      context,
      json,
      (client) => client.listPermissionProfiles(),
      { collectionKey: 'profiles', candidateKeys: ['profiles', 'permissionProfiles', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/model-provider-capabilities') {
    return discoveryRoute(context, json, (client) => client.readModelProviderCapabilities(), {});
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/windows-sandbox/readiness') {
    return discoveryRoute(context, json, (client) => client.readWindowsSandboxReadiness(), {});
  }

  const workspaceThreads = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads$/);
  if (method === 'GET' && workspaceThreads) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreads[1]), context.device);
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const archived = parseBoolean(url.searchParams.get('archived'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.listThreads(compactObject({
      workspacePath: workspaceRoot(workspace),
      limit,
      cursor,
      archived
    })));
    json(200, normalizeThreadListResponse(response));
    return true;
  }

  const workspaceSearch = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/search$/);
  if (method === 'GET' && workspaceSearch) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceSearch[1]), context.device);
    const query = parseOptionalString(url.searchParams.get('query'));
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.searchThreads(compactObject({
      query,
      workspacePath: workspaceRoot(workspace),
      limit,
      cursor
    })));
    json(200, normalizeThreadListResponse(response));
    return true;
  }

  const workspaceThreadTurns = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/turns$/);
  if (method === 'GET' && workspaceThreadTurns) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadTurns[1]), context.device);
    const threadId = decodePathParam(workspaceThreadTurns[2]);
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.listThreadTurns(compactObject({
      threadId,
      limit,
      cursor
    })));
    json(200, normalizeTurnListResponse(response));
    return true;
  }

  const workspaceTurnItems = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/turns\/([^/]+)\/items$/);
  if (method === 'GET' && workspaceTurnItems) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceTurnItems[1]), context.device);
    const threadId = decodePathParam(workspaceTurnItems[2]);
    const turnId = decodePathParam(workspaceTurnItems[3]);
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.listThreadTurnItems(compactObject({
      threadId,
      turnId,
      limit,
      cursor
    })));
    json(200, normalizeItemListResponse(response));
    return true;
  }

  const workspaceThreadGoal = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/goal$/);
  if (method === 'GET' && workspaceThreadGoal) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadGoal[1]), context.device);
    const threadId = decodePathParam(workspaceThreadGoal[2]);
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.getThreadGoal({
      threadId
    }));
    json(200, normalizeGoalResponse(response));
    return true;
  }

  const workspaceThreadRead = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)$/);
  if (method === 'GET' && workspaceThreadRead) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadRead[1]), context.device);
    const threadId = decodePathParam(workspaceThreadRead[2]);
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.readThread({
      threadId
    }));
    json(200, normalizeThreadResponse(response));
    return true;
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/threads/loaded') {
    const response = await requireService(context).withDiscoveryClient((client) => client.listLoadedThreads());
    json(200, normalizeThreadListResponse(response));
    return true;
  }

  throw Object.assign(new Error('Codex app-server route not found'), {
    status: 404,
    code: 'CODEX_APP_SERVER_ROUTE_NOT_FOUND'
  });
}

async function discoveryRoute(context, json, action, normalizeOptions) {
  const response = await requireService(context).withDiscoveryClient((client) => action(client));
  json(200, normalizeDiscoveryResponse(response, normalizeOptions));
  return true;
}

function parseLimit(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  if (!/^\d+$/.test(String(value))) throw badRequest('limit must be a positive integer');
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) throw badRequest('limit must be a positive integer');
  return Math.max(1, Math.min(parsed, 200));
}

function parseBoolean(value) {
  if (value === undefined || value === null || value === '') return undefined;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw badRequest('boolean query value must be true or false');
}

function parseOptionalString(value) {
  if (value === undefined || value === null || value === '') return undefined;
  return value;
}

function parseRequiredQueryString(value, name) {
  if (value === undefined || value === null || String(value).trim() === '') {
    throw badRequest(`${name} query parameter is required`);
  }
  return value;
}

function decodePathParam(value) {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    if (error instanceof URIError) throw badRequest('path parameter is not valid percent-encoding');
    throw error;
  }
}

function workspaceRoot(workspace) {
  return workspace.path || workspace.workspacePath;
}

function requireService(context) {
  if (!context.codexAppServerService) {
    throw Object.assign(new Error('Codex app-server service is unavailable'), {
      status: 503,
      code: 'CODEX_APP_SERVER_UNAVAILABLE'
    });
  }
  return context.codexAppServerService;
}

function badRequest(message) {
  return Object.assign(new Error(message), {
    status: 400,
    code: 'BAD_REQUEST'
  });
}

function compactObject(value) {
  const result = {};
  for (const [key, current] of Object.entries(value || {})) {
    if (current !== undefined && current !== null) result[key] = current;
  }
  return result;
}

module.exports = {
  decodePathParam,
  parseBoolean,
  parseLimit,
  tryHandleCodexAppServerRoute
};
