'use strict';

const { TextDecoder } = require('node:util');

const unsupportedMediaTypeCode = 'UNSUPPORTED_MEDIA_TYPE';
const unsupportedMediaTypeMessage = 'unsupported media type';
const windowsReservedBaseNames = new Set([
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
  'conin$',
  'conout$'
]);
const allowedTextMimeTypes = new Set([
  'text/plain',
  'text/markdown',
  'application/json',
  'text/csv'
]);

function sanitizeAttachmentName(name) {
  if (typeof name !== 'string') {
    throwUnsupportedMediaType({ reason: 'name must be a string' });
  }
  const normalized = name.trim().normalize('NFC');
  if (!normalized) {
    throwUnsupportedMediaType({ reason: 'name is empty' });
  }
  if (Buffer.byteLength(normalized, 'utf8') > 255) {
    throwUnsupportedMediaType({ reason: 'name is too long' });
  }
  if (/[\\/]/.test(normalized)) {
    throwUnsupportedMediaType({ reason: 'name contains a path separator' });
  }
  if (/[<>:"|?*]/.test(normalized)) {
    throwUnsupportedMediaType({ reason: 'name contains a Windows-invalid character' });
  }
  if (/[\u0000-\u001f\u007f]/.test(normalized)) {
    throwUnsupportedMediaType({ reason: 'name contains a control character' });
  }
  if (/[\u202a-\u202e\u2066-\u2069]/iu.test(normalized)) {
    throwUnsupportedMediaType({ reason: 'name contains bidi controls' });
  }
  if (/[ .]$/.test(normalized)) {
    throwUnsupportedMediaType({ reason: 'name has a trailing space or dot' });
  }
  const baseName = normalized.split('.')[0].toLowerCase();
  if (windowsReservedBaseNames.has(baseName)) {
    throwUnsupportedMediaType({ reason: 'name uses a reserved Windows device name' });
  }
  return normalized;
}

function sniffAttachmentBytes(bytes) {
  const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
  if (hasPrefix(buffer, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return { mimeType: 'image/png', knownType: 'png' };
  }
  if (hasPrefix(buffer, [0xff, 0xd8, 0xff])) {
    return { mimeType: 'image/jpeg', knownType: 'jpeg' };
  }
  if (buffer.length >= 12 && buffer.subarray(0, 4).toString('ascii') === 'RIFF') {
    if (buffer.subarray(8, 12).toString('ascii') === 'WEBP') {
      return { mimeType: 'image/webp', knownType: 'webp' };
    }
    return { knownType: 'riff-other' };
  }
  if (hasPrefix(buffer, [0x25, 0x50, 0x44, 0x46, 0x2d])) {
    return { mimeType: 'application/pdf', knownType: 'pdf' };
  }
  if (hasPrefix(buffer, [0x50, 0x4b, 0x03, 0x04])) {
    return { mimeType: 'application/zip', knownType: 'zip-office' };
  }
  return { knownType: 'unknown' };
}

async function validateTextAttachmentBytes(bytes, metadata = {}) {
  const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
  sanitizeAttachmentName(metadata.name || 'attachment.txt');
  const mimeType = normalizeTextMimeType(metadata.mimeType);
  if (buffer.length === 0) {
    throwUnsupportedMediaType({ reason: 'text attachment is empty' });
  }
  if (
    hasPrefix(buffer, [0xff, 0xfe]) ||
    hasPrefix(buffer, [0xfe, 0xff]) ||
    hasPrefix(buffer, [0xff, 0xfe, 0x00, 0x00]) ||
    hasPrefix(buffer, [0x00, 0x00, 0xfe, 0xff])
  ) {
    throwUnsupportedMediaType({ reason: 'UTF-16 text is not supported' });
  }
  if (buffer.includes(0x00)) {
    throwUnsupportedMediaType({ reason: 'text attachment contains NUL bytes' });
  }
  if (binaryControlRatio(buffer) > 0.10) {
    throwUnsupportedMediaType({ reason: 'text attachment looks binary' });
  }

  const withoutBom = hasPrefix(buffer, [0xef, 0xbb, 0xbf]) ? buffer.subarray(3) : buffer;
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(withoutBom);
  } catch {
    throwUnsupportedMediaType({ reason: 'text attachment is not valid UTF-8' });
  }
  return {
    text,
    mimeType
  };
}

function validateImageAttachmentHeader(bytes, metadata = {}) {
  sanitizeAttachmentName(metadata.name || 'attachment');
  const sniffed = sniffAttachmentBytes(bytes);
  if (!['image/png', 'image/jpeg', 'image/webp'].includes(sniffed.mimeType)) {
    throwUnsupportedMediaType({ reason: 'image attachment header is not supported', sniffed });
  }
  return {
    mimeType: sniffed.mimeType,
    knownType: sniffed.knownType
  };
}

function estimateAttachmentTextTokens({ text, asciiChars, wrapperChars = 0, nonAsciiChars } = {}) {
  let asciiCount = asciiChars;
  let nonAsciiCount = nonAsciiChars;
  if (typeof text === 'string') {
    asciiCount = 0;
    nonAsciiCount = 0;
    for (const char of Array.from(text)) {
      if (/^[\u0000-\u007f]$/u.test(char)) {
        asciiCount += 1;
      } else {
        nonAsciiCount += 1;
      }
    }
  }
  return Math.ceil(((asciiCount || 0) + wrapperChars) / 3.0 + (nonAsciiCount || 0) / 1.0);
}

function assertWithinContextBudget(estimatedTokens, contextWindow) {
  const windowSize = Number.isFinite(contextWindow) && contextWindow > 0 ? contextWindow : 8192;
  const reserve = Math.max(2048, Math.ceil(windowSize * 0.20));
  const available = Math.max(0, windowSize - reserve);
  if (estimatedTokens > available) {
    throw attachmentHttpError(413, 'ATTACHMENT_CONTEXT_BUDGET_EXCEEDED', 'attachment context budget exceeded', {
      estimatedTokens,
      contextWindow: windowSize,
      reserve,
      available
    });
  }
  return { estimatedTokens, contextWindow: windowSize, reserve, available };
}

function attachmentHttpError(status, code, message, details) {
  const error = new Error(message);
  error.status = status;
  error.code = code;
  error.details = details;
  return error;
}

function throwUnsupportedMediaType(details) {
  throw attachmentHttpError(415, unsupportedMediaTypeCode, unsupportedMediaTypeMessage, details);
}

function hasPrefix(buffer, bytes) {
  if (buffer.length < bytes.length) return false;
  for (let index = 0; index < bytes.length; index += 1) {
    if (buffer[index] !== bytes[index]) return false;
  }
  return true;
}

function binaryControlRatio(buffer) {
  if (buffer.length === 0) return 0;
  let controls = 0;
  for (const byte of buffer) {
    if (byte < 0x20 && byte !== 0x09 && byte !== 0x0a && byte !== 0x0d) {
      controls += 1;
    }
  }
  return controls / buffer.length;
}

function normalizeTextMimeType(mimeType) {
  if (mimeType == null || mimeType === '') return 'text/plain';
  if (typeof mimeType !== 'string') {
    throwUnsupportedMediaType({ reason: 'text MIME type must be a string' });
  }
  const normalized = mimeType.split(';')[0].trim().toLowerCase();
  if (!allowedTextMimeTypes.has(normalized)) {
    throwUnsupportedMediaType({ reason: 'text MIME type is not supported', mimeType });
  }
  return normalized;
}

module.exports = {
  sanitizeAttachmentName,
  sniffAttachmentBytes,
  validateTextAttachmentBytes,
  validateImageAttachmentHeader,
  estimateAttachmentTextTokens,
  assertWithinContextBudget,
  attachmentHttpError
};
