'use strict';

const { summarizeCodexAppServerCapabilityMatrix } = require('./capability-matrix');
const { buildCodexAppServerRouteCapabilities } = require('./capability-routes');

async function tryHandleCodexAppServerRoute({ method, url, json, readJson, context }) {
  void readJson;
  void context;
  if (url.pathname !== '/api/codex-app-server' && !url.pathname.startsWith('/api/codex-app-server/')) return false;

  if (method === 'GET' && url.pathname === '/api/codex-app-server/capabilities') {
    json(200, {
      capabilityMatrix: summarizeCodexAppServerCapabilityMatrix(),
      routes: buildCodexAppServerRouteCapabilities()
    });
    return true;
  }

  throw Object.assign(new Error('Codex app-server route not found'), {
    status: 404,
    code: 'CODEX_APP_SERVER_ROUTE_NOT_FOUND'
  });
}

module.exports = {
  tryHandleCodexAppServerRoute
};
