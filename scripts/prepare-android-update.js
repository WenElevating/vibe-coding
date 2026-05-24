#!/usr/bin/env node
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const apkPath = required(args, 'apk');
  const outDir = required(args, 'out');
  const versionName = required(args, 'version-name');
  const versionCode = parsePositiveInteger(required(args, 'version-code'), '--version-code');
  const packageName = required(args, 'package');
  const releaseNotes = args['release-notes'] || '';
  const minSupportedVersionCode = parsePositiveInteger(args['min-supported-version-code'] || '1', '--min-supported-version-code');
  const mandatory = parseBoolean(args.mandatory || 'false', '--mandatory');

  if (!fs.existsSync(apkPath)) throw new Error(`APK not found: ${apkPath}`);
  const apkStats = fs.statSync(apkPath);
  if (!apkStats.isFile()) throw new Error(`APK path is not a file: ${apkPath}`);

  fs.mkdirSync(outDir, { recursive: true });
  const bytes = fs.readFileSync(apkPath);
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const fileName = sanitizeFileName(`${packageName}-${versionName}+${versionCode}-${sha256.slice(0, 12)}.apk`);
  const apkFinal = path.join(outDir, fileName);
  const shaFinal = path.join(outDir, `${fileName}.sha256`);
  const manifestFinal = path.join(outDir, 'latest.json');
  const tempSuffix = `.tmp-${process.pid}-${Date.now()}`;
  const apkTemp = path.join(outDir, `${fileName}${tempSuffix}`);
  const shaTemp = path.join(outDir, `${fileName}.sha256${tempSuffix}`);
  const manifestTemp = path.join(outDir, `latest.json${tempSuffix}`);

  fs.writeFileSync(apkTemp, bytes);
  fs.writeFileSync(shaTemp, `${sha256}  ${fileName}\n`, 'utf8');

  const manifest = {
    schemaVersion: 1,
    platform: 'android',
    packageName,
    versionName,
    versionCode,
    minSupportedVersionCode,
    mandatory,
    apkUrl: `/api/app-updates/android/apk/${versionCode}`,
    sha256,
    sizeBytes: bytes.length,
    etag: `"android-apk-${versionCode}-${sha256.slice(0, 12)}"`,
    releaseNotes,
    publishedAt: new Date().toISOString(),
    fileName
  };

  fs.writeFileSync(manifestTemp, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  fs.renameSync(apkTemp, apkFinal);
  fs.renameSync(shaTemp, shaFinal);
  fs.renameSync(manifestTemp, manifestFinal);
  console.log(`Wrote ${manifestFinal}`);
}

function parseArgs(items) {
  const parsed = {};
  for (let i = 0; i < items.length; i += 1) {
    const item = items[i];
    if (!item.startsWith('--')) throw new Error(`Unexpected argument: ${item}`);
    const key = item.slice(2);
    const next = items[i + 1];
    if (next && !next.startsWith('--')) {
      parsed[key] = next;
      i += 1;
    } else {
      parsed[key] = 'true';
    }
  }
  return parsed;
}

function required(args, key) {
  const value = args[key];
  if (!value) throw new Error(`Missing --${key}`);
  return value;
}

function parsePositiveInteger(value, flagName) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${flagName} must be a positive integer`);
  }
  return parsed;
}

function parseBoolean(value, flagName) {
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw new Error(`${flagName} must be true or false`);
}

function sanitizeFileName(value) {
  return value.replace(/[^A-Za-z0-9._+-]/g, '_');
}
