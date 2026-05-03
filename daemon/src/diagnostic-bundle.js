'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

class DiagnosticBundleService {
  constructor({ diagnostics, runs, runQueue, commandTemplates, auditLog, outputDir = path.join(process.cwd(), '.omx', 'diagnostics') }) {
    this.diagnostics = diagnostics;
    this.runs = runs;
    this.runQueue = runQueue;
    this.commandTemplates = commandTemplates;
    this.auditLog = auditLog;
    this.outputDir = outputDir;
  }

  async exportBundle() {
    fs.mkdirSync(this.outputDir, { recursive: true });
    const bundleId = `diag_${crypto.randomUUID()}`;
    const createdAt = new Date().toISOString();
    const content = redact({
      bundleId,
      createdAt,
      daemon_status: await this.diagnostics.status(),
      run_summary: this.runs.publicSummaries ? this.runs.publicSummaries() : [],
      queue_summary: this.runQueue.list(),
      command_template_summary: this.commandTemplates.list().map((item) => ({ id: item.id, label: item.label, requiresApproval: item.requiresApproval })),
      redaction_report: { redacted: true, excluded: ['device tokens', 'provider API keys', 'environment variables', 'raw console output'] }
    });
    const filePath = path.join(this.outputDir, `${bundleId}.json`);
    fs.writeFileSync(filePath, JSON.stringify(content, null, 2), 'utf8');
    this.auditLog.record('diagnostic.export', { bundleId, path: filePath, redacted: true });
    return {
      bundleId,
      createdAt,
      path: filePath,
      redacted: true,
      items: ['daemon_status', 'adapter_status', 'recent_errors', 'schema_version', 'run_summary', 'queue_summary', 'command_template_summary', 'redaction_report']
    };
  }
}

function redact(value) {
  if (Array.isArray(value)) return value.map(redact);
  if (!value || typeof value !== 'object') return value;
  const output = {};
  for (const [key, item] of Object.entries(value)) {
    if (/token|secret|password|apiKey|authorization|env/i.test(key)) output[key] = '[REDACTED]';
    else output[key] = redact(item);
  }
  return output;
}

module.exports = { DiagnosticBundleService, redact };
