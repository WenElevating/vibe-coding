'use strict';

const attachmentKinds = Object.freeze({
  IMAGE: 'image',
  TEXT_DOCUMENT: 'textDocument',
  PDF: 'pdf'
});

const attachmentHandling = Object.freeze({
  NATIVE: 'native',
  TEXT_EXTRACT: 'text_extract',
  STAGED_PATH: 'staged_path',
  UNSUPPORTED: 'unsupported'
});

const defaultAttachmentCapabilities = Object.freeze({
  image: attachmentHandling.UNSUPPORTED,
  pdf: attachmentHandling.UNSUPPORTED,
  textDocument: attachmentHandling.TEXT_EXTRACT
});

function normalizeAttachmentCapabilities(value) {
  const input = value && typeof value === 'object' ? value : {};
  return {
    image: normalizeHandling(input.image, defaultAttachmentCapabilities.image),
    pdf: normalizeHandling(input.pdf, defaultAttachmentCapabilities.pdf),
    textDocument: normalizeHandling(input.textDocument, defaultAttachmentCapabilities.textDocument)
  };
}

function normalizeHandling(value, fallback) {
  return Object.values(attachmentHandling).includes(value) ? value : fallback;
}

function normalizeInputModalities(value) {
  if (!Array.isArray(value)) return ['text'];
  const result = Array.from(new Set(value.map((item) => String(item).trim()).filter(Boolean)));
  result.sort((a, b) => a.localeCompare(b));
  return result.length === 0 ? ['text'] : result;
}

function applyModelAttachmentCapabilities(model, adapterAttachments) {
  const rawInputModalities = explicitInputModalities(model);
  const attachments = mergeAttachmentCapabilities(adapterAttachments, model.attachments);
  const output = {
    ...model,
    attachments
  };
  if (rawInputModalities) {
    const inputModalities = normalizeInputModalities(rawInputModalities);
    if (!inputModalities.includes('image')) attachments.image = attachmentHandling.UNSUPPORTED;
    if (!inputModalities.includes('pdf')) attachments.pdf = attachmentHandling.UNSUPPORTED;
    output.inputModalities = inputModalities;
  } else {
    delete output.inputModalities;
  }
  return output;
}

function explicitInputModalities(model) {
  if (!model || typeof model !== 'object') return null;
  if (Array.isArray(model.inputModalities)) return model.inputModalities;
  if (Array.isArray(model.input_modalities)) return model.input_modalities;
  return null;
}

function mergeAttachmentCapabilities(adapterAttachments, modelAttachments) {
  const attachments = normalizeAttachmentCapabilities(adapterAttachments);
  const modelInput = modelAttachments && typeof modelAttachments === 'object' ? modelAttachments : {};
  for (const key of Object.keys(defaultAttachmentCapabilities)) {
    if (Object.values(attachmentHandling).includes(modelInput[key])) {
      attachments[key] = modelInput[key];
    }
  }
  return attachments;
}

module.exports = {
  attachmentKinds,
  attachmentHandling,
  defaultAttachmentCapabilities,
  normalizeAttachmentCapabilities,
  normalizeInputModalities,
  explicitInputModalities,
  applyModelAttachmentCapabilities
};
