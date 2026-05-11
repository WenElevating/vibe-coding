'use strict';

const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { URL } = require('node:url');
const { eventTypes, errorCodes } = require('./protocol');

function createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset }) {
  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
      const method = req.method || 'GET';

      if (method === 'GET' && url.pathname === '/api/health') return json(res, 200, await diagnostics.status());
      if (method === 'GET' && url.pathname === '/api/version') return json(res, 200, version);
      if (method === 'POST' && url.pathname === '/api/e2e/smoke') return json(res, 200, await runSmoke({ config, adapterRegistry, eventStore }));
      if (method === 'POST' && url.pathname === '/api/pairing-code') return json(res, 200, auth.createPairingCode());
      if (method === 'POST' && url.pathname === '/api/pair') {
        const body = await readJson(req);
        const paired = auth.pair(body.code, body.label, body.deviceId);
        return json(res, 200, paired);
      }

      if (method === 'POST' && url.pathname === '/api/token/refresh') {
        const body = await readJson(req);
        return json(res, 200, auth.refresh(req.headers.authorization, body.refreshToken, body.deviceId));
      }

      const device = auth.authenticate(req.headers.authorization);

      if (method === 'GET' && url.pathname === '/api/asr-model') return json(res, 200, await asrModelAsset.metadata());
      if (method === 'GET' && url.pathname === '/api/asr-model/download') return asrModelAsset.streamDownload(req, res);
      if (method === 'POST' && url.pathname === '/api/diagnostics/export') return json(res, 200, await diagnosticBundle.exportBundle());
      if (method === 'POST' && url.pathname === '/api/exceptions') return json(res, 201, recordClientException(await readJson(req), { device, diagnosticBundle, req }));
      if (method === 'GET' && url.pathname === '/api/adapters') return json(res, 200, { adapters: await adapterRegistry.listCapabilities() });
      if (method === 'GET' && url.pathname === '/api/extensions') return json(res, 200, await workspaceInspector.extensions(adapterRegistry));
      if (method === 'GET' && url.pathname === '/api/queue') return json(res, 200, { queue: runQueue.list() });
      if (method === 'GET' && url.pathname === '/api/shortcuts') return json(res, 200, { shortcuts: shortcuts.list() });
      if (method === 'POST' && url.pathname === '/api/shortcuts') return json(res, 201, shortcuts.upsert(await readJson(req)));
      if (method === 'GET' && url.pathname === '/api/command-templates') return json(res, 200, { templates: commandTemplates.list() });
      if (method === 'POST' && url.pathname === '/api/command-templates') return json(res, 201, commandTemplates.upsert(await readJson(req)));
      const templateInvoke = url.pathname.match(/^\/api\/command-templates\/([^/]+)\/invoke$/);
      if (method === 'POST' && templateInvoke) return json(res, 201, invokeTemplate(templateInvoke[1], await readJson(req), { commandTemplates, runs, eventStore, device }));
      if (method === 'POST' && url.pathname === `/api/devices/${device.id}/revoke`) return json(res, 200, auth.revokeDevice(device.id, device));
      if (method === 'GET' && url.pathname === '/api/workspaces') return json(res, 200, { workspaces: workspaces.listForDevice(device) });
      if (method === 'POST' && url.pathname === '/api/workspaces') {
        const workspace = workspaces.add(await readJson(req), device);
        auth.allowWorkspace(device.id, workspace.id);
        return json(res, 201, workspace);
      }
      const workspaceMutation = url.pathname.match(/^\/api\/workspaces\/([^/]+)$/);
      if (workspaceMutation && method === 'PATCH') {
        return json(res, 200, workspaces.renameForDevice(workspaceMutation[1], await readJson(req), device));
      }
      if (workspaceMutation && method === 'DELETE') {
        const body = await readJson(req);
        const activeRuns = runs.activeWorkspaceRuns(workspaceMutation[1], device);
        const activeConversations = conversations.activeWorkspaceConversations(workspaceMutation[1], device);
        if ((activeRuns.length > 0 || activeConversations.length > 0) && body.closeActive !== true) {
          const error = new Error('Workspace has active CLI work.');
          error.status = 409;
          error.code = 'WORKSPACE_HAS_ACTIVE_CLI';
          error.recoverable = true;
          error.userAction = 'Confirm deletion to close active CLI work and remove this workspace from the device.';
          throw error;
        }
        if (body.closeActive === true) {
          runs.cancelWorkspaceRuns(workspaceMutation[1], device);
          await conversations.cancelWorkspaceConversations(workspaceMutation[1], device);
        }
        const workspace = workspaces.deleteForDevice(workspaceMutation[1], device);
        return json(res, 200, { workspaceId: workspace.id, workspace, workspaces: workspaces.listForDevice(device) });
      }
      if (method === 'GET' && url.pathname === '/api/fs/roots') return json(res, 200, { roots: await listRoots() });
      if (method === 'GET' && url.pathname === '/api/fs/children') return json(res, 200, await listDirectory(url.searchParams.get('path') || ''));

      const workspaceOverview = url.pathname.match(/^\/api\/workspaces\/([^/]+)\/overview$/);
      if (method === 'GET' && workspaceOverview) return json(res, 200, workspaceInspector.overview(workspaces.getAuthorized(workspaceOverview[1], device)));
      const workspaceTree = url.pathname.match(/^\/api\/workspaces\/([^/]+)\/files\/tree$/);
      if (method === 'GET' && workspaceTree) return json(res, 200, workspaceInspector.tree(workspaces.getAuthorized(workspaceTree[1], device), { relativePath: url.searchParams.get('path') || '', maxDepth: url.searchParams.get('maxDepth') || 8 }));
      const workspaceContent = url.pathname.match(/^\/api\/workspaces\/([^/]+)\/files\/content$/);
      if (method === 'GET' && workspaceContent) return json(res, 200, workspaceInspector.content(workspaces.getAuthorized(workspaceContent[1], device), url.searchParams.get('path') || ''));
      const workspaceDiagnostics = url.pathname.match(/^\/api\/workspaces\/([^/]+)\/diagnostics\/code$/);
      if (method === 'GET' && workspaceDiagnostics) return json(res, 200, workspaceInspector.diagnostics(workspaces.getAuthorized(workspaceDiagnostics[1], device)));

      const gitStatus = url.pathname.match(/^\/api\/workspaces\/([^/]+)\/git\/status$/);
      if (method === 'GET' && gitStatus) return json(res, 200, gitService.status(workspaces.getAuthorized(gitStatus[1], device)));
      const gitDiff = url.pathname.match(/^\/api\/workspaces\/([^/]+)\/git\/diff$/);
      if (method === 'GET' && gitDiff) return json(res, 200, gitService.diff(workspaces.getAuthorized(gitDiff[1], device)));
      const gitCommits = url.pathname.match(/^\/api\/workspaces\/([^/]+)\/git\/commits$/);
      if (method === 'GET' && gitCommits) return json(res, 200, workspaceInspector.commits(workspaces.getAuthorized(gitCommits[1], device), { limit: url.searchParams.get('limit') || 20 }));

      if (method === 'GET' && url.pathname === '/api/conversations') return json(res, 200, { conversations: conversations.listConversations(device) });
      if (method === 'POST' && url.pathname === '/api/conversations') return json(res, 201, { conversation: conversations.createConversation(await readJson(req), device) });
      const conversationEvents = url.pathname.match(/^\/api\/conversations\/([^/]+)\/events$/);
      if (method === 'GET' && conversationEvents) {
        const afterSeq = Number(url.searchParams.get('afterSeq') || 0);
        return json(res, 200, { events: conversations.listEvents(conversationEvents[1], afterSeq, device) });
      }
      const conversationMessages = url.pathname.match(/^\/api\/conversations\/([^/]+)\/messages$/);
      if (method === 'POST' && conversationMessages) return json(res, 200, { conversation: await conversations.sendMessage(conversationMessages[1], await readJson(req), device) });
      const conversationQuestion = url.pathname.match(/^\/api\/conversations\/([^/]+)\/questions\/respond$/);
      if (method === 'POST' && conversationQuestion) return json(res, 200, { conversation: await conversations.answerQuestion(conversationQuestion[1], await readJson(req), device) });
      const conversationApproval = url.pathname.match(/^\/api\/conversations\/([^/]+)\/approvals\/([^/]+)\/respond$/);
      if (method === 'POST' && conversationApproval) return json(res, 200, { conversation: await conversations.respondApproval(conversationApproval[1], conversationApproval[2], await readJson(req), device) });
      const conversationCancel = url.pathname.match(/^\/api\/conversations\/([^/]+)\/cancel$/);
      if (method === 'POST' && conversationCancel) return json(res, 200, { conversation: await conversations.cancelConversation(conversationCancel[1], device) });

      if (method === 'GET' && url.pathname === '/api/runs') return json(res, 200, { runs: runs.listRuns(device, Object.fromEntries(url.searchParams.entries())) });
      if (method === 'POST' && url.pathname === '/api/runs') {
        const body = await readJson(req);
        if (body.shortcutId && !body.prompt) body.prompt = shortcuts.get(body.shortcutId).prompt;
        return json(res, 201, runs.createRun(body, device));
      }

      const runEvents = url.pathname.match(/^\/api\/runs\/([^/]+)\/events$/);
      if (method === 'GET' && runEvents) {
        const run = runs.getRun(runEvents[1], device);
        const afterSeq = Number(url.searchParams.get('afterSeq') || 0);
        return json(res, 200, { events: eventStore.list(run.id, afterSeq) });
      }
      const runCancel = url.pathname.match(/^\/api\/runs\/([^/]+)\/cancel$/);
      if (method === 'POST' && runCancel) return json(res, 200, runs.cancelRun(runCancel[1], device));
      const runInput = url.pathname.match(/^\/api\/runs\/([^/]+)\/input$/);
      if (method === 'POST' && runInput) return json(res, 200, runs.followUp(runInput[1], await readJson(req), device));
      const approval = url.pathname.match(/^\/api\/approvals\/([^/]+)\/respond$/);
      if (method === 'POST' && approval) return json(res, 200, runs.respondApproval(approval[1], await readJson(req), device));

      throw Object.assign(new Error('not found'), { status: 404 });
    } catch (error) {
      const trace = diagnosticBundle.recordException({
        source: 'daemon',
        message: error.message,
        stack: error.stack,
        path: req.url,
        method: req.method,
        deviceId: safeDeviceId(error),
        metadata: { code: error.code || 'ERROR', status: error.status || 500 }
      });
      json(res, error.status || 500, { error: { code: error.code || 'ERROR', message: error.message, details: error.details, actionable: error.actionable, userAction: error.userAction, recoverable: error.recoverable, traceId: trace.traceId } });
    }
  });
}

function recordClientException(body, { device, diagnosticBundle, req }) {
  const trace = diagnosticBundle.recordException({
    source: 'mobile',
    severity: body.severity || 'error',
    message: body.message,
    stack: body.stack,
    path: body.path,
    method: body.method,
    deviceId: device.id,
    conversationId: body.conversationId,
    runId: body.runId,
    metadata: { ...(body.metadata || {}), remoteAddress: req.socket?.remoteAddress }
  });
  return { traceId: trace.traceId, createdAt: trace.createdAt };
}

function safeDeviceId(error) {
  return error && error.deviceId ? error.deviceId : null;
}

async function runSmoke({ config, adapterRegistry, eventStore }) {
  if (config.mode !== 'dev') {
    const error = new Error('This endpoint is only available in daemon development mode.');
    error.status = 403;
    error.code = errorCodes.DEV_API_DISABLED;
    error.recoverable = false;
    error.userAction = 'Use a development daemon build to run smoke tests.';
    throw error;
  }
  const adapter = adapterRegistry.get('synthetic-jsonl');
  const runId = 'smoke_run';
  eventStore.append(runId, eventTypes.RUN_STARTED, { tool: 'synthetic-jsonl', workspaceId: 'smoke' });
  await adapter.startRun({ prompt: 'smoke', workspacePath: process.cwd(), onEvent: (event) => eventStore.append(runId, event.type, event) });
  return { ok: true, adapter: 'synthetic-jsonl', events: eventStore.list(runId, 0).length };
}

function invokeTemplate(templateId, body, context) {
  const template = context.commandTemplates.get(templateId);
  const payload = { tool: body.tool || 'claude', workspaceId: body.workspaceId, prompt: template.prompt, templateId };
  const run = context.runs.createRun(payload, context.device);
  context.eventStore.append(run.id, eventTypes.COMMAND_TEMPLATE_STARTED, { templateId, label: template.label });
  return { templateId, run };
}

async function resolveAll(items) { return Promise.all(items.map((item) => Promise.resolve(item))); }
async function listRoots() {
  if (process.platform === 'win32') {
    const roots = [];
    for (let code = 65; code <= 90; code += 1) {
      const root = `${String.fromCharCode(code)}:\\`;
      try {
        await fs.access(root);
        roots.push({ name: root, path: root });
      } catch (_) {}
    }
    return roots;
  }
  return [{ name: '/', path: '/' }, { name: os.homedir(), path: os.homedir() }];
}
async function listDirectory(targetPath) {
  const resolved = path.resolve(targetPath || process.cwd());
  const entries = await fs.readdir(resolved, { withFileTypes: true });
  const directories = entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => ({ name: entry.name, path: path.join(resolved, entry.name) }))
    .sort((a, b) => a.name.localeCompare(b.name));
  return { path: resolved, parent: path.dirname(resolved) === resolved ? null : path.dirname(resolved), directories };
}
function json(res, status, body) { res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(body)); }
async function readJson(req) { const chunks = []; for await (const chunk of req) chunks.push(chunk); if (chunks.length === 0) return {}; return JSON.parse(Buffer.concat(chunks).toString('utf8')); }

module.exports = { createServer };
