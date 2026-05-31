'use strict';

const catalogs = Object.freeze({
  claude: Object.freeze([
    command('/add-dir', 'add additional working directories'),
    command('/agents', 'manage specialized subagents'),
    command('/clear', 'clear conversation history'),
    command('/compact', 'compact conversation with optional instructions'),
    command('/cost', 'show token usage and cost'),
    command('/doctor', 'check Claude Code installation health'),
    command('/help', 'show help and available commands'),
    command('/ide', 'manage IDE integrations'),
    command('/init', 'create a CLAUDE.md project memory file'),
    command('/mcp', 'manage MCP server connections'),
    command('/memory', 'edit memory files'),
    command('/model', 'select model for the current session'),
    command('/permissions', 'review or update permission rules'),
    command('/pr_comments', 'view pull request comments'),
    command('/review', 'request a code review'),
    command('/status', 'show account and system status'),
    command('/terminal-setup', 'install terminal key binding support'),
    command('/vim', 'toggle vim mode')
  ]),
  codex: Object.freeze([
    command('/model', 'choose what model and reasoning effort to use'),
    command('/status', 'show current session configuration and account status'),
    command('/approvals', 'choose approval behavior for commands and edits'),
    command('/diff', 'review current code changes'),
    command('/compact', 'summarize the conversation to free context'),
    command('/new', 'start a new conversation'),
    command('/init', 'create project instructions for Codex'),
    command('/help', 'show help and available commands')
  ]),
  opencode: Object.freeze([
    command('/help', 'show help and available commands'),
    command('/model', 'select model for the current session'),
    command('/new', 'start a new session'),
    command('/share', 'share the current session'),
    command('/status', 'show current session status')
  ])
});

class SlashCommandCatalog {
  list(adapterId) {
    const adapter = normalizeAdapterId(adapterId);
    return {
      adapter,
      commands: Array.from(catalogs[adapter] || [])
    };
  }
}

function command(commandText, description) {
  return Object.freeze({ command: commandText, description });
}

function normalizeAdapterId(value) {
  return String(value || '').trim().toLowerCase();
}

module.exports = { SlashCommandCatalog };
