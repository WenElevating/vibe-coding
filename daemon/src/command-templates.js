'use strict';

const { assertNoV1TerminalRequest, errorCodes } = require('./protocol');

class CommandTemplateStore {
  constructor() {
    this.templates = new Map([
      ['test', template('test', 'Run tests', 'Run the configured test command and summarize failures.', 'npm test', true)],
      ['lint', template('lint', 'Run lint', 'Run lint/type checks and summarize failures.', 'npm run lint', true)],
      ['build', template('build', 'Run build', 'Run the configured build command.', 'npm run build', true)],
      ['review', template('review', 'Review code', 'Review recent changes for bugs and risks.', 'adapter:review', false)],
      ['explain', template('explain', 'Explain project', 'Explain the current project structure.', 'adapter:explain', false)]
    ]);
  }

  list() {
    return Array.from(this.templates.values());
  }

  get(id) {
    const item = this.templates.get(id);
    if (!item) {
      const error = new Error('command template not found');
      error.status = 404;
      error.code = errorCodes.COMMAND_TEMPLATE_NOT_FOUND;
      throw error;
    }
    return item;
  }

  upsert(input) {
    assertNoV1TerminalRequest(input);
    if (!input.id || !input.label || !input.prompt) {
      const error = new Error('template id, label, and prompt are required');
      error.status = 400;
      throw error;
    }
    const item = { ...input, requiresApproval: input.requiresApproval !== false, createdAt: new Date().toISOString() };
    this.templates.set(item.id, item);
    return item;
  }
}

function template(id, label, prompt, safeCommand, requiresApproval) {
  return { id, workspaceId: '*', label, prompt, safeCommand, requiresApproval, createdAt: new Date().toISOString() };
}

module.exports = { CommandTemplateStore };
