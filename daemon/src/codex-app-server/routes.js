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
    const workspace = context.workspaces.getAuthorized(decodeURIComponent(workspaceThreads[1]), context.device);
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
    const workspace = context.workspaces.getAuthorized(decodeURIComponent(workspaceSearch[1]), context.device);
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

  if (method === 'GET' && url.pathname === '/api/codex-app-server/threads/loaded') {
    const response = await requireService(context).withDiscoveryClient((client) => client.listLoadedThreads());
    json(200, normalizeThreadListResponse(response));
    return true;
  }

  const threadTurns = url.pathname.match(/^\/api\/codex-app-server\/threads\/([^/]+)\/turns$/);
  if (method === 'GET' && threadTurns) {
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const response = await requireService(context).withDiscoveryClient((client) => client.listThreadTurns(compactObject({
      threadId: decodeURIComponent(threadTurns[1]),
      limit,
      cursor
    })));
    json(200, normalizeTurnListResponse(response));
    return true;
  }

  const turnItems = url.pathname.match(/^\/api\/codex-app-server\/threads\/([^/]+)\/turns\/([^/]+)\/items$/);
  if (method === 'GET' && turnItems) {
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const response = await requireService(context).withDiscoveryClient((client) => client.listThreadTurnItems(compactObject({
      threadId: decodeURIComponent(turnItems[1]),
      turnId: decodeURIComponent(turnItems[2]),
      limit,
      cursor
    })));
    json(200, normalizeItemListResponse(response));
    return true;
  }

  const threadGoal = url.pathname.match(/^\/api\/codex-app-server\/threads\/([^/]+)\/goal$/);
  if (method === 'GET' && threadGoal) {
    const response = await requireService(context).withDiscoveryClient((client) => client.getThreadGoal({
      threadId: decodeURIComponent(threadGoal[1])
    }));
    json(200, normalizeGoalResponse(response));
    return true;
  }

  const threadRead = url.pathname.match(/^\/api\/codex-app-server\/threads\/([^/]+)$/);
  if (method === 'GET' && threadRead) {
    const response = await requireService(context).withDiscoveryClient((client) => client.readThread({
      threadId: decodeURIComponent(threadRead[1])
    }));
    json(200, normalizeThreadResponse(response));
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
  parseBoolean,
  parseLimit,
  tryHandleCodexAppServerRoute
};
