'use strict';

const { summarizeCodexAppServerCapabilityMatrix } = require('./capability-matrix');
const { buildCodexAppServerRouteCapabilities } = require('./capability-routes');
const {
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
