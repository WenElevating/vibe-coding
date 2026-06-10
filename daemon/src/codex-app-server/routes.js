'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { recordCodexAppServerAudit } = require('./audit');
const { summarizeCodexAppServerCapabilityMatrix } = require('./capability-matrix');
const { buildCodexAppServerRouteCapabilities } = require('./capability-routes');
const { requireHighRiskApproval } = require('./high-risk-approval');
const {
  normalizeAccountRateLimitsResponse,
  normalizeAccountResponse,
  normalizeConfigResponse,
  normalizeDiscoveryResponse,
  normalizeGoalResponse,
  normalizeItemListResponse,
  normalizeThreadListResponse,
  normalizeThreadResponse,
  normalizeTurnListResponse
} = require('./dtos');

const SUPPORTED_ROUTE_METHODS = new Set([
  'account/login/cancel',
  'account/login/start',
  'account/logout',
  'account/rateLimits/read',
  'account/read',
  'account/sendAddCreditsNudgeEmail',
  'app/list',
  'attestation/generate',
  'collaborationMode/list',
  'command/exec',
  'config/batchWrite',
  'config/mcpServer/reload',
  'config/read',
  'config/value/write',
  'configRequirements/read',
  'environment/add',
  'experimentalFeature/list',
  'externalAgentConfig/detect',
  'fs/copy',
  'fs/createDirectory',
  'fs/getMetadata',
  'fs/readDirectory',
  'fs/readFile',
  'fs/remove',
  'fs/unwatch',
  'fs/watch',
  'fs/writeFile',
  'fuzzyFileSearch',
  'fuzzyFileSearch/sessionStart',
  'fuzzyFileSearch/sessionStop',
  'fuzzyFileSearch/sessionUpdate',
  'hooks/list',
  'marketplace/add',
  'marketplace/remove',
  'marketplace/upgrade',
  'mcpServer/oauth/login',
  'mcpServer/resource/read',
  'mcpServerStatus/list',
  'modelProvider/capabilities/read',
  'permissionProfile/list',
  'plugin/install',
  'plugin/list',
  'plugin/read',
  'plugin/share/list',
  'plugin/skill/read',
  'plugin/uninstall',
  'process/kill',
  'process/spawn',
  'remoteControl/client/list',
  'remoteControl/client/revoke',
  'remoteControl/disable',
  'remoteControl/enable',
  'remoteControl/pairing/start',
  'remoteControl/status/read',
  'review/start',
  'skills/config/write',
  'skills/extraRoots/set',
  'skills/list',
  'thread/archive',
  'thread/fork',
  'thread/goal/clear',
  'thread/goal/get',
  'thread/goal/set',
  'thread/list',
  'thread/loaded/list',
  'thread/memoryMode/set',
  'thread/metadata/update',
  'thread/name/set',
  'thread/read',
  'thread/realtime/appendAudio',
  'thread/realtime/appendText',
  'thread/realtime/listVoices',
  'thread/realtime/start',
  'thread/realtime/stop',
  'thread/rollback',
  'thread/search',
  'thread/settings/update',
  'thread/turns/items/list',
  'thread/turns/list',
  'thread/unarchive',
  'windowsSandbox/readiness'
]);

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
    const response = await requireService(context).withDiscoveryClient((client) => client.readConfig());
    json(200, normalizeConfigResponse(response));
    return true;
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
    const server = parseRequiredQueryString(url.searchParams.get('server') ?? url.searchParams.get('serverId'), 'server');
    const uri = parseRequiredQueryString(url.searchParams.get('uri'), 'uri');
    return discoveryRoute(
      context,
      json,
      (client) => client.readMcpServerResource({ server, uri }),
      {}
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/skills') {
    parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listSkills(),
      { collectionKey: 'skills', candidateKeys: ['skills', 'data', 'items'] }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/plugins') {
    parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listPlugins(),
      { collectionKey: 'plugins', candidateKeys: ['plugins', 'data', 'items'] }
    );
  }

  const pluginRead = url.pathname.match(/^\/api\/codex-app-server\/plugins\/([^/]+)$/);
  if (method === 'GET' && pluginRead) {
    const pluginName = parseRequiredPathString(decodePathParam(pluginRead[1]), 'pluginName');
    return discoveryRoute(
      context,
      json,
      (client) => client.readPlugin({ pluginName }),
      { objectKey: 'plugin' }
    );
  }

  const pluginSkillRead = url.pathname.match(/^\/api\/codex-app-server\/plugins\/([^/]+)\/skills\/([^/]+)$/);
  if (method === 'GET' && pluginSkillRead) {
    const remotePluginId = parseRequiredPathString(decodePathParam(pluginSkillRead[1]), 'remotePluginId');
    const skillName = parseRequiredPathString(decodePathParam(pluginSkillRead[2]), 'skillName');
    const remoteMarketplaceName = parseRequiredQueryString(
      url.searchParams.get('remoteMarketplaceName') ?? url.searchParams.get('marketplaceName'),
      'remoteMarketplaceName'
    );
    return discoveryRoute(
      context,
      json,
      (client) => client.readPluginSkill({ remoteMarketplaceName, remotePluginId, skillName }),
      { objectKey: 'skill' }
    );
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/plugin-shares') {
    parseOptionalString(url.searchParams.get('cursor'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listPluginShares(),
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
    parseOptionalString(url.searchParams.get('encoding'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.readFile(compactObject({
      path: filePath
    })));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceFsWatch = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/watch$/);
  if (method === 'POST' && workspaceFsWatch) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsWatch[1]), context.device);
    const body = await readJson();
    const watchPath = resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(body?.path, 'path'));
    const watchId = `watch_${crypto.randomUUID()}`;
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.watchFileSystem({
      path: watchPath,
      watchId
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

  const workspaceFsWriteFile = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/write-file$/);
  if (method === 'POST' && workspaceFsWriteFile) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsWriteFile[1]), context.device);
    const body = await readJson();
    const filePath = resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(body?.path, 'path'));
    const content = parseRequiredBodyRawString(body?.content, 'content');
    const dataBase64 = Buffer.from(content, 'utf8').toString('base64');
    return highRiskMutationRoute(context, json, {
      workspace,
      method: 'fs/writeFile',
      risk: 'write',
      action: (client) => client.writeFile({ path: filePath, dataBase64 })
    });
  }

  const workspaceFsCopy = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/copy$/);
  if (method === 'POST' && workspaceFsCopy) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsCopy[1]), context.device);
    const body = await readJson();
    const sourcePath = resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(body?.sourcePath || body?.source, 'sourcePath'));
    const destinationPath = resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(body?.destinationPath || body?.destination, 'destinationPath'));
    return highRiskMutationRoute(context, json, {
      workspace,
      method: 'fs/copy',
      risk: 'write',
      action: (client) => client.copyFile({ sourcePath, destinationPath })
    });
  }

  const workspaceFsCreateDirectory = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/create-directory$/);
  if (method === 'POST' && workspaceFsCreateDirectory) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsCreateDirectory[1]), context.device);
    const body = await readJson();
    const directoryPath = resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(body?.path, 'path'));
    return highRiskMutationRoute(context, json, {
      workspace,
      method: 'fs/createDirectory',
      risk: 'write',
      action: (client) => client.createDirectory({ path: directoryPath })
    });
  }

  const workspaceFsRemove = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fs\/remove$/);
  if (method === 'DELETE' && workspaceFsRemove) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFsRemove[1]), context.device);
    const body = await readJson();
    const filePath = resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(body?.path, 'path'));
    return highRiskMutationRoute(context, json, {
      workspace,
      method: 'fs/remove',
      risk: 'write',
      action: (client) => client.removeFile({ path: filePath })
    });
  }

  const workspaceProcesses = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/processes$/);
  if (method === 'POST' && workspaceProcesses) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceProcesses[1]), context.device);
    const body = await readJson();
    const cwd = resolveWorkspaceOptionalCwd(workspace, body?.cwd);
    const request = compactObject({
      command: parseCommandVector(body),
      cwd,
      processHandle: `process_${crypto.randomUUID()}`
    });
    return highRiskMutationRoute(context, json, {
      workspace,
      method: 'process/spawn',
      risk: 'process',
      action: (client) => client.spawnProcess(request)
    });
  }

  const workspaceProcessKill = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/processes\/([^/]+)\/kill$/);
  if (method === 'POST' && workspaceProcessKill) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceProcessKill[1]), context.device);
    const processHandle = parseRequiredPathString(decodePathParam(workspaceProcessKill[2]), 'processHandle');
    return highRiskMutationRoute(context, json, {
      workspace,
      method: 'process/kill',
      risk: 'process',
      action: (client) => client.killProcess({ processHandle })
    });
  }

  const workspaceCommandExec = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/commands\/exec$/);
  if (method === 'POST' && workspaceCommandExec) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceCommandExec[1]), context.device);
    const body = await readJson();
    const cwd = resolveWorkspaceOptionalCwd(workspace, body?.cwd);
    const request = {
      command: parseCommandVector(body),
      cwd
    };
    return highRiskMutationRoute(context, json, {
      workspace,
      method: 'command/exec',
      risk: 'process',
      action: (client) => client.executeCommand(request)
    });
  }

  const workspaceThreads = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads$/);
  if (method === 'GET' && workspaceThreads) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreads[1]), context.device);
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const archived = parseBoolean(url.searchParams.get('archived'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.listThreads(compactObject({
      cwd: workspaceRoot(workspace),
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
    const query = parseRequiredQueryString(url.searchParams.get('query'), 'query');
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.searchThreads(compactObject({
      searchTerm: query,
      limit,
      cursor
    })));
    json(200, normalizeThreadListResponse(response));
    return true;
  }

  const workspaceFuzzySearch = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fuzzy-file-search$/);
  if (method === 'GET' && workspaceFuzzySearch) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFuzzySearch[1]), context.device);
    const query = parseRequiredQueryString(url.searchParams.get('q'), 'q');
    parseLimit(url.searchParams.get('limit'), 50);
    const request = {
      query,
      roots: [workspaceRoot(workspace)]
    };
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.fuzzyFileSearch(request));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceFuzzySearchSessions = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fuzzy-file-search\/sessions$/);
  if (method === 'POST' && workspaceFuzzySearchSessions) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFuzzySearchSessions[1]), context.device);
    const body = await readJson();
    const query = parseRequiredBodyString(body?.query ?? body?.q, 'query');
    parseOptionalPositiveInteger(body?.limit, 'limit');
    const sessionId = `fuzzy_${crypto.randomUUID()}`;
    const response = await requireService(context).withWorkspaceClient(workspace, async (client) => {
      await client.startFuzzyFileSearchSession({
        sessionId,
        roots: [workspaceRoot(workspace)]
      });
      return client.updateFuzzyFileSearchSession({ sessionId, query });
    });
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceFuzzySearchSession = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/fuzzy-file-search\/sessions\/([^/]+)$/);
  if (method === 'PATCH' && workspaceFuzzySearchSession) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFuzzySearchSession[1]), context.device);
    const sessionId = parseRequiredPathString(decodePathParam(workspaceFuzzySearchSession[2]), 'sessionId');
    const body = await readJson();
    parseOptionalPositiveInteger(body?.limit, 'limit');
    const request = {
      sessionId,
      query: parseRequiredBodyString(body?.query ?? body?.q, 'query')
    };
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.updateFuzzyFileSearchSession(compactObject(request)));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  if (method === 'DELETE' && workspaceFuzzySearchSession) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceFuzzySearchSession[1]), context.device);
    const sessionId = parseRequiredPathString(decodePathParam(workspaceFuzzySearchSession[2]), 'sessionId');
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => client.stopFuzzyFileSearchSession({
      sessionId
    }));
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  }

  const workspaceReviewStart = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/review\/start$/);
  if (method === 'POST' && workspaceReviewStart) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceReviewStart[1]), context.device);
    const body = await readJson();
    const request = parseReviewStartBody(body);
    return auditedDiagnosticRoute(context, json, {
      workspace,
      threadId: request.threadId,
      method: 'review/start',
      risk: 'permission',
      event: 'review_start',
      action: async (client) => {
        await preflightThreadWorkspaceOwnership({ client, workspace, threadId: request.threadId });
        return client.startReview(request);
      }
    });
  }

  const workspaceAttestationGenerate = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/attestation\/generate$/);
  if (method === 'POST' && workspaceAttestationGenerate) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceAttestationGenerate[1]), context.device);
    const body = await readJson();
    const challenge = parseOptionalBoundedBodyString(body?.challenge, 'challenge', 4096);
    return auditedDiagnosticRoute(context, json, {
      workspace,
      method: 'attestation/generate',
      risk: 'permission',
      event: 'attestation_generate',
      action: (client) => client.generateAttestation(compactObject({
        workspacePath: workspaceRoot(workspace),
        challenge
      }))
    });
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/realtime/voices') {
    const response = await requireService(context).withDiscoveryClient((client) => client.listRealtimeVoices());
    json(200, normalizeDiscoveryResponse(response, { collectionKey: 'voices', candidateKeys: ['voices', 'data', 'items'] }));
    return true;
  }

  const workspaceRealtimeStart = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/realtime\/start$/);
  if (method === 'POST' && workspaceRealtimeStart) {
    context.workspaces.getAuthorized(decodePathParam(workspaceRealtimeStart[1]), context.device);
    throw diagnosticOnlyRouteError('thread/realtime/start');
  }

  const workspaceRealtimeAppendText = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/realtime\/([^/]+)\/append-text$/);
  if (method === 'POST' && workspaceRealtimeAppendText) {
    context.workspaces.getAuthorized(decodePathParam(workspaceRealtimeAppendText[1]), context.device);
    parseRequiredPathString(decodePathParam(workspaceRealtimeAppendText[2]), 'sessionId');
    throw diagnosticOnlyRouteError('thread/realtime/appendText');
  }

  const workspaceRealtimeAppendAudio = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/realtime\/([^/]+)\/append-audio$/);
  if (method === 'POST' && workspaceRealtimeAppendAudio) {
    context.workspaces.getAuthorized(decodePathParam(workspaceRealtimeAppendAudio[1]), context.device);
    parseRequiredPathString(decodePathParam(workspaceRealtimeAppendAudio[2]), 'sessionId');
    throw diagnosticOnlyRouteError('thread/realtime/appendAudio');
  }

  const workspaceRealtimeStop = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/realtime\/([^/]+)\/stop$/);
  if (method === 'POST' && workspaceRealtimeStop) {
    context.workspaces.getAuthorized(decodePathParam(workspaceRealtimeStop[1]), context.device);
    parseRequiredPathString(decodePathParam(workspaceRealtimeStop[2]), 'sessionId');
    throw diagnosticOnlyRouteError('thread/realtime/stop');
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
    parseOptionalBodyString(body?.fromTurnId, 'fromTurnId');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/fork',
      event: 'thread_fork',
      preflight: preflightThreadWorkspaceOwnership,
      action: (client) => client.forkThread(compactObject({
        threadId,
        cwd: workspaceRoot(workspace)
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
      preflight: preflightThreadWorkspaceOwnership,
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
      preflight: preflightThreadWorkspaceOwnership,
      action: (client) => client.unarchiveThread({ threadId })
    });
  }

  const workspaceThreadRollback = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/rollback$/);
  if (method === 'POST' && workspaceThreadRollback) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadRollback[1]), context.device);
    const threadId = decodePathParam(workspaceThreadRollback[2]);
    const body = await readJson();
    const numTurns = parseRequiredPositiveInteger(body?.numTurns, 'numTurns');
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/rollback',
      event: 'thread_rollback',
      preflight: preflightThreadWorkspaceOwnership,
      action: (client) => client.rollbackThread(compactObject({
        threadId,
        numTurns
      }))
    });
  }

  const workspaceThreadMetadata = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/metadata$/);
  if (method === 'PATCH' && workspaceThreadMetadata) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadMetadata[1]), context.device);
    const threadId = decodePathParam(workspaceThreadMetadata[2]);
    const body = await readJson();
    const gitInfo = parseThreadGitInfoUpdate(body);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/metadata/update',
      event: 'thread_metadata_update',
      action: (client) => client.updateThreadMetadata({
        threadId,
        gitInfo
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
    const request = normalizeThreadSettings(settings, workspace);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/settings/update',
      event: 'thread_settings_update',
      action: (client) => client.updateThreadSettings({
        threadId,
        ...request
      })
    });
  }

  const workspaceThreadMemoryMode = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/memory-mode$/);
  if (method === 'PATCH' && workspaceThreadMemoryMode) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadMemoryMode[1]), context.device);
    const threadId = decodePathParam(workspaceThreadMemoryMode[2]);
    const body = await readJson();
    const mode = parseThreadMemoryMode(body?.mode ?? body?.memoryMode);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/memoryMode/set',
      event: 'thread_memory_mode_set',
      action: (client) => client.setThreadMemoryMode({
        threadId,
        mode
      })
    });
  }

  const workspaceThreadGoalPut = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads\/([^/]+)\/goal$/);
  if (method === 'PUT' && workspaceThreadGoalPut) {
    const workspace = context.workspaces.getAuthorized(decodePathParam(workspaceThreadGoalPut[1]), context.device);
    const threadId = decodePathParam(workspaceThreadGoalPut[2]);
    const body = await readJson();
    const goal = parseThreadGoalSet(body);
    return threadMutationRoute(context, json, {
      workspace,
      threadId,
      method: 'thread/goal/set',
      event: 'thread_goal_set',
      action: (client) => client.setThreadGoal({
        threadId,
        ...goal
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

  if (method === 'PATCH' && url.pathname === '/api/codex-app-server/config/value') {
    const body = await readJson();
    const request = {
      keyPath: parseRequiredBodyString(body?.keyPath ?? body?.key, 'keyPath'),
      mergeStrategy: parseMergeStrategy(body?.mergeStrategy),
      value: parseDefinedValue(body?.value, 'value')
    };
    return highRiskMutationRoute(context, json, {
      method: 'config/value/write',
      risk: 'write',
      action: (client) => client.writeConfigValue(request)
    });
  }

  if (method === 'PATCH' && url.pathname === '/api/codex-app-server/config/batch') {
    const body = await readJson();
    const edits = parseConfigBatchEdits(body);
    return highRiskMutationRoute(context, json, {
      method: 'config/batchWrite',
      risk: 'write',
      action: (client) => client.writeConfigBatch({ edits })
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/config/mcp-server/reload') {
    await readJson();
    return highRiskMutationRoute(context, json, {
      method: 'config/mcpServer/reload',
      risk: 'write',
      action: (client) => client.reloadMcpServerConfig(null)
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/environment') {
    const body = await readJson();
    const request = {
      environmentId: parseRequiredBodyString(body?.environmentId ?? body?.name, 'environmentId'),
      execServerUrl: parseRequiredBodyString(body?.execServerUrl ?? body?.value, 'execServerUrl')
    };
    return highRiskMutationRoute(context, json, {
      method: 'environment/add',
      risk: 'write',
      action: (client) => client.addEnvironment(request)
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/plugins/install') {
    const body = await readJson();
    const request = compactObject({
      pluginName: parseRequiredBodyString(body?.pluginName ?? body?.pluginId, 'pluginName'),
      marketplacePath: parseOptionalBodyString(body?.marketplacePath, 'marketplacePath'),
      remoteMarketplaceName: parseOptionalBodyString(body?.remoteMarketplaceName, 'remoteMarketplaceName')
    });
    return highRiskMutationRoute(context, json, {
      method: 'plugin/install',
      risk: 'write',
      action: (client) => client.installPlugin(request)
    });
  }

  const pluginUninstall = url.pathname.match(/^\/api\/codex-app-server\/plugins\/([^/]+)\/uninstall$/);
  if (method === 'POST' && pluginUninstall) {
    const pluginId = decodePathParam(pluginUninstall[1]);
    return highRiskMutationRoute(context, json, {
      method: 'plugin/uninstall',
      risk: 'write',
      action: (client) => client.uninstallPlugin({ pluginId })
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/marketplace/add') {
    const body = await readJson();
    const request = compactObject({
      source: parseRequiredBodyString(body?.source ?? body?.url, 'source'),
      refName: parseOptionalBodyString(body?.refName, 'refName'),
      sparsePaths: parseOptionalStringArray(body?.sparsePaths, 'sparsePaths')
    });
    return highRiskMutationRoute(context, json, {
      method: 'marketplace/add',
      risk: 'write',
      action: (client) => client.addMarketplace(request)
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/marketplace/remove') {
    const body = await readJson();
    const request = { marketplaceName: parseRequiredBodyString(body?.marketplaceName ?? body?.marketplaceId, 'marketplaceName') };
    return highRiskMutationRoute(context, json, {
      method: 'marketplace/remove',
      risk: 'write',
      action: (client) => client.removeMarketplace(request)
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/marketplace/upgrade') {
    const body = await readJson();
    const request = compactObject({
      marketplaceName: parseOptionalBodyString(body?.marketplaceName ?? body?.marketplaceId, 'marketplaceName')
    });
    return highRiskMutationRoute(context, json, {
      method: 'marketplace/upgrade',
      risk: 'write',
      action: (client) => client.upgradeMarketplace(request)
    });
  }

  if (method === 'PATCH' && url.pathname === '/api/codex-app-server/skills/config') {
    const body = await readJson();
    const source = body?.config && typeof body.config === 'object' && !Array.isArray(body.config)
      ? body.config
      : body;
    const request = compactObject({
      enabled: parseRequiredBoolean(source?.enabled, 'enabled'),
      name: parseOptionalBodyString(source?.name, 'name'),
      path: parseOptionalBodyString(source?.path, 'path')
    });
    return highRiskMutationRoute(context, json, {
      method: 'skills/config/write',
      risk: 'write',
      action: (client) => client.writeSkillsConfig(request)
    });
  }

  if (method === 'PATCH' && url.pathname === '/api/codex-app-server/skills/extra-roots') {
    const body = await readJson();
    const request = { extraRoots: parseRequiredStringArray(body?.extraRoots ?? body?.roots, 'extraRoots') };
    return highRiskMutationRoute(context, json, {
      method: 'skills/extraRoots/set',
      risk: 'write',
      action: (client) => client.setSkillsExtraRoots(request)
    });
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/remote-control/status') {
    return discoveryRoute(context, json, (client) => client.readRemoteControlStatus(), {});
  }

  if (method === 'GET' && url.pathname === '/api/codex-app-server/remote-control/clients') {
    const environmentId = parseRequiredQueryString(url.searchParams.get('environmentId'), 'environmentId');
    const cursor = parseOptionalString(url.searchParams.get('cursor'));
    const limit = parseOptionalPositiveIntegerParam(url.searchParams.get('limit'), 'limit');
    const order = parseRemoteControlClientOrder(url.searchParams.get('order'));
    return discoveryRoute(
      context,
      json,
      (client) => client.listRemoteControlClients(compactObject({ environmentId, cursor, limit, order })),
      { collectionKey: 'clients', candidateKeys: ['clients', 'data', 'items'] }
    );
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/remote-control/enable') {
    return highRiskMutationRoute(context, json, {
      method: 'remoteControl/enable',
      risk: 'network',
      action: (client) => client.enableRemoteControl()
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/remote-control/disable') {
    return highRiskMutationRoute(context, json, {
      method: 'remoteControl/disable',
      risk: 'network',
      action: (client) => client.disableRemoteControl()
    });
  }

  if (method === 'POST' && url.pathname === '/api/codex-app-server/remote-control/pairing/start') {
    const body = await readJson();
    parseOptionalPositiveInteger(body?.timeoutSecs, 'timeoutSecs');
    const request = compactObject({
      manualCode: parseOptionalBoolean(body?.manualCode, 'manualCode')
    });
    return highRiskMutationRoute(context, json, {
      method: 'remoteControl/pairing/start',
      risk: 'network',
      action: (client) => client.startRemoteControlPairing(request)
    });
  }

  const remoteClientRevoke = url.pathname.match(/^\/api\/codex-app-server\/remote-control\/clients\/([^/]+)\/revoke$/);
  if (method === 'POST' && remoteClientRevoke) {
    const body = await readJson();
    const clientId = parseRequiredPathString(decodePathParam(remoteClientRevoke[1]), 'clientId');
    const environmentId = parseRequiredBodyString(
      url.searchParams.get('environmentId') ?? body?.environmentId,
      'environmentId'
    );
    return highRiskMutationRoute(context, json, {
      method: 'remoteControl/client/revoke',
      risk: 'network',
      action: (client) => client.revokeRemoteControlClient({ clientId, environmentId })
    });
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

async function highRiskMutationRoute(context, json, { workspace = null, method, risk, action }) {
  const correlationId = createCorrelationId();
  const workspaceId = workspace?.id || workspace?.workspaceId || null;
  const metadata = {
    method,
    workspaceId,
    deviceId: context.device?.id || null,
    risk,
    correlationId
  };
  try {
    const approval = requireHighRiskApproval({
      method,
      approvalPolicy: context.approvalPolicy
    });
    const service = requireService(context);
    const response = await service.withMutationClient({
      method,
      risk,
      workspaceId,
      workspacePath: workspace ? workspaceRoot(workspace) : undefined
    }, (client) => action(client));
    recordCodexAppServerAudit(context.auditLog, 'high_risk_success', {
      ...metadata,
      decision: approval.decision,
      ok: true
    });
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  } catch (error) {
    if (error?.code === 'CODEX_APP_SERVER_APPROVAL_REQUIRED') {
      recordCodexAppServerAudit(context.auditLog, 'high_risk_denial', {
        ...metadata,
        decision: 'deny',
        result: 'denied',
        errorCode: error.code
      });
      throw error;
    }
    const sanitized = sanitizeHighRiskMutationError(error);
    recordCodexAppServerAudit(context.auditLog, 'high_risk_failure', {
      ...metadata,
      decision: 'allow',
      result: 'failure',
      errorCode: sanitized.downstreamCode || sanitized.errorCode,
      downstreamStatus: sanitized.downstreamStatus
    });
    if (isSafeLocalInfrastructureError(error)) throw error;
    throw controlledHighRiskMutationError();
  }
}

async function auditedDiagnosticRoute(context, json, { workspace, threadId, method, risk, event, action }) {
  const correlationId = createCorrelationId();
  const metadata = {
    method,
    workspaceId: workspace?.id || workspace?.workspaceId || null,
    workspacePath: workspace ? workspaceRoot(workspace) : undefined,
    threadId,
    deviceId: context.device?.id || null,
    risk,
    correlationId
  };
  try {
    const response = await requireService(context).withWorkspaceClient(workspace, (client) => action(client));
    recordCodexAppServerAudit(context.auditLog, event, {
      ...metadata,
      decision: 'allow',
      ok: true
    });
    json(200, normalizeDiscoveryResponse(response, {}));
    return true;
  } catch (error) {
    const sanitized = sanitizeHighRiskMutationError(error);
    recordCodexAppServerAudit(context.auditLog, event, {
      ...metadata,
      decision: 'allow',
      result: 'failure',
      errorCode: sanitized.downstreamCode || sanitized.errorCode,
      downstreamStatus: sanitized.downstreamStatus
    });
    if (isSafeLocalInfrastructureError(error)) throw error;
    throw controlledHighRiskMutationError('Codex app-server diagnostic operation failed.');
  }
}

async function threadMutationRoute(context, json, { workspace, threadId, method, event, preflight = preflightThreadWorkspaceOwnership, skipPreflight = false, action }) {
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
    const response = await requireService(context).withMutationClient(metadata, async (client) => {
      if (!skipPreflight && preflight) await preflight({ client, workspace, threadId });
      return action(client);
    });
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
    if (error?.threadWorkspaceOwnershipDenied === true) {
      recordCodexAppServerAudit(context.auditLog, event, {
        method,
        workspaceId: metadata.workspaceId,
        threadId,
        deviceId: context.device?.id || null,
        risk,
        decision: 'deny',
        result: 'failure',
        errorCode: 'FORBIDDEN',
        correlationId
      });
      throw error;
    }
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
      downstreamStatus: sanitized.downstreamStatus,
      correlationId
    });
    if (isSafeLocalInfrastructureError(error)) throw error;
    throw controlledThreadMutationError();
  }
}

async function preflightThreadWorkspaceOwnership({ client, workspace, threadId }) {
  const response = await client.readThread({ threadId });
  const workspacePath = response?.thread?.workspacePath || response?.workspacePath;
  if (!workspacePath || !pathsReferToSameLocation(workspacePath, workspaceRoot(workspace))) {
    throw Object.assign(forbidden('thread does not belong to authorized workspace'), {
      threadWorkspaceOwnershipDenied: true
    });
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

function parseDefinedValue(value, name) {
  if (value === undefined) throw badRequest(`${name} is required`);
  return value;
}

function parseRequiredStringArray(value, name) {
  if (!Array.isArray(value)) throw badRequest(`${name} must be an array of strings`);
  return value.map((entry) => parseRequiredStringValue(entry, name));
}

function parseCommandVector(body) {
  if (Array.isArray(body?.command)) {
    if (body?.args !== undefined && body?.args !== null) {
      throw badRequest('args cannot be combined with command array');
    }
    const command = parseRequiredStringArray(body.command, 'command');
    if (command.length === 0) throw badRequest('command must not be empty');
    return command;
  }
  const executable = parseRequiredBodyString(body?.command, 'command');
  const args = parseOptionalStringArray(body?.args, 'args') || [];
  return [executable, ...args];
}

function parseConfigBatchEdits(body) {
  if (Array.isArray(body?.edits)) {
    if (body.edits.length === 0) throw badRequest('edits must not be empty');
    return body.edits.map((edit, index) => parseConfigEdit(edit, `edits[${index}]`));
  }
  const values = parseRequiredObject(body?.values, 'values');
  return Object.entries(values).map(([keyPath, value]) => ({
    keyPath: parseRequiredStringValue(keyPath, 'keyPath'),
    mergeStrategy: 'replace',
    value
  }));
}

function parseConfigEdit(edit, name) {
  const parsed = parseRequiredObject(edit, name);
  return {
    keyPath: parseRequiredBodyString(parsed.keyPath ?? parsed.key, `${name}.keyPath`),
    mergeStrategy: parseMergeStrategy(parsed.mergeStrategy),
    value: parseDefinedValue(parsed.value, `${name}.value`)
  };
}

function parseMergeStrategy(value) {
  if (value === undefined || value === null || value === '') return 'replace';
  if (value === 'replace' || value === 'upsert') return value;
  throw badRequest('mergeStrategy must be replace or upsert');
}

function parseOptionalStringArray(value, name) {
  if (value === undefined || value === null) return undefined;
  return parseRequiredStringArray(value, name);
}

function parseOptionalPositiveInteger(value, name) {
  if (value === undefined || value === null) return undefined;
  if (!Number.isInteger(value) || value < 1) throw badRequest(`${name} must be a positive integer`);
  return value;
}

function parseRequiredPositiveInteger(value, name) {
  const parsed = parseOptionalPositiveInteger(value, name);
  if (parsed === undefined) throw badRequest(`${name} is required`);
  return parsed;
}

function parseOptionalPositiveIntegerParam(value, name) {
  if (value === undefined || value === null || value === '') return undefined;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) throw badRequest(`${name} must be a positive integer`);
  return parsed;
}

function parseRequiredBoolean(value, name) {
  if (typeof value !== 'boolean') throw badRequest(`${name} must be a boolean`);
  return value;
}

function parseOptionalBoolean(value, name) {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'boolean') throw badRequest(`${name} must be a boolean`);
  return value;
}

function parseRemoteControlClientOrder(value) {
  if (value === undefined || value === null || value === '') return undefined;
  if (value === 'asc' || value === 'desc') return value;
  throw badRequest('order must be asc or desc');
}

function parseRequiredQueryString(value, name) {
  if (value === undefined || value === null || String(value).trim() === '') {
    throw badRequest(`${name} query parameter is required`);
  }
  return value;
}

function parseRequiredPathString(value, name) {
  if (value === undefined || value === null || String(value).trim() === '') {
    throw badRequest(`${name} path parameter is required`);
  }
  return String(value).trim();
}

function parseRequiredBodyString(value, name) {
  if (value === undefined || value === null || String(value).trim() === '') {
    throw badRequest(`${name} is required`);
  }
  return String(value).trim();
}

function parseRequiredBodyRawString(value, name) {
  if (value === undefined || value === null) {
    throw badRequest(`${name} is required`);
  }
  if (typeof value !== 'string') {
    throw badRequest(`${name} must be a string`);
  }
  return value;
}

function parseOptionalBoundedBodyString(value, name, maxLength) {
  if (value === undefined || value === null) return undefined;
  const parsed = parseRequiredStringValue(value, name);
  if (parsed.length > maxLength) throw badRequest(`${name} must be at most ${maxLength} characters`);
  return parsed;
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

function parseThreadGitInfoUpdate(body) {
  const source = Object.prototype.hasOwnProperty.call(body || {}, 'gitInfo')
    ? body.gitInfo
    : body?.metadata?.gitInfo;
  if (source === undefined) throw badRequest('gitInfo is required');
  if (source === null) return null;
  const gitInfo = parseRequiredObject(source, 'gitInfo');
  assertAllowedKeys(gitInfo, ['branch', 'originUrl', 'sha'], 'gitInfo');
  return compactDefinedObject({
    branch: parseOptionalNullableBodyString(gitInfo.branch, 'gitInfo.branch'),
    originUrl: parseOptionalNullableBodyString(gitInfo.originUrl, 'gitInfo.originUrl'),
    sha: parseOptionalNullableBodyString(gitInfo.sha, 'gitInfo.sha')
  });
}

function normalizeThreadSettings(settings, workspace) {
  assertAllowedKeys(settings, [
    'approvalPolicy',
    'approvalsReviewer',
    'collaborationMode',
    'cwd',
    'effort',
    'model',
    'permissions',
    'personality',
    'sandboxPolicy',
    'serviceTier',
    'summary'
  ], 'settings');
  const request = compactDefinedObject({
    approvalPolicy: settings.approvalPolicy,
    approvalsReviewer: settings.approvalsReviewer,
    collaborationMode: settings.collaborationMode,
    effort: settings.effort,
    model: settings.model,
    permissions: settings.permissions,
    personality: settings.personality,
    sandboxPolicy: settings.sandboxPolicy,
    serviceTier: settings.serviceTier,
    summary: settings.summary
  });
  if (Object.prototype.hasOwnProperty.call(settings, 'cwd')) {
    request.cwd = settings.cwd === null ? null : resolveWorkspaceOptionalCwd(workspace, settings.cwd);
  }
  return request;
}

function parseThreadMemoryMode(value) {
  const mode = parseRequiredBodyString(value, 'mode');
  if (mode !== 'enabled' && mode !== 'disabled') throw badRequest('mode must be enabled or disabled');
  return mode;
}

function parseThreadGoalSet(body) {
  let source;
  if (body && Object.prototype.hasOwnProperty.call(body, 'goal')) {
    if (typeof body.goal === 'string') {
      source = { objective: parseRequiredBodyString(body.goal, 'goal') };
    } else if (body.goal && typeof body.goal === 'object' && !Array.isArray(body.goal)) {
      source = body.goal;
    } else {
      throw badRequest('goal is required');
    }
  } else if (
    Object.prototype.hasOwnProperty.call(body || {}, 'objective') ||
    Object.prototype.hasOwnProperty.call(body || {}, 'status') ||
    Object.prototype.hasOwnProperty.call(body || {}, 'tokenBudget')
  ) {
    source = body;
  } else {
    throw badRequest('goal is required');
  }
  assertAllowedKeys(source, ['objective', 'status', 'tokenBudget'], 'goal');
  const result = compactDefinedObject({
    objective: parseOptionalNullableBodyString(source.objective, 'goal.objective'),
    status: parseThreadGoalStatus(source.status),
    tokenBudget: parseThreadGoalTokenBudget(source.tokenBudget)
  });
  return result;
}

function parseOptionalNullableBodyString(value, name) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  return parseRequiredBodyString(value, name);
}

function parseThreadGoalStatus(value) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const status = parseRequiredBodyString(value, 'goal.status');
  if (!['active', 'paused', 'blocked', 'usageLimited', 'budgetLimited', 'complete'].includes(status)) {
    throw badRequest('goal.status is invalid');
  }
  return status;
}

function parseThreadGoalTokenBudget(value) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (!Number.isInteger(value) || value < 0) throw badRequest('goal.tokenBudget must be a nonnegative integer');
  return value;
}

function parseReviewStartBody(body) {
  const request = parseRequiredObject(body, 'body');
  assertAllowedKeys(request, ['threadId', 'target', 'delivery'], 'review');
  return compactDefinedObject({
    threadId: parseRequiredBodyString(request.threadId, 'threadId'),
    target: parseReviewTarget(request.target),
    delivery: parseReviewDelivery(request.delivery)
  });
}

function parseReviewDelivery(value) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const delivery = parseRequiredBodyString(value, 'delivery');
  if (delivery !== 'inline' && delivery !== 'detached') throw badRequest('delivery must be inline or detached');
  return delivery;
}

function parseReviewTarget(value) {
  const target = parseRequiredObject(value, 'target');
  const type = parseRequiredBodyString(target.type, 'target.type');
  if (type === 'uncommittedChanges') {
    assertAllowedKeys(target, ['type'], 'target');
    return { type };
  }
  if (type === 'baseBranch') {
    assertAllowedKeys(target, ['type', 'branch'], 'target');
    return { type, branch: parseRequiredBodyString(target.branch, 'target.branch') };
  }
  if (type === 'commit') {
    assertAllowedKeys(target, ['type', 'sha', 'title'], 'target');
    return compactDefinedObject({
      type,
      sha: parseRequiredBodyString(target.sha, 'target.sha'),
      title: parseOptionalNullableBodyString(target.title, 'target.title')
    });
  }
  if (type === 'custom') {
    assertAllowedKeys(target, ['type', 'instructions'], 'target');
    return { type, instructions: parseRequiredBodyString(target.instructions, 'target.instructions') };
  }
  throw badRequest('target.type is invalid');
}

function assertAllowedKeys(value, allowed, name) {
  const allowedSet = new Set(allowed);
  for (const key of Object.keys(value || {})) {
    if (!allowedSet.has(key)) throw badRequest(`${name}.${key} is not supported`);
  }
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
  assertPathWithinWorkspace(resolved, resolvedRoot);
  assertRealPathWithinWorkspace(resolved, resolvedRoot);
  return resolved;
}

function resolveWorkspaceOptionalCwd(workspace, relativePath) {
  if (relativePath === undefined || relativePath === null || String(relativePath).trim() === '') return workspaceRoot(workspace);
  return resolveWorkspaceRelativePath(workspace, parseRequiredBodyString(relativePath, 'cwd'));
}

function pathsReferToSameLocation(left, right) {
  if (!left || !right) return false;
  return normalizePathForGuard(path.resolve(left)) === normalizePathForGuard(path.resolve(right));
}

function assertPathWithinWorkspace(target, root) {
  const comparableRoot = normalizePathForGuard(root);
  const comparableTarget = normalizePathForGuard(target);
  if (comparableTarget === comparableRoot || comparableTarget.startsWith(`${comparableRoot}${path.sep}`)) return;
  throwForbiddenPathEscape();
}

function assertRealPathWithinWorkspace(target, root) {
  const realRoot = tryRealpath(root);
  if (!realRoot) return;
  const realTarget = realpathClosestExisting(target, root);
  assertPathWithinWorkspace(realTarget, realRoot);
}

function realpathClosestExisting(target, root) {
  let current = target;
  while (true) {
    try {
      return realpath(current);
    } catch (error) {
      if (error?.code !== 'ENOENT' && error?.code !== 'ENOTDIR') throw error;
      const parent = path.dirname(current);
      if (parent === current || !isLexicallyWithinRoot(parent, root)) return realpath(root);
      current = parent;
    }
  }
}

function realpath(value) {
  const nativeRealpath = fs.realpathSync.native || fs.realpathSync;
  return nativeRealpath(value);
}

function tryRealpath(value) {
  try {
    return realpath(value);
  } catch (error) {
    if (error?.code === 'ENOENT' || error?.code === 'ENOTDIR') return null;
    throw error;
  }
}

function isLexicallyWithinRoot(target, root) {
  const comparableRoot = normalizePathForGuard(root);
  const comparableTarget = normalizePathForGuard(target);
  return comparableTarget === comparableRoot || comparableTarget.startsWith(`${comparableRoot}${path.sep}`);
}

function throwForbiddenPathEscape() {
  throw Object.assign(new Error('path outside authorized workspace'), {
    status: 403,
    code: 'FORBIDDEN'
  });
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

function forbidden(message) {
  return Object.assign(new Error(message || 'forbidden'), {
    status: 403,
    code: 'FORBIDDEN'
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

function controlledHighRiskMutationError(message) {
  return Object.assign(new Error(message || 'Codex app-server high-risk operation failed.'), {
    status: 502,
    code: 'CODEX_APP_SERVER_HIGH_RISK_OPERATION_FAILED'
  });
}

function diagnosticOnlyRouteError(method) {
  return Object.assign(new Error(`${method} is diagnostic-only until realtime streaming support is implemented.`), {
    status: 409,
    code: 'CODEX_APP_SERVER_DIAGNOSTIC_ONLY'
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

function sanitizeHighRiskMutationError(error) {
  return {
    errorCode: 'CODEX_APP_SERVER_HIGH_RISK_OPERATION_FAILED',
    downstreamStatus: safeDownstreamStatus(error?.status),
    downstreamCode: safeDownstreamCode(error?.code)
  };
}

function isSafeLocalInfrastructureError(error) {
  const status = safeDownstreamStatus(error?.status);
  const code = safeDownstreamCode(error?.code);
  if (!status || !code) return false;
  return /^(CODEX_APP_SERVER_|BAD_REQUEST|FORBIDDEN|WORKSPACE_|AUTH_|CONVERSATION_|RUN_|ADAPTER_|CLAUDE_|OPENCODE_|GIT_|ATTACHMENT_|UNSUPPORTED_MEDIA_TYPE)/.test(code);
}

function redactAccountSensitiveText(text) {
  if (!text) return '[REDACTED]';
  let value = String(text);
  value = value.replace(/[A-Z]:\\[^\s"'`]+/gi, '[REDACTED]');
  value = value.replace(/\/(?:[^\s"'`/]+\/)+[^\s"'`/]+/g, '[REDACTED]');
  value = value.replace(/\b((?:api[_-]?key|password|secret)\s*[:=]\s*)[^\s,;]+/gi, '$1[REDACTED]');
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

function compactDefinedObject(value) {
  const result = {};
  for (const [key, current] of Object.entries(value || {})) {
    if (current !== undefined) result[key] = current;
  }
  return result;
}

module.exports = {
  SUPPORTED_ROUTE_METHODS,
  decodePathParam,
  parseBoolean,
  parseLimit,
  resolveWorkspaceRelativePath,
  tryHandleCodexAppServerRoute
};
