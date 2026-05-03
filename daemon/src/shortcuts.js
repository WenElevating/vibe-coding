'use strict';

class ShortcutStore {
  constructor() {
    this.shortcuts = new Map([
      ['test', { id: 'test', label: 'Run tests', prompt: 'Run the test suite and summarize failures.', tool: 'claude' }],
      ['lint', { id: 'lint', label: 'Run lint', prompt: 'Run lint/type checks and fix straightforward issues.', tool: 'claude' }],
      ['review', { id: 'review', label: 'Review code', prompt: 'Review recent changes for bugs and risks.', tool: 'claude' }],
      ['fix', { id: 'fix', label: 'Fix issue', prompt: 'Investigate and fix the reported issue.', tool: 'claude' }],
      ['explain', { id: 'explain', label: 'Explain project', prompt: 'Explain the current project structure and key flows.', tool: 'claude' }]
    ]);
  }

  list() {
    return Array.from(this.shortcuts.values());
  }

  get(id) {
    const shortcut = this.shortcuts.get(id);
    if (!shortcut) {
      const error = new Error('shortcut not found');
      error.status = 404;
      throw error;
    }
    return shortcut;
  }

  upsert(shortcut) {
    if (!shortcut.id || !shortcut.label || !shortcut.prompt) {
      const error = new Error('shortcut id, label, and prompt are required');
      error.status = 400;
      throw error;
    }
    const normalized = { tool: 'claude', ...shortcut };
    this.shortcuts.set(normalized.id, normalized);
    return normalized;
  }
}

module.exports = { ShortcutStore };
