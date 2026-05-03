'use strict';

const { schemaVersion } = require('./version');

class MigrationService {
  constructor({ now = () => new Date() } = {}) {
    this.now = now;
    this.status = {
      status: 'ok',
      schemaVersion,
      lastMigration: this.now().toISOString(),
      preservedStores: ['pairedDevices', 'workspaces', 'runs', 'events', 'queue', 'templates', 'adapterProfiles']
    };
  }

  getStatus() {
    return { ...this.status };
  }

  validate() {
    return { ok: this.status.status === 'ok', ...this.getStatus() };
  }
}

module.exports = { MigrationService };
