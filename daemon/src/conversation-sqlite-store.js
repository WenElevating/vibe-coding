'use strict';

const { AppSqliteStore, defaultAppDbPath } = require('./app-sqlite-store');

class ConversationSqliteStore extends AppSqliteStore {}

function defaultDbPath() {
  return defaultAppDbPath();
}

module.exports = { ConversationSqliteStore, defaultDbPath };
