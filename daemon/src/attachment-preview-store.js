'use strict';

const fs = require('node:fs/promises');
const { createReadStream } = require('node:fs');
const path = require('node:path');
const { isUnderRoot } = require('./attachment-scratch-store');

const metadataSuffix = '.json';

class AttachmentPreviewStore {
  constructor({ root }) {
    this.root = path.resolve(root);
  }

  async saveImagePreview({ conversationId, attachment, sourcePath }) {
    if (!attachment || attachment.kind !== 'image' || !sourcePath) return null;
    const conversationSegment = safeSegment(conversationId, 'conversation id');
    const attachmentSegment = safeSegment(attachment.id, 'attachment id');
    const conversationDir = path.resolve(path.join(this.root, conversationSegment));
    if (!isUnderRoot(conversationDir, this.root)) throw new Error('attachment preview path escaped root');
    await fs.mkdir(conversationDir, { recursive: true });

    const fileName = `${attachmentSegment}${imageExtension(attachment.mimeType)}`;
    const target = path.resolve(path.join(conversationDir, fileName));
    if (!isUnderRoot(target, conversationDir)) throw new Error('attachment preview path escaped conversation directory');
    await fs.copyFile(sourcePath, target);

    await fs.writeFile(
      path.join(conversationDir, `${attachmentSegment}${metadataSuffix}`),
      `${JSON.stringify({
        conversationId,
        attachmentId: attachment.id,
        fileName,
        name: attachment.name,
        mimeType: attachment.mimeType,
        sizeBytes: attachment.sizeBytes
      }, null, 2)}\n`,
      'utf8'
    );

    return `/api/conversations/${encodeURIComponent(conversationId)}/attachments/${encodeURIComponent(attachment.id)}/preview`;
  }

  async getImagePreview({ conversationId, attachmentId }) {
    const conversationSegment = safeSegment(conversationId, 'conversation id');
    const attachmentSegment = safeSegment(attachmentId, 'attachment id');
    const conversationDir = path.resolve(path.join(this.root, conversationSegment));
    if (!isUnderRoot(conversationDir, this.root)) return null;
    const metadataPath = path.resolve(path.join(conversationDir, `${attachmentSegment}${metadataSuffix}`));
    if (!isUnderRoot(metadataPath, conversationDir)) return null;
    const metadata = await readJson(metadataPath);
    if (metadata?.conversationId !== conversationId || metadata?.attachmentId !== attachmentId) return null;

    const fileName = safeStoredFileName(metadata.fileName);
    const filePath = path.resolve(path.join(conversationDir, fileName));
    if (!isUnderRoot(filePath, conversationDir)) return null;
    let stat;
    try {
      stat = await fs.stat(filePath);
    } catch {
      return null;
    }
    if (!stat.isFile()) return null;

    return {
      name: typeof metadata.name === 'string' ? metadata.name : attachmentId,
      mimeType: typeof metadata.mimeType === 'string' ? metadata.mimeType : 'application/octet-stream',
      sizeBytes: stat.size,
      stream: () => createReadStream(filePath)
    };
  }
}

async function readJson(filePath) {
  try {
    return JSON.parse(await fs.readFile(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function safeSegment(value, label) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error(`${label} is invalid`);
  }
  return value;
}

function safeStoredFileName(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+\.(?:png|jpg|webp|img)$/.test(value)) {
    throw new Error('attachment preview file name is invalid');
  }
  return value;
}

function imageExtension(mimeType) {
  switch (mimeType) {
    case 'image/png':
      return '.png';
    case 'image/jpeg':
      return '.jpg';
    case 'image/webp':
      return '.webp';
    default:
      return '.img';
  }
}

module.exports = { AttachmentPreviewStore };
