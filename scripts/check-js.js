'use strict';

const { spawnSync } = require('node:child_process');
const { readdirSync } = require('node:fs');
const { join } = require('node:path');

const files = [
  ...readdirSync('daemon/src').filter((file) => file.endsWith('.js')).map((file) => join('daemon/src', file)),
  ...readdirSync('daemon/test').filter((file) => file.endsWith('.js')).map((file) => join('daemon/test', file))
];

for (const file of files) {
  const result = spawnSync(process.execPath, ['--check', file], { stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status || 1);
}
