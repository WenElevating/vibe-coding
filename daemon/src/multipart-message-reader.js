'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const Busboy = require('busboy');
const {
  sanitizeAttachmentName,
  validateTextAttachmentBytes,
  validateImageAttachmentHeader,
  attachmentHttpError
} = require('./attachment-validation');

const maxPayloadBytes = 64 * 1024;
const sniffBytes = 128 * 1024;
const maxTextAttachmentBytes = 256 * 1024;
const maxFileCount = 16;
const maxTotalBytes = 50 * 1024 * 1024;

async function readMultipartConversationMessage(req, scratch) {
  const files = [];
  const fileWrites = [];
  let payload = null;
  let payloadSeen = false;
  let totalBytes = 0;
  let aborted = false;
  let parser = null;

  function abort(error) {
    aborted = true;
    if (parser) {
      req.unpipe(parser);
      parser.removeAllListeners();
    }
    req.resume();
    return error;
  }

  await new Promise((resolve, reject) => {
    let busboy;
    try {
      busboy = Busboy({
        headers: req.headers,
        limits: {
          fieldSize: maxPayloadBytes + 1,
          fields: 1,
          files: maxFileCount,
          parts: maxFileCount + 1
        }
      });
    } catch (error) {
      reject(badRequest(error.message));
      return;
    }
    parser = busboy;

    busboy.on('field', (name, value, info) => {
      if (aborted) return;
      if (name !== 'payload') {
        reject(abort(badRequest('multipart payload field is required')));
        return;
      }
      if (payloadSeen) {
        reject(abort(badRequest('multipart payload field must appear once')));
        return;
      }
      payloadSeen = true;
      if (info?.valueTruncated || Buffer.byteLength(value, 'utf8') > maxPayloadBytes) {
        reject(abort(badRequest('multipart payload is too large')));
        return;
      }
      try {
        payload = JSON.parse(value);
      } catch {
        reject(abort(badRequest('multipart payload must be valid JSON')));
      }
    });

    busboy.on('file', (field, file, info) => {
      if (aborted) {
        file.resume();
        return;
      }
      if (!payloadSeen || !payload) {
        file.resume();
        reject(abort(badRequest('multipart payload field must arrive before files[]')));
        return;
      }
      if (field !== 'files[]') {
        file.resume();
        reject(abort(badRequest('multipart files must use files[] field')));
        return;
      }
      const index = files.length;
      if (index >= maxFileCount) {
        file.resume();
        reject(abort(attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'too many attachments', { maxFileCount })));
        return;
      }
      const requested = attachmentForFile(payload, index);
      const filePromise = writeAndValidateFile({ file, info, requested, scratch, index, addBytes(bytes) {
        totalBytes += bytes;
        if (totalBytes > maxTotalBytes) throw attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'attachment upload is too large', { maxTotalBytes });
      } }).then((committed) => {
        files[index] = committed;
      });
      fileWrites.push(filePromise);
      filePromise.catch((error) => {
        if (!aborted) reject(abort(error));
      });
    });

    busboy.on('filesLimit', () => {
      if (!aborted) reject(abort(attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'too many attachments', { maxFileCount })));
    });
    busboy.on('fieldsLimit', () => {
      if (!aborted) reject(abort(badRequest('multipart payload field must appear once')));
    });
    busboy.on('partsLimit', () => {
      if (!aborted) reject(abort(attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'too many multipart parts', { maxFileCount })));
    });
    busboy.on('error', (error) => {
      if (!aborted) reject(abort(badRequest(error.message)));
    });
    busboy.on('close', async () => {
      if (aborted) return;
      try {
        if (!payloadSeen || !payload) throw badRequest('multipart payload field is required');
        await Promise.all(fileWrites);
        resolve();
      } catch (error) {
        reject(error);
      }
    });
    req.pipe(busboy);
  });

  return { payload, files };
}

function writeAndValidateFile({ file, info, requested, scratch, index, addBytes }) {
  return new Promise((resolve, reject) => {
    const name = sanitizeAttachmentName(requested.name || info.filename || `attachment-${index}`);
    const kind = normalizeKind(requested.kind);
    const mimeType = normalizeMimeType(requested.mimeType || info.mimeType);
    const scratchName = `file_${index}.bin`;
    const scratchPath = path.join(scratch.dir, scratchName);
    const output = fs.createWriteStream(scratchPath, { flags: 'wx' });
    const hash = crypto.createHash('sha256');
    const sniffChunks = [];
    const textChunks = [];
    let sizeBytes = 0;
    let failed = false;

    function fail(error) {
      if (failed) return;
      failed = true;
      output.destroy();
      file.destroy(error);
      reject(error);
    }

    file.on('data', (chunk) => {
      if (failed) return;
      try {
        sizeBytes += chunk.length;
        addBytes(chunk.length);
        hash.update(chunk);
        if (sniffLength(sniffChunks) < sniffBytes) {
          sniffChunks.push(chunk.subarray(0, Math.min(chunk.length, sniffBytes - sniffLength(sniffChunks))));
        }
        if (kind === 'textDocument') {
          if (sizeBytes > maxTextAttachmentBytes) {
            throw attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'text attachment is too large', { maxTextAttachmentBytes });
          }
          textChunks.push(chunk);
        }
      } catch (error) {
        fail(error);
      }
    });
    file.on('error', fail);
    output.on('error', fail);
    output.on('finish', async () => {
      if (failed) return;
      try {
        const sniffBuffer = Buffer.concat(sniffChunks);
        let validatedMimeType = mimeType;
        let text;
        let handling = 'staged_path';
        if (kind === 'textDocument') {
          const validated = await validateTextAttachmentBytes(Buffer.concat(textChunks), { name, mimeType });
          validatedMimeType = validated.mimeType;
          text = validated.text;
          handling = 'text_extract';
        } else if (kind === 'image') {
          const validated = validateImageAttachmentHeader(sniffBuffer, { name, mimeType });
          validatedMimeType = validated.mimeType;
          handling = 'native';
        } else {
          throw attachmentHttpError(415, 'UNSUPPORTED_MEDIA_TYPE', 'unsupported media type', { reason: 'PDF attachments are not supported yet' });
        }
        const contentSha256 = hash.digest('hex');
        resolve({
          name,
          kind,
          mimeType: validatedMimeType,
          sizeBytes,
          scratchPath,
          contentSha256,
          contentSha256Prefix: contentSha256.slice(0, 32),
          handling,
          ...(text == null ? {} : { text })
        });
      } catch (error) {
        fail(error);
      }
    });
    file.pipe(output);
  });
}

function attachmentForFile(payload, index) {
  const attachments = Array.isArray(payload?.attachments) ? payload.attachments : [];
  const byField = attachments.find((attachment) => attachment?.field === `files[${index}]`);
  return byField || attachments[index] || {};
}

function normalizeKind(kind) {
  if (kind === 'textDocument' || kind === 'image' || kind === 'pdf') return kind;
  throw attachmentHttpError(415, 'UNSUPPORTED_MEDIA_TYPE', 'unsupported media type', { reason: 'attachment kind is not supported', kind });
}

function normalizeMimeType(value) {
  return String(value || 'application/octet-stream').split(';')[0].trim().toLowerCase();
}

function sniffLength(chunks) {
  return chunks.reduce((sum, chunk) => sum + chunk.length, 0);
}

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = 'BAD_REQUEST';
  return error;
}

module.exports = {
  readMultipartConversationMessage
};
