'use strict';

const fs = require('node:fs');
const path = require('node:path');

const apkContentType = 'application/vnd.android.package-archive';

class AppUpdateService {
  constructor({
    artifactDir = path.join(process.cwd(), 'daemon', 'update-artifacts', 'android')
  } = {}) {
    this.artifactDir = artifactDir;
    this.available = false;
    this.manifest = unavailableManifest();
    this.apkPath = null;
    this.load();
  }

  load() {
    const manifestPath = path.join(this.artifactDir, 'latest.json');
    if (!fs.existsSync(manifestPath)) return;

    let manifest;
    try {
      manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
      validateManifest(manifest);
    } catch {
      return;
    }

    const fileName = resolveManifestFileName(manifest);
    if (!fileName) return;
    const resolved = path.resolve(this.artifactDir, fileName);
    if (!isWithinDirectory(this.artifactDir, resolved)) return;
    if (!fs.existsSync(resolved)) return;

    const stats = fs.statSync(resolved);
    if (!stats.isFile()) return;
    if (stats.size !== manifest.sizeBytes) return;

    const etag = manifest.etag || `"android-apk-${manifest.versionCode}-${manifest.sha256.slice(0, 12)}"`;
    this.manifest = {
      ...manifest,
      etag,
      fileName
    };
    this.apkPath = resolved;
    this.available = true;
  }

  sendLatest(req, res) {
    const etag = this.manifest.etag || '"android-update-none"';
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, { etag });
      res.end();
      return;
    }
    json(res, 200, this.manifest, { etag });
  }

  sendApk(req, res, requestedVersionCode) {
    if (!this.available || Number(requestedVersionCode) !== this.manifest.versionCode) {
      notFound(res);
      return;
    }

    const total = this.manifest.sizeBytes;
    const commonHeaders = {
      'content-type': apkContentType,
      'accept-ranges': 'bytes',
      etag: this.manifest.etag,
      'cache-control': 'private, no-cache'
    };

    if (req.method === 'HEAD') {
      res.writeHead(200, { ...commonHeaders, 'content-length': total });
      res.end();
      return;
    }

    const ifRange = req.headers['if-range'];
    const range = ifRange && ifRange !== this.manifest.etag ? null : parseRange(req.headers.range, total);
    if (range && range.unsatisfiable) {
      res.writeHead(416, { ...commonHeaders, 'content-range': `bytes */${total}` });
      res.end();
      return;
    }

    if (!range) {
      res.writeHead(200, { ...commonHeaders, 'content-length': total });
      fs.createReadStream(this.apkPath).pipe(res);
      return;
    }

    res.writeHead(206, {
      ...commonHeaders,
      'content-length': range.end - range.start + 1,
      'content-range': `bytes ${range.start}-${range.end}/${total}`
    });
    fs.createReadStream(this.apkPath, { start: range.start, end: range.end }).pipe(res);
  }
}

function unavailableManifest() {
  return {
    schemaVersion: 1,
    platform: 'android',
    available: false
  };
}

function validateManifest(manifest) {
  if (!manifest || typeof manifest !== 'object') throw new Error('android update manifest must be an object');
  if (manifest.schemaVersion !== 1) throw new Error('android update manifest schemaVersion must be 1');
  if (manifest.platform !== 'android') throw new Error('android update manifest platform must be android');
  if (typeof manifest.packageName !== 'string' || manifest.packageName.trim() === '') throw new Error('android update manifest packageName is required');
  if (typeof manifest.versionName !== 'string' || manifest.versionName.trim() === '') throw new Error('android update manifest versionName is required');
  if (!Number.isSafeInteger(manifest.versionCode) || manifest.versionCode <= 0) throw new Error('android update manifest versionCode is invalid');
  if (!Number.isSafeInteger(manifest.minSupportedVersionCode) || manifest.minSupportedVersionCode < 0) throw new Error('android update manifest minSupportedVersionCode is invalid');
  if (typeof manifest.mandatory !== 'boolean') throw new Error('android update manifest mandatory is required');
  if (typeof manifest.apkUrl !== 'string' || manifest.apkUrl.trim() === '') throw new Error('android update manifest apkUrl is required');
  if (typeof manifest.sha256 !== 'string' || !/^[a-f0-9]{64}$/i.test(manifest.sha256)) throw new Error('android update manifest sha256 is invalid');
  if (!Number.isSafeInteger(manifest.sizeBytes) || manifest.sizeBytes <= 0) throw new Error('android update manifest sizeBytes is invalid');
  if (manifest.etag != null && (typeof manifest.etag !== 'string' || manifest.etag.trim() === '')) throw new Error('android update manifest etag is invalid');
  if (manifest.fileName != null && (typeof manifest.fileName !== 'string' || manifest.fileName.trim() === '')) throw new Error('android update manifest fileName is invalid');
}

function resolveManifestFileName(manifest) {
  if (manifest.fileName) return manifest.fileName;
  try {
    const parsed = new URL(manifest.apkUrl, 'http://daemon.local');
    return path.basename(parsed.pathname);
  } catch {
    return path.basename(manifest.apkUrl);
  }
}

function isWithinDirectory(rootDir, targetPath) {
  const root = path.resolve(rootDir);
  const relative = path.relative(root, path.resolve(targetPath));
  return relative !== '' && !relative.startsWith('..') && !path.isAbsolute(relative);
}

function parseRange(header, total) {
  if (!header) return null;
  const text = String(header).trim();
  if (text.includes(',')) return { unsatisfiable: true };
  const match = /^bytes=(\d*)-(\d*)$/.exec(text);
  if (!match) return { unsatisfiable: true };

  const startText = match[1];
  const endText = match[2];
  if (!startText && !endText) return { unsatisfiable: true };

  if (!startText) {
    const suffixLength = Number(endText);
    if (!Number.isSafeInteger(suffixLength) || suffixLength <= 0) return { unsatisfiable: true };
    return {
      start: Math.max(total - suffixLength, 0),
      end: total - 1
    };
  }

  const start = Number(startText);
  const requestedEnd = endText ? Number(endText) : total - 1;
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(requestedEnd) ||
    start < 0 ||
    requestedEnd < start ||
    start >= total
  ) {
    return { unsatisfiable: true };
  }

  return {
    start,
    end: Math.min(requestedEnd, total - 1)
  };
}

function notFound(res) {
  json(res, 404, {
    error: {
      code: 'NOT_FOUND',
      message: 'Android update artifact not found.'
    }
  });
}

function json(res, status, body, headers = {}) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', ...headers });
  res.end(JSON.stringify(body));
}

module.exports = { AppUpdateService, parseRange };
