'use strict';

const path = require('node:path');
const { recordCodexAppServerAudit } = require('./audit');
const { summarizeCodexAppServerCapabilityMatrix } = require('./capability-matrix');
const { buildCodexAppServerRouteCapabilities } = require('./capability-routes');
const {
  normalizeAccountRateLimitsResponse,
  normalizeAccountResponse,
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

  if (method === 'GET' && url.pathname === '/api/codex-app-server/account') {
    const response = await requireService(context).withDiscoveryClient((client) => client.readAccount());
    json(200, normalizeAccountResponse(response));
    return true;
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/account/rate-limits') {
    const response = await requireService(context).withDiscoveryClient((client) => client.readAccountRateLimits());
    json(200, normalizeAccountRateLimitsResponse(response));
    return true;
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/account/login/start') {
    const body = await readJson();
    const request = normalizeAccountLoginStartBody(body);
    return mutationRoute(context, json, {
      method: 'account/login/start',
      risk: 'account',
      action: (client) => client.startAccountLogin(request)
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/account/login/cancel') {
    const body = await readJson();
    const loginId = parseRequiredBodyString(body?.loginId, 'loginId');
    return mutationRoute(context, json, {
      method: 'account/login/cancel',
      risk: 'account',
      action: (client) => client.cancelAccountLogin({ loginId })
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/account/logout') {
    return mutationRoute(context, json, {
      method: 'account/logout',
      risk: 'account',
      action: (client) => client.logoutAccount()
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/account/add-credits-email') {
    return mutationRoute(context, json, {
      method: 'account/sendAddCreditsNudgeEmail',
      risk: 'account',
      action: (client) => client.sendAddCreditsNudgeEmail()
    });
  }

  const mcpOauthLogin = url.pathname.match(/^\/api\/codex-app-server\/mcp\/servers\/([^/]+)\/oauth\/login$/);
  if (method === 'POST' && mcpOauthLogin) {
    const body = await readJson();
    const request = normalizeMcpOauthLoginBody(decodePathParam(mcpOauthLogin[1]), body);
    return mutationRoute(context, json, {
      method: 'mcpServer/oauth/login',
      risk: 'account',
      action: (client) => client.startMcpServerOauthLogin(request)
    });
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

  const workspaceFsMetadata = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/metadata$/);
  if (method === 'GET' && workspaceFsMetadata) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsMetadata[1]), context.device);
    const filePath = resolveWorkspaceRelativePath(workspace, parseRequiredQueryString(url.searchParams.get('path'), 'path'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.getFileMetadata({
      path: filePath
    }));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceFsDirectory = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/directory$/);
  if (method === 'GET' && workspaceFsDirectory) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsDirectory[1]), context.device);
    const directoryPath = resolveWorkspaceRelativePath(workspace, parseRequiredQueryString(url.searchParams.get('path'), 'path'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.readDirectory({
      path: directoryPath
    }));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceFsReadFile = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/read-file$/);
  if (method === 'GET' && workspaceFsReadFile) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsReadFile[1]), context.device);
    const filePath = resolveWorkspaceRelativePath(workspace, parseRequiredQueryString(url.searchParams.get('path'), 'path'));
    const encoding = parseOptionalString(url.searchParams.get('encoding'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.readFile(compactObject({
      path: filePath,
      encoding
    })));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceFsWatch = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/watch$/);
  if (method === 'POST' && workspaceFsWatch) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsWatch[1]), context.device);
    const body = await readJson();
    const watchPath = resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(body?.path, 'path'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.watchFileSystem({
      path: watchPath
    }));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceFsUnwatch = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/unwatch$/);
  if (method === 'POST' && workspaceFsUnwatch) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsUnwatch[1]), context.device);
    const body = await readJson();
    const watchId = parseRequiredBodyString(body?.watchId, 'watchId');
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.unwatchFileSystem({
      watchId
    }));
    json(200, normalizeDiscoveryResponse(response, {}));
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

  const workspaceThreadFork = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/fork$/);
  if (method === 'POST' && workspaceThreadFork) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadFork[1]), context.device);
    const threadId = decodePathParam(workspaceThreadFork[2]);
    const body = await readJson();
    const fromTurnId = parseOptionalBodyString(body?.fromTurnId, 'fromTurnId');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/fork',
      event: 'thread_fork',
      action: (client) => client.forkThread(compactObject({
        threadId,
        workspacePath: workspaceRoot(workspace),
        fromTurnId
      }))
    });
  }

  const workspaceThreadArchive = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/archive$/);
  if (method === 'POST' && workspaceThreadArchive) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadArchive[1]), context.device);
    const threadId = decodePathParam(workspaceThreadArchive[2]);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/archive',
      event: 'thread_archive',
      action: (client) => client.archiveThread({ threadId })
    });
  }

  const workspaceThreadUnarchive = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/unarchive$/);
  if (method === 'POST' && workspaceThreadUnarchive) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadUnarchive[1]), context.device);
    const threadId = decodePathParam(workspaceThreadUnarchive[2]);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/unarchive',
      event: 'thread_unarchive',
      action: (client) => client.unarchiveThread({ threadId })
    });
  }

  const workspaceThreadRollback = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/rollback$/);
  if (method === 'POST' && workspaceThreadRollback) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadRollback[1]), context.device);
    const threadId = decodePathParam(workspaceThreadRollback[2]);
    const body = await readJson();
    const turnId = parseOptionalBodyString(body?.turnId, 'turnId');
    const itemId = parseOptionalBodyString(body?.itemId, 'itemId');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/rollback',
      event: 'thread_rollback',
      action: (client) => client.rollbackThread(compactObject({
        threadId,
        turnId,
        itemId
      }))
    });
  }

  const workspaceThreadMetadata = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/metadata$/);
  if (method === 'PATCH' && workspaceThreadMetadata) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadMetadata[1]), context.device);
    const threadId = decodePathParam(workspaceThreadMetadata[2]);
    const body = await readJson();
    const metadata = parseRequiredObject(body?.metadata, 'metadata');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/metadata/update',
      event: 'thread_metadata_update',
      action: (client) => client.updateThreadMetadata({
        threadId,
        metadata
      })
    });
  }

  const workspaceThreadName = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/name$/);
  if (method === 'PATCH' && workspaceThreadName) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadName[1]), context.device);
    const threadId = decodePathParam(workspaceThreadName[2]);
    const body = await readJson();
    const name = parseRequiredBodyString(body?.name, 'name');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/name/set',
      event: 'thread_name_set',
      action: (client) => client.setThreadName({
        threadId,
        name
      })
    });
  }

  const workspaceThreadSettings = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/settings$/);
  if (method === 'PATCH' && workspaceThreadSettings) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadSettings[1]), context.device);
    const threadId = decodePathParam(workspaceThreadSettings[2]);
    const body = await readJson();
    const settings = parseRequiredObject(body?.settings, 'settings');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/settings/update',
      event: 'thread_settings_update',
      action: (client) => client.updateThreadSettings({
        threadId,
        settings
      })
    });
  }

  const workspaceThreadMemoryMode = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/memory-mode$/);
  if (method === 'PATCH' && workspaceThreadMemoryMode) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadMemoryMode[1]), context.device);
    const threadId = decodePathParam(workspaceThreadMemoryMode[2]);
    const body = await readJson();
    const memoryMode = parseRequiredBodyString(body?.memoryMode, 'memoryMode');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/memoryMode/set',
      event: 'thread_memory_mode_set',
      action: (client) => client.setThreadMemoryMode({
        threadId,
        memoryMode
      })
    });
  }

  const workspaceThreadGoalPut = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/goal$/);
  if (method === 'PUT' && workspaceThreadGoalPut) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadGoalPut[1]), context.device);
    const threadId = decodePathParam(workspaceThreadGoalPut[2]);
    const body = await readJson();
    const goal = parseRequiredGoal(body);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/goal/set',
      event: 'thread_goal_set',
      action: (client) => client.setThreadGoal({
        threadId,
        goal
      })
    });
  }

  const workspaceThreadGoalDelete = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/goal$/);
  if (method === 'DELETE' && workspaceThreadGoalDelete) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadGoalDelete[1]), context.device);
    const threadId = decodePathParam(workspaceThreadGoalDelete[2]);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/goal/clear',
      event: 'thread_goal_clear',
      action: (client) => client.clearThreadGoal({ threadId })
    });
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

async function mutationRoute(context, json, { method, risk, action }) {
  const correlationId = createCorrelationId();
  try {
    const response = await requireService(context).withMutationClient({ method, risk }, (client) => action(client));
    recordAccountAudit(context, { method, risk, decision: 'allow', result: 'success', correlationId });
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  } catch (error) {
    const sanitized = sanitizeAccountMutationError(error);
    recordAccountAudit(context, {
      method,
      risk,
      decision: 'allow',
      result: 'error',
      correlationId,
      error: sanitized.auditError,
      downstreamStatus: sanitized.downstreamStatus,
      downstreamCode: sanitized.downstreamCode
    });
    throw controlledAccountMutationError();
  }
}

async function threadMutationRoute(context, json, { workspace, threadId, method, event, action }) {
  const correlationId = createCorrelationId();
  const risk = 'write';
  const metadata = {
    method,
    risk,
    workspaceId: workspace.id || workspace.workspaceId || null,
    workspacePath: workspaceRoot(workspace),
    threadId
  };
  try {
    const response = await requireService(context).withMutationClient(metadata, (client) => action(client));
    recordCodexAppServerAudit(context.auditLog, event, {
      method,
      workspaceId: metadata.workspaceId,
      threadId,
      deviceId: context.device?.id || null,
      risk,
      decision: 'allow',
      ok: true,
      correlationId
    });
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  } catch (error) {
    const sanitized = sanitizeThreadMutationError(error);
    recordCodexAppServerAudit(context.auditLog, event, {
      method,
      workspaceId: metadata.workspaceId,
      threadId,
      deviceId: context.device?.id || null,
      risk,
      decision: 'allow',
      result: 'failure',
      errorCode: sanitized.downstreamCode || sanitized.errorCode,
      correlationId
    });
    throw controlledThreadMutationError();
  }
}

function normalizeAccountLoginStartBody(body) {
  const type = parseRequiredBodyString(body?.type, 'type');
  if (type === 'apiKey') {
    return {
      type,
      apiKey: parseRequiredBodyString(body?.apiKey, 'apiKey')
    };
  }
  if (type === 'chatgpt') {
    return compactObject({
      type,
      codexStreamlinedLogin: parseOptionalBoolean(body?.codexStreamlinedLogin, 'codexStreamlinedLogin')
    });
  }
  if (type === 'chatgptDeviceCode') {
    return { type };
  }
  if (type === 'chatgptAuthTokens') {
    return compactObject({
      type,
      accessToken: parseRequiredBodyString(body?.accessToken, 'accessToken'),
      chatgptAccountId: parseRequiredBodyString(body?.chatgptAccountId, 'chatgptAccountId'),
      chatgptPlanType: parseOptionalNullableString(body?.chatgptPlanType, 'chatgptPlanType')
    });
  }
  throw badRequest('type must be apiKey, chatgpt, chatgptDeviceCode, or chatgptAuthTokens');
}

function normalizeMcpOauthLoginBody(serverId, body) {
  const request = {
    name: parseRequiredBodyString(serverId, 'serverId')
  };
  if (body?.scopes !== undefined && body?.scopes !== null) {
    if (!Array.isArray(body.scopes)) throw badRequest('scopes must be an array of strings');
    request.scopes = body.scopes.map((scope) => parseRequiredStringValue(scope, 'scopes'));
  }
  if (body?.timeoutSecs !== undefined && body?.timeoutSecs !== null) {
    if (!Number.isInteger(body.timeoutSecs) || body.timeoutSecs < 1) {
      throw badRequest('timeoutSecs must be a positive integer');
    }
    request.timeoutSecs = body.timeoutSecs;
  }
  return request;
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

function parseOptionalNullableString(value, name) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  return parseRequiredBodyString(value, name);
}

function parseOptionalBodyString(value, name) {
  if (value === undefined || value === null) return undefined;
  return parseRequiredBodyString(value, name);
}

function parseOptionalBoolean(value, name) {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'boolean') throw badRequest(`${name} must be a boolean`);
  return value;
}

function parseRequiredQueryString(value, name) {
  if (value === undefined || value === null || String(value).trim() === '') {
    throw badRequest(`${name} query parameter is required`);
  }
  return value;
}

function parseRequiredBodyString(value, name) {
  if (value === undefined || value === null || String(value).trim() === '') {
    throw badRequest(`${name} is required`);
  }
  return String(value).trim();
}

function parseRequiredStringValue(value, name) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw badRequest(`${name} must be a nonblank string`);
  }
  return value.trim();
}

function parseRequiredObject(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw badRequest(`${name} must be an object`);
  }
  return value;
}

function parseRequiredGoal(body) {
  if (body && Object.prototype.hasOwnProperty.call(body, 'goal')) {
    const goal = body.goal;
    if (goal === null) return null;
    if (typeof goal === 'string') return parseRequiredBodyString(goal, 'goal');
    if (goal && typeof goal === 'object' && !Array.isArray(goal)) return goal;
  }
  throw badRequest('goal is required');
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

function resolveWorkspaceRelativePath(workspace, relativePath) {
  const root = workspaceRoot(workspace);
  if (!root) throw badRequest('workspace path is required');
  if (hasAbsolutePathSyntax(relativePath)) {
    throw Object.assign(new Error('path outside authorized workspace'), {
      status: 403,
      code: 'FORBIDDEN'
    });
  }
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(resolvedRoot, relativePath || '.');
  const comparableRoot = normalizePathForGuard(resolvedRoot);
  const comparableResolved = normalizePathForGuard(resolved);
  if (comparableResolved !== comparableRoot && !comparableResolved.startsWith(`${comparableRoot}${path.sep}`)) {
    throw Object.assign(new Error('path outside authorized workspace'), {
      status: 403,
      code: 'FORBIDDEN'
    });
  }
  return resolved;
}

function hasAbsolutePathSyntax(value) {
  const candidate = String(value || '');
  return path.isAbsolute(candidate) ||
    path.win32.isAbsolute(candidate) ||
    path.posix.isAbsolute(candidate) ||
    /^[A-Za-z]:/.test(candidate);
}

function normalizePathForGuard(value) {
  let normalized = path.normalize(value);
  while (normalized.length > path.parse(normalized).root.length && normalized.endsWith(path.sep)) {
    normalized = normalized.slice(0, -1);
  }
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
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

function controlledAccountMutationError() {
  return Object.assign(new Error('Codex app-server account mutation failed.'), {
    status: 502,
    code: 'CODEX_APP_SERVER_ACCOUNT_MUTATION_FAILED'
  });
}

function controlledThreadMutationError() {
  return Object.assign(new Error('Codex app-server thread mutation failed.'), {
    status: 502,
    code: 'CODEX_APP_SERVER_THREAD_MUTATION_FAILED'
  });
}

function sanitizeAccountMutationError(error) {
  return {
    auditError: redactAccountSensitiveText(error?.message || 'Codex app-server account mutation failed.'),
    downstreamStatus: safeDownstreamStatus(error?.status),
    downstreamCode: safeDownstreamCode(error?.code)
  };
}

function sanitizeThreadMutationError(error) {
  return {
    errorCode: 'CODEX_APP_SERVER_THREAD_MUTATION_FAILED',
    downstreamStatus: safeDownstreamStatus(error?.status),
    downstreamCode: safeDownstreamCode(error?.code)
  };
}

function redactAccountSensitiveText(text) {
  if (!text) return '[REDACTED]';
  let value = String(text);
  value = value.replace(/[A-Z]:\\[^\s"'`]+/gi, '[REDACTED]');
  value = value.replace(/\/(?:[^\s"'`/]+\/)+[^\s"'`/]+/g, '[REDACTED]');
  value = value.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[REDACTED]');
  value = value.replace(/\b(?:sk|sess|access|refresh|bearer)[-_A-Za-z0-9.]{3,}\b/gi, '[REDACTED]');
  if (/[\\/.](?:codex|config|json)|token|oauth|auth/i.test(value)) return '[REDACTED]';
  return value.trim() || '[REDACTED]';
}

function safeDownstreamStatus(status) {
  return Number.isInteger(status) && status >= 400 && status < 600 ? status : undefined;
}

function safeDownstreamCode(code) {
  if (typeof code !== 'string' || !/^[A-Z0-9_:-]{1,80}$/.test(code)) return undefined;
  return code;
}

function recordAccountAudit(context, payload) {
  if (!context.auditLog || typeof context.auditLog.record !== 'function') return;
  context.auditLog.record('codex_app_server.account_mutation', {
    ...payload,
    deviceId: context.device?.id || null
  });
}

function createCorrelationId() {
  return `codex-app-server-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
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
  resolveWorkspaceRelativePath,
  tryHandleCodexAppServerRoute
};
