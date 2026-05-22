'use strict';

const MAX_CONVERSATION_TITLE_LENGTH = 80;

function deriveConversationTitle(input = {}) {
  const textTitle = normalizeConversationTitle(input.text);
  if (textTitle) return textTitle;
  const attachments = Array.isArray(input.attachments) ? input.attachments : [];
  for (const attachment of attachments) {
    const attachmentTitle = normalizeConversationTitle(attachment?.name);
    if (attachmentTitle) return attachmentTitle;
  }
  return null;
}

function normalizeConversationTitle(value) {
  if (typeof value !== 'string') return null;
  const flat = value.replace(/\s+/g, ' ').trim();
  if (!flat) return null;
  const chars = Array.from(flat);
  if (chars.length <= MAX_CONVERSATION_TITLE_LENGTH) return flat;
  const truncated = chars.slice(0, MAX_CONVERSATION_TITLE_LENGTH).join('').trim();
  return truncated || null;
}

module.exports = {
  deriveConversationTitle,
  normalizeConversationTitle,
  MAX_CONVERSATION_TITLE_LENGTH
};
