'use strict';

const crypto = require('node:crypto');
const { loadCodexAppServerMethods } = require('./methods');

const REVIEWED_METHOD_SURFACE_SIGNATURE = 'd73ae1187282b17fa5620a414460f1e7fc7916be5b22dc2b6d693fe68aa8dbb1';

const DIRECTIONS = new Set(['request', 'notification', 'serverRequest']);
const STABILITIES = new Set(['stable', 'experimental']);
const CATEGORIES = new Set([
  'lifecycle',
  'model',
  'thread',
  'turn',
  'item',
  'command',
  'file',
  'mcp',
  'skill',
  'plugin',
  'app',
  'config',
  'auth',
  'sandbox',
  'remote-control',
  'diagnostics',
  'unknown'
]);
const LOCAL_STATUSES = new Set([
  'supported',
  'partial',
  'planned',
  'diagnostic-only',
  'unsupported',
  'intentionally-blocked'
]);
const DAEMON_OWNERS = new Set([
  'client',
  'conversation adapter',
  'listing adapter',
  'server route',
  'matrix only',
  'diagnostics',
  'none'
]);
const MOBILE_STATUSES = new Set(['consumed', 'protocol-only', 'planned', 'not planned']);
const RISKS = new Set(['none', 'read', 'write', 'process', 'account', 'network', 'permission', 'unknown']);
const TEST_REQUIREMENTS = new Set(['unit', 'integration fake transport', 'route test', 'mobile contract test', 'matrix/event metadata only', 'manual-only']);

const EXPLICIT_ROWS = [
  row('initialize', 'request', 'stable', 'lifecycle', 'supported', 'client', 'protocol-only', 'none', 'unit', 'Existing initialization request.'),
  row('initialized', 'notification', 'stable', 'lifecycle', 'supported', 'client', 'protocol-only', 'none', 'unit', 'Existing initialized notification.'),
  row('model/list', 'request', 'stable', 'model', 'supported', 'listing adapter', 'consumed', 'read', 'unit', 'Existing model picker source through /api/adapters.'),
  row('modelProvider/capabilities/read', 'request', 'stable', 'model', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('permissionProfile/list', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('app/list', 'request', 'stable', 'app', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('app/list/updated', 'notification', 'stable', 'app', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('mcpServerStatus/list', 'request', 'stable', 'mcp', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('mcpServer/resource/read', 'request', 'stable', 'mcp', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('mcpServer/startupStatus/updated', 'notification', 'stable', 'mcp', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('skills/list', 'request', 'stable', 'skill', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('skills/changed', 'notification', 'stable', 'skill', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('plugin/list', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('plugin/read', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('plugin/skill/read', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('plugin/share/list', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('hooks/list', 'request', 'stable', 'diagnostics', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('hook/started', 'notification', 'stable', 'diagnostics', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('hook/completed', 'notification', 'stable', 'diagnostics', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('collaborationMode/list', 'request', 'stable', 'remote-control', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('experimentalFeature/list', 'request', 'experimental', 'diagnostics', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('externalAgentConfig/detect', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('config/read', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('configRequirements/read', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('configWarning', 'notification', 'stable', 'config', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('windowsSandbox/readiness', 'request', 'stable', 'sandbox', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 4 read-only discovery route.'),
  row('windowsSandbox/setupCompleted', 'notification', 'stable', 'sandbox', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('windows/worldWritableWarning', 'notification', 'stable', 'sandbox', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('deprecationNotice', 'notification', 'stable', 'diagnostics', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('warning', 'notification', 'stable', 'diagnostics', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('guardianWarning', 'notification', 'stable', 'diagnostics', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('model/rerouted', 'notification', 'stable', 'model', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('model/verification', 'notification', 'stable', 'model', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 4 discovery notification metadata; not consumed by event sink yet.'),
  row('account/read', 'request', 'stable', 'auth', 'supported', 'server route', 'planned', 'account', 'route test', 'Task 5 account status read route with redacted DTO.'),
  row('account/rateLimits/read', 'request', 'stable', 'auth', 'supported', 'server route', 'planned', 'account', 'route test', 'Task 5 account rate-limit read route with redacted DTO.'),
  row('account/login/start', 'request', 'stable', 'auth', 'supported', 'server route', 'planned', 'account', 'route test', 'Task 5 audited account login mutation route.'),
  row('account/login/cancel', 'request', 'stable', 'auth', 'supported', 'server route', 'planned', 'account', 'route test', 'Task 5 audited account login cancellation route.'),
  row('account/logout', 'request', 'stable', 'auth', 'supported', 'server route', 'planned', 'account', 'route test', 'Task 5 audited account logout mutation route.'),
  row('account/sendAddCreditsNudgeEmail', 'request', 'stable', 'auth', 'supported', 'server route', 'planned', 'account', 'route test', 'Task 5 audited add-credits email nudge route.'),
  row('mcpServer/oauth/login', 'request', 'stable', 'mcp', 'supported', 'server route', 'planned', 'account', 'route test', 'Task 5 audited MCP OAuth login route.'),
  row('account/chatgptAuthTokens/refresh', 'serverRequest', 'stable', 'auth', 'intentionally-blocked', 'conversation adapter', 'not planned', 'account', 'unit', 'Token refresh requires an explicit secure token provider; daemon must not synthesize or expose account tokens.'),
  row('account/updated', 'notification', 'stable', 'auth', 'partial', 'server route', 'planned', 'account', 'matrix/event metadata only', 'Task 5 account notification metadata; not consumed by event sink yet.'),
  row('account/rateLimits/updated', 'notification', 'stable', 'auth', 'partial', 'server route', 'planned', 'account', 'matrix/event metadata only', 'Task 5 account rate-limit notification metadata; not consumed by event sink yet.'),
  row('account/login/completed', 'notification', 'stable', 'auth', 'partial', 'server route', 'planned', 'account', 'matrix/event metadata only', 'Task 5 account login notification metadata; not consumed by event sink yet.'),
  row('mcpServer/oauthLogin/completed', 'notification', 'stable', 'mcp', 'partial', 'server route', 'planned', 'account', 'matrix/event metadata only', 'Task 5 MCP OAuth login notification metadata; not consumed by event sink yet.'),
  row('fs/getMetadata', 'request', 'stable', 'file', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 6 workspace-scoped filesystem metadata read route.'),
  row('fs/readDirectory', 'request', 'stable', 'file', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 6 workspace-scoped filesystem directory read route.'),
  row('fs/readFile', 'request', 'stable', 'file', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 6 workspace-scoped filesystem file read route.'),
  row('fs/watch', 'request', 'stable', 'file', 'diagnostic-only', 'server route', 'planned', 'permission', 'route test', 'Task 6 workspace-scoped watch diagnostic route until mobile watcher UX exists.'),
  row('fs/unwatch', 'request', 'stable', 'file', 'diagnostic-only', 'server route', 'planned', 'permission', 'route test', 'Task 6 workspace-scoped unwatch diagnostic route until mobile watcher UX exists.'),
  row('fs/changed', 'notification', 'stable', 'file', 'diagnostic-only', 'server route', 'planned', 'permission', 'matrix/event metadata only', 'Task 6 filesystem watch notification metadata; not consumed by event sink yet.'),
  row('fs/copy', 'request', 'stable', 'file', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk workspace-scoped file copy route with approval gate.'),
  row('fs/createDirectory', 'request', 'stable', 'file', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk workspace-scoped directory creation route with approval gate.'),
  row('fs/remove', 'request', 'stable', 'file', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk workspace-scoped remove route with approval gate.'),
  row('fs/writeFile', 'request', 'stable', 'file', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk workspace-scoped file write route with approval gate.'),
  row('process/spawn', 'request', 'stable', 'command', 'supported', 'server route', 'planned', 'process', 'route test', 'Task 8 high-risk workspace-scoped process spawn route with approval gate.'),
  row('process/kill', 'request', 'stable', 'command', 'supported', 'server route', 'planned', 'process', 'route test', 'Task 8 high-risk workspace-scoped process kill route with approval gate.'),
  row('process/resizePty', 'request', 'stable', 'command', 'diagnostic-only', 'matrix only', 'planned', 'process', 'manual-only', 'Task 8 classified as high-risk process control; no product route exists yet.'),
  row('process/writeStdin', 'request', 'stable', 'command', 'diagnostic-only', 'matrix only', 'planned', 'process', 'manual-only', 'Task 8 classified as high-risk process input; no product route exists yet.'),
  row('process/exited', 'notification', 'stable', 'command', 'partial', 'server route', 'planned', 'process', 'matrix/event metadata only', 'Task 8 process notification metadata only; no route-level stream yet.'),
  row('process/outputDelta', 'notification', 'stable', 'command', 'partial', 'server route', 'planned', 'process', 'matrix/event metadata only', 'Task 8 process output notification metadata only; no route-level stream yet.'),
  row('command/exec', 'request', 'stable', 'command', 'supported', 'server route', 'planned', 'process', 'route test', 'Task 8 high-risk workspace-scoped command execution route with approval gate.'),
  row('command/exec/resize', 'request', 'stable', 'command', 'diagnostic-only', 'matrix only', 'planned', 'process', 'manual-only', 'Task 8 classified as high-risk command control; no product route exists yet.'),
  row('command/exec/terminate', 'request', 'stable', 'command', 'diagnostic-only', 'matrix only', 'planned', 'process', 'manual-only', 'Task 8 classified as high-risk command control; no product route exists yet.'),
  row('command/exec/write', 'request', 'stable', 'command', 'diagnostic-only', 'matrix only', 'planned', 'process', 'manual-only', 'Task 8 classified as high-risk command input; no product route exists yet.'),
  row('command/exec/outputDelta', 'notification', 'stable', 'command', 'partial', 'server route', 'planned', 'process', 'matrix/event metadata only', 'Task 8 command output notification metadata only; no route-level stream yet.'),
  row('config/value/write', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk config value write route with approval gate.'),
  row('config/batchWrite', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk config batch write route with approval gate.'),
  row('config/mcpServer/reload', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk MCP server config reload route with approval gate.'),
  row('environment/add', 'request', 'stable', 'config', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk environment add route with approval gate.'),
  row('plugin/install', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk plugin install route with approval gate.'),
  row('plugin/uninstall', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk plugin uninstall route with approval gate.'),
  row('plugin/installed', 'notification', 'stable', 'plugin', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 8 plugin installed notification metadata only; not consumed by event sink yet.'),
  row('plugin/share/checkout', 'request', 'stable', 'plugin', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 8 classified as high-risk plugin share mutation; no product route exists yet.'),
  row('plugin/share/delete', 'request', 'stable', 'plugin', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 8 classified as high-risk plugin share mutation; no product route exists yet.'),
  row('plugin/share/save', 'request', 'stable', 'plugin', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 8 classified as high-risk plugin share mutation; no product route exists yet.'),
  row('plugin/share/updateTargets', 'request', 'stable', 'plugin', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 8 classified as high-risk plugin share mutation; no product route exists yet.'),
  row('marketplace/add', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk marketplace add route with approval gate.'),
  row('marketplace/remove', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk marketplace remove route with approval gate.'),
  row('marketplace/upgrade', 'request', 'stable', 'plugin', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk marketplace upgrade route with approval gate.'),
  row('skills/config/write', 'request', 'stable', 'skill', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk skills config write route with approval gate.'),
  row('skills/extraRoots/set', 'request', 'stable', 'skill', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 8 high-risk skills extra roots route with approval gate.'),
  row('remoteControl/status/read', 'request', 'stable', 'remote-control', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 8 remote-control status read route.'),
  row('remoteControl/client/list', 'request', 'stable', 'remote-control', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 8 remote-control client list route.'),
  row('remoteControl/client/revoke', 'request', 'stable', 'remote-control', 'supported', 'server route', 'planned', 'network', 'route test', 'Task 8 high-risk remote-control client revoke route with approval gate.'),
  row('remoteControl/enable', 'request', 'stable', 'remote-control', 'supported', 'server route', 'planned', 'network', 'route test', 'Task 8 high-risk remote-control enable route with approval gate.'),
  row('remoteControl/disable', 'request', 'stable', 'remote-control', 'supported', 'server route', 'planned', 'network', 'route test', 'Task 8 high-risk remote-control disable route with approval gate.'),
  row('remoteControl/pairing/start', 'request', 'stable', 'remote-control', 'supported', 'server route', 'planned', 'network', 'route test', 'Task 8 high-risk remote-control pairing route with approval gate.'),
  row('remoteControl/status/changed', 'notification', 'stable', 'remote-control', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 8 remote-control status notification metadata only; not consumed by event sink yet.'),
  row('thread/list', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 thread history list route.'),
  row('thread/loaded/list', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 loaded thread list route.'),
  row('thread/read', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 thread read route.'),
  row('thread/search', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 workspace-scoped thread search route.'),
  row('thread/turns/list', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 thread turns route.'),
  row('thread/turns/items/list', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 thread turn items route.'),
  row('thread/goal/get', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 thread goal route.'),
  row('thread/fork', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread fork mutation route.'),
  row('thread/archive', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread archive mutation route.'),
  row('thread/unarchive', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread unarchive mutation route.'),
  row('thread/rollback', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread rollback mutation route.'),
  row('thread/metadata/update', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread metadata mutation route.'),
  row('thread/name/set', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread name mutation route.'),
  row('thread/settings/update', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread settings mutation route.'),
  row('thread/memoryMode/set', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread memory mode mutation route.'),
  row('thread/goal/set', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread goal mutation route.'),
  row('thread/goal/clear', 'request', 'stable', 'thread', 'supported', 'server route', 'planned', 'write', 'route test', 'Task 7 workspace-scoped audited thread goal clear mutation route.'),
  row('thread/inject_items', 'request', 'stable', 'thread', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 7 classified as diagnostic-only metadata; no product route exists yet.'),
  row('thread/unsubscribe', 'request', 'stable', 'thread', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 7 classified as diagnostic-only metadata; no product route exists yet.'),
  row('thread/compact/start', 'request', 'stable', 'thread', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 7 classified as diagnostic-only metadata; no product route exists yet.'),
  row('thread/backgroundTerminals/clean', 'request', 'stable', 'thread', 'diagnostic-only', 'matrix only', 'planned', 'process', 'manual-only', 'Task 7 classified as diagnostic-only metadata; no product route exists yet.'),
  row('thread/approveGuardianDeniedAction', 'request', 'stable', 'thread', 'diagnostic-only', 'matrix only', 'planned', 'permission', 'manual-only', 'Task 7 classified as diagnostic-only metadata; no product route exists yet.'),
  row('thread/increment_elicitation', 'request', 'stable', 'thread', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 7 classified as diagnostic-only metadata; no product route exists yet.'),
  row('thread/decrement_elicitation', 'request', 'stable', 'thread', 'diagnostic-only', 'matrix only', 'planned', 'write', 'manual-only', 'Task 7 classified as diagnostic-only metadata; no product route exists yet.'),
  row('thread/status/changed', 'notification', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 read API parity event metadata.'),
  row('thread/tokenUsage/updated', 'notification', 'stable', 'thread', 'supported', 'server route', 'planned', 'read', 'route test', 'Task 3 read API parity event metadata.'),
  row('thread/archived', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/unarchived', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/name/updated', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/settings/updated', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/goal/updated', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/goal/cleared', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/closed', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/compacted', 'notification', 'stable', 'thread', 'partial', 'server route', 'planned', 'read', 'matrix/event metadata only', 'Task 7 thread mutation notification metadata; not consumed by event sink yet.'),
  row('thread/start', 'request', 'stable', 'thread', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing conversation startup path.'),
  row('thread/resume', 'request', 'stable', 'thread', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing conversation resume path.'),
  row('turn/start', 'request', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing user message path.'),
  row('turn/interrupt', 'request', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing cancel path; side-effecting after request write.'),
  row('item/commandExecution/requestApproval', 'serverRequest', 'stable', 'command', 'supported', 'conversation adapter', 'consumed', 'permission', 'unit', 'Existing mobile approval request mapping.'),
  row('item/fileChange/requestApproval', 'serverRequest', 'stable', 'file', 'supported', 'conversation adapter', 'consumed', 'permission', 'unit', 'Existing file-change approval request mapping.'),
  row('item/permissions/requestApproval', 'serverRequest', 'stable', 'item', 'supported', 'conversation adapter', 'consumed', 'permission', 'unit', 'Existing permission approval request mapping.'),
  row('item/agentMessage/delta', 'notification', 'stable', 'item', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing streaming assistant.partial mapping.'),
  row('item/commandExecution/outputDelta', 'notification', 'stable', 'command', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing tool.delta mapping.'),
  row('thread/started', 'notification', 'stable', 'thread', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing event mapping.'),
  row('turn/started', 'notification', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing event mapping.'),
  row('turn/completed', 'notification', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing completion mapping.'),
  row('turn/plan/updated', 'notification', 'stable', 'turn', 'partial', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Mapped to todo list events.'),
  row('item/started', 'notification', 'stable', 'item', 'partial', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Mapped through current Codex event bridge.'),
  row('item/completed', 'notification', 'stable', 'item', 'partial', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Mapped through current Codex event bridge.'),
  row('error', 'notification', 'stable', 'diagnostics', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing run error mapping.')
];

const CODEX_APP_SERVER_CAPABILITY_MATRIX = buildMatrix();

function row(method, direction, stability, category, localStatus, daemonOwner, mobileStatus, risk, testRequirement, rationale) {
  return { method, direction, stability, category, localStatus, daemonOwner, mobileStatus, risk, testRequirement, rationale };
}

function buildMatrix(methods = loadCodexAppServerMethods()) {
  const rows = new Map();
  for (const explicit of EXPLICIT_ROWS) rows.set(explicit.method, explicit);
  addGeneratedDefaults(rows, methods.clientRequests || methods.requests, 'request');
  addGeneratedDefaults(rows, methods.clientNotifications, 'notification');
  addGeneratedDefaults(rows, methods.serverRequests, 'serverRequest');
  addGeneratedDefaults(rows, methods.serverNotifications || methods.notifications, 'notification');
  return [...rows.values()].sort((left, right) => left.method.localeCompare(right.method));
}

function addGeneratedDefaults(rows, methods, direction) {
  for (const method of methods || []) {
    if (rows.has(method)) continue;
    rows.set(method, row(
      method,
      direction,
      inferStability(method),
      inferCategory(method),
      'unsupported',
      'none',
      'not planned',
      'unknown',
      'unit',
      'Generated from official app-server schema; not classified yet.'
    ));
  }
}

function validateCodexAppServerCapabilityMatrix(rows = CODEX_APP_SERVER_CAPABILITY_MATRIX, methods = loadCodexAppServerMethods()) {
  const errors = [];
  const seen = new Set();
  const signature = codexAppServerMethodSurfaceSignature(methods);
  if (signature !== REVIEWED_METHOD_SURFACE_SIGNATURE) {
    errors.push(`official method surface changed: ${signature}`);
  }
  for (const current of rows) {
    if (!current || typeof current !== 'object') {
      errors.push('matrix row must be an object');
      continue;
    }
    if (!current.method) errors.push('matrix row missing method');
    if (seen.has(current.method)) errors.push(`${current.method} duplicate row`);
    seen.add(current.method);
    validateEnum(errors, current, 'direction', DIRECTIONS);
    validateEnum(errors, current, 'stability', STABILITIES);
    validateEnum(errors, current, 'category', CATEGORIES);
    validateEnum(errors, current, 'localStatus', LOCAL_STATUSES);
    validateEnum(errors, current, 'daemonOwner', DAEMON_OWNERS);
    validateEnum(errors, current, 'mobileStatus', MOBILE_STATUSES);
    validateEnum(errors, current, 'risk', RISKS);
    validateEnum(errors, current, 'testRequirement', TEST_REQUIREMENTS);
    if (current.risk === 'unknown' && current.localStatus !== 'unsupported') {
      errors.push(`${current.method} has active status with unknown risk`);
    }
    if (current.risk === 'unknown' && current.mobileStatus !== 'not planned') {
      errors.push(`${current.method} is mobile-accessible with unknown risk`);
    }
  }
  requireRows(errors, seen, methods.clientRequests || methods.requests, 'client request');
  requireRows(errors, seen, methods.clientNotifications, 'client notification');
  requireRows(errors, seen, methods.serverRequests, 'serverRequest');
  requireRows(errors, seen, methods.serverNotifications || methods.notifications, 'server notification');
  return { errors };
}

function requireRows(errors, seen, methods, label) {
  for (const method of methods || []) {
    if (!seen.has(method)) errors.push(`${method} missing ${label} row`);
  }
}

function codexAppServerMethodSurfaceSignature(methods = loadCodexAppServerMethods()) {
  const payload = JSON.stringify({
    clientRequests: sortedMethods(methods.clientRequests || methods.requests),
    clientNotifications: sortedMethods(methods.clientNotifications),
    serverRequests: sortedMethods(methods.serverRequests),
    serverNotifications: sortedMethods(methods.serverNotifications || methods.notifications)
  });
  return crypto.createHash('sha256').update(payload).digest('hex');
}

function sortedMethods(methods) {
  return [...(methods || [])].sort();
}

function summarizeCodexAppServerCapabilityMatrix(rows = CODEX_APP_SERVER_CAPABILITY_MATRIX) {
  const validation = validateCodexAppServerCapabilityMatrix(rows);
  return {
    totalMethods: rows.length,
    supportedMethods: rows.filter((row) => row.localStatus === 'supported').length,
    partialMethods: rows.filter((row) => row.localStatus === 'partial').length,
    plannedMethods: rows.filter((row) => row.localStatus === 'planned').length,
    unsupportedMethods: rows.filter((row) => row.localStatus === 'unsupported').length,
    diagnosticOnlyMethods: rows.filter((row) => row.localStatus === 'diagnostic-only').length,
    intentionallyBlockedMethods: rows.filter((row) => row.localStatus === 'intentionally-blocked').length,
    invalidRows: validation.errors.length
  };
}

function validateEnum(errors, current, key, allowed) {
  if (!allowed.has(current[key])) errors.push(`${current.method || '<unknown>'} has invalid ${key}: ${current[key]}`);
}

function inferStability(method) {
  return /experimental|fuzzy|attestation|dynamic|mock/i.test(method) ? 'experimental' : 'stable';
}

function inferCategory(method) {
  const lower = String(method || '').toLowerCase();
  if (lower === 'initialize' || lower === 'initialized') return 'lifecycle';
  if (lower.startsWith('model/')) return 'model';
  if (lower.startsWith('thread/')) return 'thread';
  if (lower.startsWith('turn/')) return 'turn';
  if (lower.startsWith('item/commandexecution')) return 'command';
  if (lower.startsWith('item/filechange')) return 'file';
  if (lower.startsWith('item/')) return 'item';
  if (lower.startsWith('mcp/')) return 'mcp';
  if (lower.startsWith('skills/') || lower.startsWith('skill/')) return 'skill';
  if (lower.startsWith('plugin/') || lower.startsWith('marketplace/')) return 'plugin';
  if (lower.startsWith('apps/') || lower.startsWith('app/')) return 'app';
  if (lower.startsWith('config/')) return 'config';
  if (lower.includes('auth') || lower.includes('account') || lower.includes('login') || lower.includes('logout')) return 'auth';
  if (lower.includes('sandbox')) return 'sandbox';
  if (lower.startsWith('remotecontrol/')) return 'remote-control';
  if (lower.startsWith('command/') || lower.startsWith('process/')) return 'command';
  if (lower.startsWith('fs/')) return 'file';
  if (lower.includes('feedback') || lower.includes('warning') || lower.includes('deprecation')) return 'diagnostics';
  return 'unknown';
}

module.exports = {
  CODEX_APP_SERVER_CAPABILITY_MATRIX,
  buildCodexAppServerCapabilityMatrix: buildMatrix,
  codexAppServerMethodSurfaceSignature,
  summarizeCodexAppServerCapabilityMatrix,
  validateCodexAppServerCapabilityMatrix
};
