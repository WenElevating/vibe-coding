'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');

const DEFAULT_MODEL_FILE =
  'sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20-mobile.zip';

class AsrModelAsset {
  constructor({
    filePath = path.join(__dirname, '..', 'asset', DEFAULT_MODEL_FILE),
    version = path.basename(filePath, '.zip'),
    downloadPath = '/api/asr-model/download',
  } = {}) {
    this.filePath = filePath;
    this.version = version;
    this.fileName = path.basename(filePath);
    this.downloadPath = downloadPath;
    this._metadata = null;
    this._metadataStatKey = null;
  }

  async metadata() {
    const stat = await this._statReadable();
    const statKey = `${stat.size}:${stat.mtimeMs}`;
    if (this._metadata && this._metadataStatKey === statKey) {
      return this._metadata;
    }
    const sha256 = await sha256File(this.filePath);
    this._metadata = {
      version: this.version,
      fileName: this.fileName,
      sizeBytes: stat.size,
      sha256,
      downloadPath: this.downloadPath,
    };
    this._metadataStatKey = statKey;
    return this._metadata;
  }

  async streamDownload(req, res) {
    const stat = await this._statReadable();
    const size = stat.size;
    const range = parseRange(req.headers.range, size);
    if (range.unsatisfiable) {
      res.writeHead(416, {
        'accept-ranges': 'bytes',
        'content-range': `bytes */${size}`,
      });
      res.end();
      return;
    }

    const start = range.start;
    const end = range.end;
    const partial = start !== 0 || end !== size - 1;
    res.writeHead(partial ? 206 : 200, {
      'accept-ranges': 'bytes',
      'content-type': 'application/zip',
      'content-length': end - start + 1,
      ...(partial ? { 'content-range': `bytes ${start}-${end}/${size}` } : {}),
    });
    fs.createReadStream(this.filePath, { start, end }).pipe(res);
  }

  async _statReadable() {
    try {
      const stat = await fsp.stat(this.filePath);
      if (!stat.isFile()) throw new Error('configured ASR model asset is not a file');
      await fsp.access(this.filePath, fs.constants.R_OK);
      return stat;
    } catch (error) {
      const wrapped = new Error(`ASR model asset is unavailable: ${error.message}`);
      wrapped.status = 503;
      wrapped.code = 'ASR_MODEL_UNAVAILABLE';
      wrapped.recoverable = true;
      wrapped.userAction = 'Place the configured ASR model ZIP under daemon/asset and retry from the mobile app.';
      throw wrapped;
    }
  }
}

function parseRange(header, size) {
  if (!header) return { start: 0, end: size - 1 };
  const match = String(header).match(/^bytes=(\d*)-(\d*)$/);
  if (!match) return { unsatisfiable: true };
  const startText = match[1];
  const endText = match[2];
  if (!startText && !endText) return { unsatisfiable: true };

  if (!startText) {
    const suffixLength = Number(endText);
    if (!Number.isSafeInteger(suffixLength) || suffixLength <= 0) {
      return { unsatisfiable: true };
    }
    const start = Math.max(size - suffixLength, 0);
    return { start, end: size - 1 };
  }

  const start = Number(startText);
  const requestedEnd = endText ? Number(endText) : size - 1;
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(requestedEnd) ||
    start < 0 ||
    requestedEnd < start ||
    start >= size
  ) {
    return { unsatisfiable: true };
  }
  return { start, end: Math.min(requestedEnd, size - 1) };
}

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

module.exports = { AsrModelAsset, parseRange };
