'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const Busboy = require('busboy');
const {
  sanitizeAttachmentName,
  validateTextAttachmentBytes,
  validateImageAttachmentHeader,
  validatePdfAttachmentHeader,
  estimateAttachmentTextTokens,
  assertWithinContextBudget,
  attachmentHttpError
} = require('./attachment-validation');

const maxPayloadBytes = 64 * 1024;
const sniffBytes = 128 * 1024;
const maxTextAttachmentBytes = 256 * 1024;
const maxImageAttachmentBytes = 10 * 1024 * 1024;
const maxPdfAttachmentBytes = 20 * 1024 * 1024;
const maxFileCount = 16;
const maxTotalBytes = 20 * 1024 * 1024;
const textExtractWrapperChars = 128;

async function readMultipartConversationMessage(req, scratch) {
  const files = [];
  const fileWrites = [];
  let payload = null;
  let payloadSeen = false;
  let totalBytes = 0;
  let aborted = false;
  let parser = null;
  let nextFileIndex = 0;
  const fileAttachmentIndexes = [];

  function abort(error, { validationFailure = false } = {}) {
    aborted = true;
    if (parser) {
      req.unpipe(parser);
      if (validationFailure) {
        parser.removeAllListeners();
        if (typeof parser.destroy === 'function') parser.destroy();
      }
    }
    stopRequestAfterAbort(req, error, { validationFailure });
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
      const index = nextFileIndex;
      if (index >= maxFileCount) {
        file.resume();
        reject(abort(attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'too many attachments', { maxFileCount })));
        return;
      }
      nextFileIndex += 1;
      let match;
      try {
        match = attachmentMatchForFile(payload, index);
      } catch (error) {
        file.resume();
        reject(abort(error));
        return;
      }
      if (!match) {
        file.resume();
        reject(abort(badRequest('multipart file part has no matching attachment metadata')));
        return;
      }
      fileAttachmentIndexes[index] = match.attachmentIndex;
      const filePromise = writeAndValidateFile({ file, info, requested: match.attachment, scratch, index, addBytes(bytes) {
        totalBytes += bytes;
        if (totalBytes > maxTotalBytes) throw attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'attachment upload is too large', { maxTotalBytes });
      } }).then((committed) => {
        files[index] = committed;
      });
      fileWrites.push(filePromise);
      filePromise.catch((error) => {
        if (!aborted) reject(abort(error, { validationFailure: error.uploadValidationFailure === true }));
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
        validateDeclaredAttachmentsMatchFiles(payload, files, fileAttachmentIndexes);
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
    let name;
    let kind;
    let mimeType;
    try {
      name = sanitizeAttachmentName(requested.name || info.filename || `attachment-${index}`);
      kind = normalizeKind(requested.kind);
      mimeType = normalizeMimeType(requested.mimeType || info.mimeType);
    } catch (error) {
      file.resume();
      reject(error);
      return;
    }
    const scratchName = `file_${index}.bin`;
    const scratchPath = path.join(scratch.dir, scratchName);
    const output = fs.createWriteStream(scratchPath, { flags: 'wx' });
    const hash = crypto.createHash('sha256');
    const sniffChunks = [];
    const textChunks = [];
    let sizeBytes = 0;
    let failed = false;

    function fail(error, { validationFailure = true } = {}) {
      if (failed) return;
      failed = true;
      if (validationFailure && error && typeof error === 'object') {
        error.uploadValidationFailure = true;
      }
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
        } else if (kind === 'image' && sizeBytes > maxImageAttachmentBytes) {
          throw attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'image attachment is too large', { maxImageAttachmentBytes });
        } else if (kind === 'pdf' && sizeBytes > maxPdfAttachmentBytes) {
          throw attachmentHttpError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'PDF attachment is too large', { maxPdfAttachmentBytes });
        }
      } catch (error) {
        fail(error, { validationFailure: true });
      }
    });
    file.on('error', (error) => fail(error, { validationFailure: false }));
    output.on('error', (error) => fail(error, { validationFailure: false }));
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
          assertWithinContextBudget(estimateAttachmentTextTokens({
            text,
            wrapperChars: textExtractWrapperChars + name.length
          }));
          handling = 'text_extract';
        } else if (kind === 'image') {
          const validated = validateImageAttachmentHeader(sniffBuffer, { name, mimeType });
          validatedMimeType = validated.mimeType;
          handling = 'native';
        } else if (kind === 'pdf') {
          const validated = validatePdfAttachmentHeader(sniffBuffer, { name, mimeType });
          validatedMimeType = validated.mimeType;
          handling = 'staged_path';
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
        fail(error, { validationFailure: true });
      }
    });
    file.pipe(output);
  });
}

function attachmentMatchForFile(payload, index) {
  const attachments = declaredAttachments(payload);
  const expectedField = `files[${index}]`;
  const byField = [];
  for (let attachmentIndex = 0; attachmentIndex < attachments.length; attachmentIndex += 1) {
    if (attachments[attachmentIndex]?.field === expectedField) byField.push(attachmentIndex);
  }
  if (byField.length > 1) throw badRequest('multipart attachment metadata has duplicate file fields');
  if (byField.length === 1) {
    return {
      attachment: attachments[byField[0]],
      attachmentIndex: byField[0]
    };
  }
  const positional = attachments[index];
  if (positional && !hasExplicitAttachmentField(positional)) {
    return {
      attachment: positional,
      attachmentIndex: index
    };
  }
  return null;
}

function validateDeclaredAttachmentsMatchFiles(payload, files, fileAttachmentIndexes) {
  const attachments = declaredAttachments(payload);
  if (attachments.length !== files.length) {
    throw badRequest('multipart attachments metadata must match file parts');
  }
  const matchedAttachmentIndexes = new Set(fileAttachmentIndexes);
  if (matchedAttachmentIndexes.size !== files.length || matchedAttachmentIndexes.has(undefined)) {
    throw badRequest('multipart file parts must have unique attachment metadata');
  }
  for (let attachmentIndex = 0; attachmentIndex < attachments.length; attachmentIndex += 1) {
    const fileIndex = expectedFileIndexForAttachment(attachments[attachmentIndex], attachmentIndex);
    if (fileIndex < 0 || fileIndex >= files.length || fileAttachmentIndexes[fileIndex] !== attachmentIndex) {
      throw badRequest('multipart attachment metadata has no matching file part');
    }
  }
}

function declaredAttachments(payload) {
  if (!payload || typeof payload !== 'object') return [];
  if (!Object.prototype.hasOwnProperty.call(payload, 'attachments')) return [];
  if (!Array.isArray(payload.attachments)) throw badRequest('multipart attachments metadata must be an array');
  return payload.attachments;
}

function expectedFileIndexForAttachment(attachment, fallbackIndex) {
  if (!hasExplicitAttachmentField(attachment)) return fallbackIndex;
  const match = String(attachment.field).match(/^files\[(\d+)]$/);
  if (!match) throw badRequest('multipart attachment field is invalid');
  const index = Number(match[1]);
  if (!Number.isSafeInteger(index)) throw badRequest('multipart attachment field is invalid');
  return index;
}

function hasExplicitAttachmentField(attachment) {
  return Object.prototype.hasOwnProperty.call(attachment || {}, 'field') && attachment.field != null && attachment.field !== '';
}

function stopRequestAfterAbort(req, error, { validationFailure }) {
  // Destroying Node's HTTP IncomingMessage during route handling can reset the
  // socket before the server writes its JSON error. For validation failures we
  // still destroy non-HTTP/explicitly abortable request streams; HTTP requests
  // get the parser/file streams destroyed and the remaining body discarded.
  if (validationFailure && shouldDestroyRequestOnValidationFailure(req)) {
    req.destroy(error);
    return;
  }
  req.resume();
}

function shouldDestroyRequestOnValidationFailure(req) {
  if (!req || typeof req.destroy !== 'function') return false;
  if (req.destroyOnValidationFailure === true) return true;
  return req.constructor?.name !== 'IncomingMessage' && !req.socket;
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
