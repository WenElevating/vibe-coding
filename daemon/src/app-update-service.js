'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const apkContentType = 'application/vnd.android.package-archive';

class AppUpdateService {
  constructor({
    artifactDir = path.join(process.cwd(), 'daemon', 'update-artifacts', 'android')
  } = {}) {
    this.artifactDir = artifactDir;
    this.available = false;
    this.manifest = unavailableManifest();
    this.apkPath = null;
    this.apkIdentity = null;
    this.load();
  }

  load() {
    const manifestPath = path.join(this.artifactDir, 'latest.json');
    if (!fs.existsSync(manifestPath)) {
      this._markUnavailable();
      return;
    }

    let manifest;
    try {
      manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
      validateManifest(manifest);
    } catch {
      this._markUnavailable();
      return;
    }

    const fileName = resolveManifestFileName(manifest);
    if (!fileName) {
      this._markUnavailable();
      return;
    }

    const resolved = path.resolve(this.artifactDir, fileName);
    let realArtifactDir;
    let realApkPath;
    let stats;
    try {
      realArtifactDir = fs.realpathSync.native(this.artifactDir);
      realApkPath = fs.realpathSync.native(resolved);
      if (!isWithinDirectory(realArtifactDir, realApkPath)) {
        this._markUnavailable();
        return;
      }
      stats = fs.statSync(realApkPath);
    } catch {
      this._markUnavailable();
      return;
    }
    if (!stats.isFile()) {
      this._markUnavailable();
      return;
    }
    if (stats.size !== manifest.sizeBytes) {
      this._markUnavailable();
      return;
    }
    const identity = apkIdentityFor(stats, realApkPath, manifest.sha256);
    if (!apkIdentityMatches(this.apkIdentity, stats, realApkPath, manifest.sha256)) {
      if (!this._verifyDigest(realApkPath, stats, manifest.sha256)) {
        this._markUnavailable();
        return;
      }
    }

    const etag = manifest.etag || `"android-apk-${manifest.versionCode}-${manifest.sha256.slice(0, 12)}"`;
    this.manifest = {
      ...manifest,
      available: true,
      etag,
      fileName
    };
    this.apkPath = realApkPath;
    this.apkIdentity = identity;
    this.available = true;
  }

  _markUnavailable() {
    this.available = false;
    this.manifest = unavailableManifest();
    this.apkPath = null;
    this.apkIdentity = null;
  }

  sendLatest(req, res) {
    this.load();
    if (!this.available) {
      json(res, 200, this.manifest, { 'cache-control': 'no-store' });
      return;
    }
    const etag = this.manifest.etag;
    if (ifNoneMatchIncludes(req.headers['if-none-match'], etag)) {
      res.writeHead(304, { etag });
      res.end();
      return;
    }
    json(res, 200, this.manifest, { etag });
  }

  sendApk(req, res, requestedVersionCode, device) {
    this.load();
    if (!device || !device.id) {
      json(res, 403, {
        error: {
          code: 'APP_UPDATE_DEVICE_AUTH_REQUIRED',
          message: 'Android update downloads require an authenticated paired device.'
        }
      });
      return;
    }

    if (!this.available || Number(requestedVersionCode) !== this.manifest.versionCode) {
      notFound(res);
      return;
    }

    const total = this.manifest.sizeBytes;
    const openedApk = this.openVerifiedApk();
    if (!openedApk) {
      notFound(res);
      return;
    }
    const commonHeaders = {
      'content-type': apkContentType,
      'accept-ranges': 'bytes',
      etag: this.manifest.etag,
      'cache-control': 'private, no-cache'
    };

    if (req.method === 'HEAD') {
      res.writeHead(200, { ...commonHeaders, 'content-length': total });
      res.end();
      fs.closeSync(openedApk.fd);
      return;
    }

    const ifRange = req.headers['if-range'];
    const range = ifRange && ifRange !== this.manifest.etag ? null : parseRange(req.headers.range, total);
    if (range && range.unsatisfiable) {
      res.writeHead(416, { ...commonHeaders, 'content-range': `bytes */${total}` });
      res.end();
      fs.closeSync(openedApk.fd);
      return;
    }

    if (!range) {
      res.writeHead(200, { ...commonHeaders, 'content-length': total });
      this.streamApk(res, openedApk.fd);
      return;
    }

    res.writeHead(206, {
      ...commonHeaders,
      'content-length': range.end - range.start + 1,
      'content-range': `bytes ${range.start}-${range.end}/${total}`
    });
    this.streamApk(res, openedApk.fd, { start: range.start, end: range.end });
  }

  streamApk(res, fd, options = {}) {
    const stream = fs.createReadStream(null, { ...options, fd, autoClose: true });
    stream.on('error', (error) => {
      res.destroy(error);
    });
    stream.pipe(res);
  }

  openVerifiedApk() {
    const identity = this.apkIdentity;
    if (!this.available || !this.apkPath || !identity) return null;
    let fd;
    try {
      fd = fs.openSync(this.apkPath, 'r');
      const realArtifactDir = fs.realpathSync.native(this.artifactDir);
      const realApkPath = fs.realpathSync.native(this.apkPath);
      if (!isWithinDirectory(realArtifactDir, realApkPath)) {
        fs.closeSync(fd);
        return null;
      }
      const stats = fs.fstatSync(fd);
      const pathStats = fs.statSync(realApkPath);
      if (pathStats.dev !== stats.dev || pathStats.ino !== stats.ino) {
        fs.closeSync(fd);
        return null;
      }
      if (!stats.isFile() || !apkIdentityMatches(identity, stats, realApkPath, this.manifest.sha256)) {
        fs.closeSync(fd);
        return null;
      }
      return { fd, stats };
    } catch {
      if (fd != null) {
        try {
          fs.closeSync(fd);
        } catch {}
      }
      return null;
    }
  }

  _verifyDigest(apkPath, stats, expectedSha256) {
    const actualSha256 = crypto.createHash('sha256').update(fs.readFileSync(apkPath)).digest('hex');
    const matches = actualSha256.toLowerCase() === expectedSha256.toLowerCase();
    return matches;
  }
}

function apkIdentityFor(stats, realApkPath, sha256) {
  return {
    realApkPath,
    dev: stats.dev,
    ino: stats.ino,
    size: stats.size,
    mtimeMs: stats.mtimeMs,
    sha256: sha256.toLowerCase()
  };
}

function apkIdentityMatches(identity, stats, realApkPath, sha256) {
  return identity != null &&
    identity.realApkPath === realApkPath &&
    identity.dev === stats.dev &&
    identity.ino === stats.ino &&
    identity.size === stats.size &&
    identity.mtimeMs === stats.mtimeMs &&
    identity.sha256 === sha256.toLowerCase();
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
  if (manifest.apkUrl !== expectedApkUrl(manifest.versionCode)) throw new Error('android update manifest apkUrl is invalid');
  if (typeof manifest.sha256 !== 'string' || !/^[a-f0-9]{64}$/i.test(manifest.sha256)) throw new Error('android update manifest sha256 is invalid');
  if (!Number.isSafeInteger(manifest.sizeBytes) || manifest.sizeBytes <= 0) throw new Error('android update manifest sizeBytes is invalid');
  if (manifest.etag != null && (typeof manifest.etag !== 'string' || manifest.etag.trim() === '')) throw new Error('android update manifest etag is invalid');
  if (manifest.fileName != null && (typeof manifest.fileName !== 'string' || manifest.fileName.trim() === '')) throw new Error('android update manifest fileName is invalid');
}

function expectedApkUrl(versionCode) {
  return `/api/app-updates/android/apk/${versionCode}`;
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

function ifNoneMatchIncludes(header, etag) {
  if (!header) return false;
  return String(header)
    .split(',')
    .map((item) => item.trim())
    .some((item) => item === '*' || item === etag);
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
