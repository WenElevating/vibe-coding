'use strict';

const fs = require('node:fs');
const path = require('node:path');

function defaultCodexAppServerSchemaDir() {
  return path.join(__dirname, '..', '..', 'test', 'fixtures', 'codex-app-server', 'schema');
}

function loadCodexAppServerMethods(schemaDir = defaultCodexAppServerSchemaDir()) {
  const clientRequests = extractMethodsFromSchema(path.join(schemaDir, 'ClientRequest.json'));
  const clientNotifications = extractMethodsFromSchema(path.join(schemaDir, 'ClientNotification.json'));
  const serverRequests = extractMethodsFromSchema(path.join(schemaDir, 'ServerRequest.json'));
  const serverNotifications = extractMethodsFromSchema(path.join(schemaDir, 'ServerNotification.json'));
  return {
    clientRequests,
    clientNotifications,
    serverRequests,
    serverNotifications,
    requests: clientRequests,
    notifications: serverNotifications
  };
}

function extractMethodsFromSchema(filePath) {
  const schema = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const methods = new Set();
  for (const variant of Array.isArray(schema.oneOf) ? schema.oneOf : []) {
    const enumValues = variant?.properties?.method?.enum;
    if (!Array.isArray(enumValues)) continue;
    for (const value of enumValues) {
      if (typeof value === 'string' && value.trim()) methods.add(value);
    }
  }
  return methods;
}

module.exports = {
  defaultCodexAppServerSchemaDir,
  extractMethodsFromSchema,
  loadCodexAppServerMethods
};
