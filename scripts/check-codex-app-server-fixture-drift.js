'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const {
  defaultCodexAppServerSchemaDir,
  loadCodexAppServerMethods
} = require('../daemon/src/codex-app-server/methods');

function main() {
  const codex = findCodex();
  if (!codex) return skip('codex executable is not available on PATH');

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-app-server-schema-'));
  const jsonOut = path.join(tempRoot, 'json');
  const tsOut = path.join(tempRoot, 'ts');
  fs.mkdirSync(jsonOut, { recursive: true });
  fs.mkdirSync(tsOut, { recursive: true });

  try {
    const jsonResult = run(codex, ['app-server', 'generate-json-schema', '--experimental', '--out', jsonOut]);
    if (jsonResult.status !== 0) {
      return skip(`codex app-server generate-json-schema is unavailable: ${formatProcessFailure(jsonResult)}`);
    }
    const tsResult = run(codex, ['app-server', 'generate-ts', '--experimental', '--out', tsOut]);
    if (tsResult.status !== 0) {
      return skip(`codex app-server generate-ts is unavailable: ${formatProcessFailure(tsResult)}`);
    }

    const generatedSchemaDir = findGeneratedSchemaDir(jsonOut);
    if (!generatedSchemaDir) {
      return skip('codex app-server generate-json-schema did not emit ClientRequest.json/ServerNotification.json fixtures');
    }

    const fixtureMethods = loadCodexAppServerMethods(defaultCodexAppServerSchemaDir());
    const generatedMethods = loadCodexAppServerMethods(generatedSchemaDir);
    const differences = diffMethodSets(fixtureMethods, generatedMethods);
    if (differences.length > 0) {
      console.error('Codex app-server fixture drift detected.');
      for (const difference of differences) console.error(`- ${difference}`);
      process.exitCode = 1;
      return;
    }

    const generatedTsFiles = listFiles(tsOut).filter((file) => file.endsWith('.ts'));
    if (generatedTsFiles.length === 0) {
      return skip('codex app-server generate-ts completed but emitted no TypeScript files');
    }

    console.log('Codex app-server fixture drift check passed: generated method sets match committed fixtures.');
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

function findCodex() {
  const command = process.platform === 'win32' ? 'where.exe' : 'which';
  const args = ['codex'];
  const result = run(command, args);
  if (result.status !== 0) return null;
  return 'codex';
}

function run(command, args) {
  return spawnSync(command, args, {
    encoding: 'utf8',
    windowsHide: true
  });
}

function findGeneratedSchemaDir(root) {
  for (const dir of listDirs(root)) {
    if (
      fs.existsSync(path.join(dir, 'ClientRequest.json')) &&
      fs.existsSync(path.join(dir, 'ClientNotification.json')) &&
      fs.existsSync(path.join(dir, 'ServerRequest.json')) &&
      fs.existsSync(path.join(dir, 'ServerNotification.json'))
    ) {
      return dir;
    }
  }
  return null;
}

function listDirs(root) {
  const dirs = [root];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    dirs.push(...listDirs(path.join(root, entry.name)));
  }
  return dirs;
}

function listFiles(root) {
  const files = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...listFiles(fullPath));
    } else {
      files.push(fullPath);
    }
  }
  return files;
}

function diffMethodSets(fixtureMethods, generatedMethods) {
  const groups = [
    ['clientRequests', fixtureMethods.clientRequests, generatedMethods.clientRequests],
    ['clientNotifications', fixtureMethods.clientNotifications, generatedMethods.clientNotifications],
    ['serverRequests', fixtureMethods.serverRequests, generatedMethods.serverRequests],
    ['serverNotifications', fixtureMethods.serverNotifications, generatedMethods.serverNotifications]
  ];
  const differences = [];
  for (const [name, fixture, generated] of groups) {
    const missing = [...fixture].filter((method) => !generated.has(method)).sort();
    const added = [...generated].filter((method) => !fixture.has(method)).sort();
    if (missing.length > 0) differences.push(`${name} missing from generated schema: ${missing.join(', ')}`);
    if (added.length > 0) differences.push(`${name} added by generated schema: ${added.join(', ')}`);
  }
  return differences;
}

function formatProcessFailure(result) {
  if (result.error) return result.error.message;
  const stderr = String(result.stderr || '').trim();
  const stdout = String(result.stdout || '').trim();
  const message = stderr || stdout || `exit status ${result.status}`;
  return message.split(/\r?\n/)[0];
}

function skip(message) {
  console.log(`SKIP Codex app-server fixture drift check: ${message}`);
  process.exitCode = 0;
}

main();
