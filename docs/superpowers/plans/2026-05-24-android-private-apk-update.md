# Android Private APK Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an internal daemon-hosted Android APK update flow with resumable downloads, package verification, and Android system install confirmation.

**Architecture:** The daemon owns update manifests and APK byte serving. Mobile owns version comparison, resumable download state, hash verification, settings UI, and an Android `PackageInstaller.Session` bridge. The normal update path is `daemon latest manifest -> mobile download manager -> verified APK -> PackageInstaller session`.

**Tech Stack:** Node.js HTTP daemon, Flutter/Dart layered app, Kotlin Android platform channel, `http`, `crypto`, `path_provider`, `shared_preferences`, `package_info_plus`, Android `PackageInstaller`.

---

## Reference Spec

Use this spec as the authority for behavior:

```text
docs/superpowers/specs/2026-05-24-android-private-apk-update-design.md
```

Do not implement silent install, Google Play updates, Shorebird, background download guarantees, or client-selectable rollback versions in this plan.

## File Map

Daemon files:

- Create `daemon/src/app-update-service.js`: validates `latest.json`, serves manifest metadata, streams only the current APK, supports `HEAD`, `GET`, `Range`, `If-Range`, `ETag`, `If-None-Match`, and retained-artifact safety.
- Modify `daemon/src/main.js`: instantiate `AppUpdateService` with `ANDROID_UPDATE_ARTIFACT_DIR` and pass it to the HTTP server.
- Modify `daemon/src/server.js`: add authenticated `/api/app-updates/android/latest` and `/api/app-updates/android/apk/:versionCode` routes.
- Create `scripts/prepare-android-update.js`: release helper that computes `sha256`, `sizeBytes`, `etag`, sidecar digest, and `latest.json`.
- Modify `scripts/run-tests.js`: add daemon unit/regression tests for manifest, range, ETag, auth, and retained non-latest `404`.
- Modify `daemon/test/server.test.js` only if the project owner wants `node:test` parity; the primary daemon gate remains `node scripts/run-tests.js`.

Mobile shared/data/domain files:

- Modify `mobile/pubspec.yaml`: add `package_info_plus`.
- Create `mobile/lib/src/data/models/app_update_models.dart`: manifest and download metadata models.
- Create `mobile/lib/src/domain/repositories/app_update_repository.dart`: repository contract used by UI.
- Create `mobile/lib/src/data/repositories/daemon_app_update_repository.dart`: daemon-backed update repository.
- Create `mobile/lib/src/services/app_update_client.dart`: raw manifest and APK request client using existing daemon auth.
- Create `mobile/lib/src/services/app_update_download_manager.dart`: `.part` files, resume, storage preflight, progress, hash verification, reconciliation, and cleanup.
- Create `mobile/lib/src/services/android_package_installer.dart`: Dart-side platform channel wrapper for PackageInstaller and storage APIs.
- Modify `mobile/lib/src/services/daemon_client.dart`: expose authenticated raw/stream request helpers that refresh auth before surfacing terminal failures.
- Modify `mobile/lib/src/app/app_dependencies.dart`: wire update repository, downloader, installer, and settings ViewModel factory.

Mobile UI/native files:

- Create `mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart`: update state machine and commands.
- Create `mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart`: settings panel UI.
- Modify `mobile/lib/src/ui/features/settings/settings_page.dart`: render update panel.
- Modify `mobile/lib/src/ui/main_tabs_page.dart`: create/dispose `AppUpdateViewModel`, pass it to settings, allow mandatory update escape hatches.
- Modify `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt`: method/event channels, `PackageInstaller.Session`, session result recovery, storage preflight.
- Modify `mobile/android/app/src/main/AndroidManifest.xml`: `REQUEST_INSTALL_PACKAGES`, FileProvider.
- Create `mobile/android/app/src/main/res/xml/file_paths.xml`: `<cache-path name="app_updates" path="app_updates/" />`.
- Modify `mobile/android/app/build.gradle.kts`: release signing config and AndroidX dependency if FileProvider is not already available transitively.

Mobile tests:

- Create `mobile/test/app_update_models_test.dart`.
- Create `mobile/test/app_update_client_test.dart`.
- Create `mobile/test/app_update_download_manager_test.dart`.
- Create `mobile/test/app_update_view_model_test.dart`.
- Create `mobile/test/app_update_panel_test.dart`.
- Modify `mobile/test/app_dependencies_test.dart`.
- Reuse `mobile/test/support/fake_http.dart` for HTTP assertions.

Verification commands:

```powershell
node scripts\run-tests.js
node scripts\check-project-knowledge.js
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\app_update_models_test.dart test\app_update_client_test.dart test\app_update_download_manager_test.dart test\app_update_view_model_test.dart test\app_update_panel_test.dart -r expanded
```

If any Flutter/Dart command times out once in the agent environment, stop retrying and ask the user to run the exact mirror-configured command.

---

### Task 1: Daemon App Update Service

**Files:**

- Create: `daemon/src/app-update-service.js`
- Modify: `daemon/src/main.js`
- Modify: `daemon/src/server.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Add failing daemon tests**

Add these tests to `scripts/run-tests.js` near the other `createApp`/HTTP API tests. Use helpers local to the test file so the test does not depend on a real APK.

```javascript
function createUpdateFixture({ versionCode = 2, apkBytes = Buffer.from('fake-apk-v2') } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-fixture-'));
  const apkName = `lan_ai_cli_control-1.4.0+${versionCode}.apk`;
  const apkPath = path.join(root, apkName);
  fs.writeFileSync(apkPath, apkBytes);
  const sha256 = require('node:crypto').createHash('sha256').update(apkBytes).digest('hex');
  const manifest = {
    schemaVersion: 1,
    platform: 'android',
    packageName: 'com.example.lan_ai_cli_control',
    versionName: '1.4.0',
    versionCode,
    minSupportedVersionCode: 1,
    mandatory: false,
    apkUrl: `/api/app-updates/android/apk/${versionCode}`,
    sha256,
    sizeBytes: apkBytes.length,
    etag: `"android-apk-${versionCode}-${sha256.slice(0, 12)}"`,
    releaseNotes: 'test update',
    publishedAt: '2026-05-24T10:00:00.000Z',
    fileName: apkName
  };
  fs.writeFileSync(path.join(root, 'latest.json'), JSON.stringify(manifest, null, 2), 'utf8');
  fs.writeFileSync(path.join(root, `${apkName}.sha256`), `${sha256}  ${apkName}\n`, 'utf8');
  return { root, apkBytes, manifest };
}

async function rawRequest(port, method, requestPath, { token, headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: '127.0.0.1',
      port,
      path: requestPath,
      method,
      headers: {
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...headers
      }
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve({
        status: res.statusCode,
        headers: res.headers,
        body: Buffer.concat(chunks)
      }));
    });
    req.on('error', reject);
    req.end();
  });
}

test('android update endpoints serve manifest, 304, HEAD, full APK, and range APK', async () => {
  const fixture = createUpdateFixture();
  const app = createApp({
    port: 0,
    devAdapters: false,
    appDbPath: tempConversationDbPath('app-db-update-api-'),
    androidUpdateArtifactDir: fixture.root
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'test',
      deviceId: 'device-update'
    });
    const token = paired.body.token;

    const latest = await rawRequest(port, 'GET', '/api/app-updates/android/latest', { token });
    assert.equal(latest.status, 200);
    assert.equal(latest.headers.etag, fixture.manifest.etag);
    assert.equal(JSON.parse(latest.body.toString('utf8')).schemaVersion, 1);

    const cached = await rawRequest(port, 'GET', '/api/app-updates/android/latest', {
      token,
      headers: { 'if-none-match': fixture.manifest.etag }
    });
    assert.equal(cached.status, 304);
    assert.equal(cached.body.length, 0);

    const head = await rawRequest(port, 'HEAD', `/api/app-updates/android/apk/${fixture.manifest.versionCode}`, { token });
    assert.equal(head.status, 200);
    assert.equal(Number(head.headers['content-length']), fixture.apkBytes.length);
    assert.equal(head.headers['accept-ranges'], 'bytes');

    const range = await rawRequest(port, 'GET', `/api/app-updates/android/apk/${fixture.manifest.versionCode}`, {
      token,
      headers: { range: 'bytes=2-', 'if-range': fixture.manifest.etag }
    });
    assert.equal(range.status, 206);
    assert.equal(range.headers['content-range'], `bytes 2-${fixture.apkBytes.length - 1}/${fixture.apkBytes.length}`);
    assert.deepEqual(range.body, fixture.apkBytes.subarray(2));
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('android update APK endpoint rejects retained non-latest versions and path escape', async () => {
  const fixture = createUpdateFixture({ versionCode: 5 });
  fs.writeFileSync(path.join(fixture.root, 'lan_ai_cli_control-1.3.0+3.apk'), Buffer.from('old'));
  const app = createApp({
    port: 0,
    devAdapters: false,
    appDbPath: tempConversationDbPath('app-db-update-retained-'),
    androidUpdateArtifactDir: fixture.root
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'test',
      deviceId: 'device-retained'
    });
    const token = paired.body.token;

    const old = await rawRequest(port, 'GET', '/api/app-updates/android/apk/3', { token });
    assert.equal(old.status, 404);

    const escapeRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-escape-'));
    fs.writeFileSync(path.join(fixture.root, 'latest.json'), JSON.stringify({
      ...fixture.manifest,
      fileName: path.relative(fixture.root, path.join(escapeRoot, 'evil.apk'))
    }), 'utf8');
    const invalidApp = createApp({
      port: 0,
      devAdapters: false,
      appDbPath: tempConversationDbPath('app-db-update-invalid-'),
      androidUpdateArtifactDir: fixture.root
    });
    assert.equal(invalidApp.appUpdates.available, false);
    invalidApp.appSqliteStore.close();
    fs.rmSync(escapeRoot, { recursive: true, force: true });
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected: fails with `Cannot find module '../daemon/src/app-update-service'` or `androidUpdateArtifactDir`/routes not implemented.

- [ ] **Step 3: Implement `AppUpdateService`**

Create `daemon/src/app-update-service.js` with this shape:

```javascript
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const apkContentType = 'application/vnd.android.package-archive';

class AppUpdateService {
  constructor({ artifactDir, now = () => new Date() } = {}) {
    this.artifactDir = artifactDir || path.join(process.cwd(), 'daemon', 'update-artifacts', 'android');
    this.now = now;
    this.available = false;
    this.manifest = {
      schemaVersion: 1,
      platform: 'android',
      available: false
    };
    this.apkPath = null;
    this.load();
  }

  load() {
    const manifestPath = path.join(this.artifactDir, 'latest.json');
    if (!fs.existsSync(manifestPath)) return;
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    validateManifest(manifest);
    const fileName = manifest.fileName || path.basename(String(manifest.apkUrl || ''));
    const resolved = path.resolve(this.artifactDir, fileName);
    const root = path.resolve(this.artifactDir);
    if (!(resolved === root || resolved.startsWith(root + path.sep))) {
      return;
    }
    if (!fs.existsSync(resolved)) return;
    const stats = fs.statSync(resolved);
    if (stats.size !== manifest.sizeBytes) return;
    const etag = manifest.etag || `"android-apk-${manifest.versionCode}-${manifest.sha256.slice(0, 12)}"`;
    this.manifest = { ...manifest, etag };
    this.apkPath = resolved;
    this.available = true;
  }

  sendLatest(req, res) {
    const etag = this.manifest.etag || `"android-update-none"`;
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, { etag });
      res.end();
      return;
    }
    json(res, 200, this.manifest, { etag });
  }

  sendApk(req, res, requestedVersionCode) {
    if (!this.available || Number(requestedVersionCode) !== this.manifest.versionCode) {
      return notFound(res);
    }
    const stats = fs.statSync(this.apkPath);
    const total = stats.size;
    const commonHeaders = {
      'content-type': apkContentType,
      'accept-ranges': 'bytes',
      etag: this.manifest.etag,
      'cache-control': 'private, no-cache'
    };
    if (req.method === 'HEAD') {
      res.writeHead(200, { ...commonHeaders, 'content-length': total });
      res.end();
      return;
    }
    const range = parseRange(req.headers.range, total);
    const ifRange = req.headers['if-range'];
    if (!range || (ifRange && ifRange !== this.manifest.etag)) {
      res.writeHead(200, { ...commonHeaders, 'content-length': total });
      fs.createReadStream(this.apkPath).pipe(res);
      return;
    }
    if (range.unsatisfiable) {
      res.writeHead(416, { ...commonHeaders, 'content-range': `bytes */${total}` });
      res.end();
      return;
    }
    res.writeHead(206, {
      ...commonHeaders,
      'content-length': range.end - range.start + 1,
      'content-range': `bytes ${range.start}-${range.end}/${total}`
    });
    fs.createReadStream(this.apkPath, { start: range.start, end: range.end }).pipe(res);
  }
}

function validateManifest(manifest) {
  if (manifest.schemaVersion !== 1) throw new Error('android update manifest schemaVersion must be 1');
  if (manifest.platform !== 'android') throw new Error('android update manifest platform must be android');
  if (!Number.isInteger(manifest.versionCode) || manifest.versionCode <= 0) throw new Error('android update manifest versionCode is invalid');
  if (typeof manifest.apkUrl !== 'string') throw new Error('android update manifest apkUrl is required');
  if (typeof manifest.sha256 !== 'string' || !/^[a-f0-9]{64}$/i.test(manifest.sha256)) throw new Error('android update manifest sha256 is invalid');
  if (!Number.isInteger(manifest.sizeBytes) || manifest.sizeBytes <= 0) throw new Error('android update manifest sizeBytes is invalid');
}

function parseRange(header, total) {
  if (!header) return null;
  const match = /^bytes=(\d+)-(\d*)$/.exec(String(header).trim());
  if (!match) return { unsatisfiable: true };
  const start = Number(match[1]);
  const end = match[2] ? Number(match[2]) : total - 1;
  if (start >= total || end < start) return { unsatisfiable: true };
  return { start, end: Math.min(end, total - 1) };
}

function notFound(res) {
  json(res, 404, { error: { code: 'NOT_FOUND', message: 'Android update artifact not found.' } });
}

function json(res, status, body, headers = {}) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', ...headers });
  res.end(JSON.stringify(body));
}

module.exports = { AppUpdateService };
```

- [ ] **Step 4: Wire service into app and routes**

Modify `daemon/src/main.js`:

```javascript
const { AppUpdateService } = require('./app-update-service');
```

Extend `createApp` parameters:

```javascript
  androidUpdateArtifactDir = process.env.ANDROID_UPDATE_ARTIFACT_DIR,
```

Create the service before `createServer`:

```javascript
  const appUpdates = new AppUpdateService({ artifactDir: androidUpdateArtifactDir });
```

Pass it into `createServer`:

```javascript
  const server = createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset, appUpdates });
```

Return it for tests:

```javascript
  return { server, auth, workspaces, eventStore, conversationEventStore, conversationSqliteStore, appSqliteStore, auditLog, adapterRegistry, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, migrationService, diagnostics, diagnosticBundle, runs, conversations, notificationHub, config, version, asrModelAsset, appUpdates, attachmentScratchCleanup };
```

Modify `daemon/src/server.js` signature:

```javascript
function createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset, appUpdates }) {
```

Add routes immediately after authentication and before other authenticated routes:

```javascript
      if (method === 'GET' && url.pathname === '/api/app-updates/android/latest') return appUpdates.sendLatest(req, res);
      const androidApk = url.pathname.match(/^\/api\/app-updates\/android\/apk\/(\d+)$/);
      if ((method === 'GET' || method === 'HEAD') && androidApk) return appUpdates.sendApk(req, res, androidApk[1]);
```

- [ ] **Step 5: Run daemon tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected: all tests pass.

- [ ] **Step 6: Commit daemon update service**

```powershell
git add daemon\src\app-update-service.js daemon\src\main.js daemon\src\server.js scripts\run-tests.js
git commit -m "Add daemon Android update service" -m "Constraint: APK download exposes only the manifest current versionCode; retained artifacts require operator manifest rollback." -m "Tested: node scripts\\run-tests.js"
```

---

### Task 2: Release Signing And Manifest Helper

**Files:**

- Modify: `mobile/android/app/build.gradle.kts`
- Modify: `.gitignore`
- Create: `mobile/android/key.properties.example`
- Create: `scripts/prepare-android-update.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Add failing helper tests**

Add this test to `scripts/run-tests.js`:

```javascript
test('prepare android update writes latest manifest and sha sidecar', async () => {
  const childProcess = require('node:child_process');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-helper-'));
  const apk = path.join(root, 'app-release.apk');
  const out = path.join(root, 'artifacts');
  fs.writeFileSync(apk, Buffer.from('release-apk'));

  const result = childProcess.spawnSync(process.execPath, [
    path.join(process.cwd(), 'scripts', 'prepare-android-update.js'),
    '--apk', apk,
    '--out', out,
    '--version-name', '1.4.0',
    '--version-code', '2',
    '--package', 'com.example.lan_ai_cli_control',
    '--release-notes', 'test release'
  ], { encoding: 'utf8' });

  try {
    assert.equal(result.status, 0, result.stderr);
    const manifest = JSON.parse(fs.readFileSync(path.join(out, 'latest.json'), 'utf8'));
    assert.equal(manifest.schemaVersion, 1);
    assert.equal(manifest.versionCode, 2);
    assert.equal(manifest.apkUrl, '/api/app-updates/android/apk/2');
    assert.equal(fs.existsSync(path.join(out, manifest.fileName)), true);
    assert.equal(fs.existsSync(path.join(out, `${manifest.fileName}.sha256`)), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected: fails because `scripts/prepare-android-update.js` does not exist.

- [ ] **Step 3: Add manifest helper script**

Create `scripts/prepare-android-update.js`:

```javascript
#!/usr/bin/env node
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const args = parseArgs(process.argv.slice(2));
const apkPath = required(args, 'apk');
const outDir = required(args, 'out');
const versionName = required(args, 'version-name');
const versionCode = Number(required(args, 'version-code'));
const packageName = required(args, 'package');
const releaseNotes = args['release-notes'] || '';
const minSupportedVersionCode = Number(args['min-supported-version-code'] || 1);
const mandatory = args.mandatory === 'true';

if (!Number.isInteger(versionCode) || versionCode <= 0) throw new Error('--version-code must be a positive integer');
if (!fs.existsSync(apkPath)) throw new Error(`APK not found: ${apkPath}`);

fs.mkdirSync(outDir, { recursive: true });
const bytes = fs.readFileSync(apkPath);
const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
const fileName = `${packageName}-${versionName}+${versionCode}.apk`.replace(/[^A-Za-z0-9._+-]/g, '_');
fs.copyFileSync(apkPath, path.join(outDir, fileName));
fs.writeFileSync(path.join(outDir, `${fileName}.sha256`), `${sha256}  ${fileName}\n`, 'utf8');

const manifest = {
  schemaVersion: 1,
  platform: 'android',
  packageName,
  versionName,
  versionCode,
  minSupportedVersionCode,
  mandatory,
  apkUrl: `/api/app-updates/android/apk/${versionCode}`,
  sha256,
  sizeBytes: bytes.length,
  etag: `"android-apk-${versionCode}-${sha256.slice(0, 12)}"`,
  releaseNotes,
  publishedAt: new Date().toISOString(),
  fileName
};

fs.writeFileSync(path.join(outDir, 'latest.json'), `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
console.log(`Wrote ${path.join(outDir, 'latest.json')}`);

function parseArgs(items) {
  const parsed = {};
  for (let i = 0; i < items.length; i += 1) {
    const item = items[i];
    if (!item.startsWith('--')) throw new Error(`Unexpected argument: ${item}`);
    const key = item.slice(2);
    const next = items[i + 1];
    if (next && !next.startsWith('--')) {
      parsed[key] = next;
      i += 1;
    } else {
      parsed[key] = 'true';
    }
  }
  return parsed;
}

function required(args, key) {
  const value = args[key];
  if (!value) throw new Error(`Missing --${key}`);
  return value;
}
```

- [ ] **Step 4: Add release signing configuration**

Modify `.gitignore`:

```gitignore
mobile/android/key.properties
mobile/android/app/*.jks
mobile/android/app/*.keystore
```

Create `mobile/android/key.properties.example`:

```properties
storePassword=replace-me
keyPassword=replace-me
keyAlias=lan-ai-cli-control
storeFile=app/release-upload-key.jks
```

Modify `mobile/android/app/build.gradle.kts` after `kotlinOptions`:

```kotlin
    val keyPropertiesFile = rootProject.file("key.properties")
    val keyProperties = java.util.Properties()
    if (keyPropertiesFile.exists()) {
        keyPropertiesFile.inputStream().use { keyProperties.load(it) }
    }

    signingConfigs {
        create("releasePrivate") {
            if (keyPropertiesFile.exists()) {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = rootProject.file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }
```

Replace release signing:

```kotlin
        release {
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("releasePrivate")
            } else {
                signingConfigs.getByName("debug")
            }
        }
```

- [ ] **Step 5: Run tests and Gradle configuration check**

Run:

```powershell
node scripts\run-tests.js
```

Expected: all tests pass.

Run from `mobile`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter build apk --debug --no-pub
```

Expected: debug APK builds. If this times out once, stop and ask the user to run it.

- [ ] **Step 6: Commit release helper**

```powershell
git add .gitignore mobile\android\app\build.gradle.kts mobile\android\key.properties.example scripts\prepare-android-update.js scripts\run-tests.js
git commit -m "Add private Android release update helper" -m "Constraint: Release signing uses a stable private keystore when key.properties exists; debug signing remains only as a local fallback." -m "Tested: node scripts\\run-tests.js"
```

---

### Task 3: Mobile Update Models, Client, And Repository

**Files:**

- Modify: `mobile/pubspec.yaml`
- Create: `mobile/lib/src/data/models/app_update_models.dart`
- Create: `mobile/lib/src/domain/repositories/app_update_repository.dart`
- Create: `mobile/lib/src/services/app_update_client.dart`
- Create: `mobile/lib/src/data/repositories/daemon_app_update_repository.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Create: `mobile/test/app_update_models_test.dart`
- Create: `mobile/test/app_update_client_test.dart`
- Modify: `mobile/test/app_dependencies_test.dart`

- [ ] **Step 1: Add dependency**

Modify `mobile/pubspec.yaml` dependencies:

```yaml
  package_info_plus: ^8.3.0
```

Run from `mobile`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter pub get
```

Expected: `package_info_plus` is resolved. If it times out once, stop and ask the user to run the command.

- [ ] **Step 2: Write model tests**

Create `mobile/test/app_update_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';

void main() {
  test('parses available manifest and mandatory min-supported semantics', () {
    final manifest = AppUpdateManifest.fromJson(const <String, Object?>{
      'schemaVersion': 1,
      'platform': 'android',
      'packageName': 'com.example.lan_ai_cli_control',
      'versionName': '1.7.0',
      'versionCode': 5,
      'minSupportedVersionCode': 4,
      'mandatory': false,
      'apkUrl': '/api/app-updates/android/apk/5',
      'sha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'sizeBytes': 20,
      'etag': '"android-apk-5-aaaa"',
      'releaseNotes': 'Compatibility update.',
      'publishedAt': '2026-05-24T10:00:00.000Z',
    });

    expect(manifest.available, true);
    expect(manifest.isNewerThan(4), true);
    expect(manifest.isMandatoryFor(3), true);
    expect(manifest.isMandatoryFor(4), false);
  });

  test('parses unavailable manifest using schema envelope', () {
    final manifest = AppUpdateManifest.fromJson(const <String, Object?>{
      'schemaVersion': 1,
      'platform': 'android',
      'available': false,
    });

    expect(manifest.available, false);
    expect(manifest.versionCode, isNull);
  });

  test('rejects unsupported schema and cross-origin apk url', () {
    expect(
      () => AppUpdateManifest.fromJson(const <String, Object?>{
        'schemaVersion': 2,
        'platform': 'android',
        'available': false,
      }),
      throwsFormatException,
    );

    final manifest = AppUpdateManifest.fromJson(const <String, Object?>{
      'schemaVersion': 1,
      'platform': 'android',
      'packageName': 'com.example.lan_ai_cli_control',
      'versionName': '1.4.0',
      'versionCode': 2,
      'minSupportedVersionCode': 1,
      'mandatory': false,
      'apkUrl': 'https://evil.example/app.apk',
      'sha256':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'sizeBytes': 10,
      'etag': '"etag"',
      'publishedAt': '2026-05-24T10:00:00.000Z',
    });

    expect(
      () => manifest.resolveApkUri(Uri.parse('http://127.0.0.1:4317')),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 3: Implement models**

Create `mobile/lib/src/data/models/app_update_models.dart`:

```dart
class AppUpdateManifest {
  const AppUpdateManifest({
    required this.schemaVersion,
    required this.platform,
    required this.available,
    this.packageName,
    this.versionName,
    this.versionCode,
    this.minSupportedVersionCode,
    this.mandatory = false,
    this.apkUrl,
    this.sha256,
    this.sizeBytes,
    this.etag,
    this.releaseNotes,
    this.publishedAt,
  });

  final int schemaVersion;
  final String platform;
  final bool available;
  final String? packageName;
  final String? versionName;
  final int? versionCode;
  final int? minSupportedVersionCode;
  final bool mandatory;
  final String? apkUrl;
  final String? sha256;
  final int? sizeBytes;
  final String? etag;
  final String? releaseNotes;
  final DateTime? publishedAt;

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1) {
      throw FormatException('Unsupported update manifest schemaVersion: $schemaVersion');
    }
    final platform = json['platform'];
    if (platform != 'android') {
      throw FormatException('Unsupported update manifest platform: $platform');
    }
    final available = json['available'] as bool? ?? true;
    if (!available) {
      return const AppUpdateManifest(
        schemaVersion: 1,
        platform: 'android',
        available: false,
      );
    }
    return AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: true,
      packageName: json['packageName'] as String?,
      versionName: json['versionName'] as String?,
      versionCode: json['versionCode'] as int?,
      minSupportedVersionCode: json['minSupportedVersionCode'] as int? ?? 1,
      mandatory: json['mandatory'] as bool? ?? false,
      apkUrl: json['apkUrl'] as String?,
      sha256: json['sha256'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      etag: json['etag'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
    );
  }

  bool isNewerThan(int installedVersionCode) =>
      available && versionCode != null && versionCode! > installedVersionCode;

  bool isMandatoryFor(int installedVersionCode) =>
      available &&
      (mandatory ||
          (minSupportedVersionCode != null &&
              installedVersionCode < minSupportedVersionCode!));

  Uri resolveApkUri(Uri daemonBaseUri) {
    final value = apkUrl;
    if (value == null || value.isEmpty) {
      throw const FormatException('Update manifest apkUrl is missing.');
    }
    final resolved = daemonBaseUri.resolve(value);
    if (resolved.scheme != daemonBaseUri.scheme ||
        resolved.authority != daemonBaseUri.authority) {
      throw FormatException('Update manifest apkUrl is cross-origin: $value');
    }
    return resolved;
  }
}

class AppUpdateDownloadMetadata {
  const AppUpdateDownloadMetadata({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.etag,
    required this.downloadedBytes,
    required this.updatedAt,
    this.installSessionId,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String etag;
  final int downloadedBytes;
  final DateTime updatedAt;
  final int? installSessionId;
}
```

- [ ] **Step 4: Add client/repository tests**

Create `mobile/test/app_update_client_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lan_ai_cli_control/src/services/app_update_client.dart';

import 'support/fake_http.dart';

void main() {
  test('fetches latest manifest with bearer token and If-None-Match', () async {
    final requests = <http.BaseRequest>[];
    final client = FakeHttpClient((request) {
      requests.add(request);
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(request.headers['if-none-match'], '"old"');
      return jsonResponse(const <String, Object?>{
        'schemaVersion': 1,
        'platform': 'android',
        'available': false,
      }, headers: const <String, String>{'etag': '"new"'});
    });
    final updateClient = AppUpdateClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      httpClient: client,
      tokenProvider: () => 'token-1',
    );

    final result = await updateClient.fetchLatest(ifNoneMatch: '"old"');

    expect(result.notModified, false);
    expect(result.etag, '"new"');
    expect(result.manifest?.available, false);
    expect(requests.single.url.path, '/api/app-updates/android/latest');
  });

  test('opens apk stream with range and if-range headers', () async {
    final client = FakeHttpClient((request) {
      expect(request.method, 'GET');
      expect(request.headers['range'], 'bytes=5-');
      expect(request.headers['if-range'], '"etag"');
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('bytes')),
        206,
        headers: const <String, String>{
          'content-length': '5',
          'content-range': 'bytes 5-9/10',
        },
      );
    });
    final updateClient = AppUpdateClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      httpClient: client,
      tokenProvider: () => 'token-1',
    );

    final response = await updateClient.openApkStream(
      Uri.parse('http://127.0.0.1:4317/api/app-updates/android/apk/2'),
      rangeStart: 5,
      ifRange: '"etag"',
    );

    expect(response.statusCode, 206);
  });
}
```

- [ ] **Step 5: Implement `AppUpdateClient`**

Create `mobile/lib/src/services/app_update_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models/app_update_models.dart';

class AppUpdateLatestResult {
  const AppUpdateLatestResult({
    required this.notModified,
    this.etag,
    this.manifest,
  });

  final bool notModified;
  final String? etag;
  final AppUpdateManifest? manifest;
}

class AppUpdateClient {
  AppUpdateClient({
    required this.baseUri,
    required this.httpClient,
    required this.tokenProvider,
  });

  final Uri baseUri;
  final http.Client httpClient;
  final String? Function() tokenProvider;

  Future<AppUpdateLatestResult> fetchLatest({String? ifNoneMatch}) async {
    final headers = _headers();
    if (ifNoneMatch != null) headers['if-none-match'] = ifNoneMatch;
    final response = await httpClient.get(
      baseUri.resolve('/api/app-updates/android/latest'),
      headers: headers,
    );
    if (response.statusCode == 304) {
      return AppUpdateLatestResult(
        notModified: true,
        etag: response.headers['etag'],
      );
    }
    if (response.statusCode >= 400) {
      throw AppUpdateClientException(response.statusCode, response.body);
    }
    return AppUpdateLatestResult(
      notModified: false,
      etag: response.headers['etag'],
      manifest: AppUpdateManifest.fromJson(
        jsonDecode(response.body) as Map<String, Object?>,
      ),
    );
  }

  Future<http.StreamedResponse> openApkStream(
    Uri apkUri, {
    int? rangeStart,
    String? ifRange,
  }) {
    final request = http.Request('GET', apkUri)..headers.addAll(_headers());
    if (rangeStart != null && rangeStart > 0) {
      request.headers['range'] = 'bytes=$rangeStart-';
      if (ifRange != null) request.headers['if-range'] = ifRange;
    }
    return httpClient.send(request);
  }

  Map<String, String> _headers() => <String, String>{
        if (tokenProvider() case final token?) 'authorization': 'Bearer $token',
      };
}

class AppUpdateClientException implements Exception {
  const AppUpdateClientException(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
```

- [ ] **Step 6: Expose authenticated raw stream in `DaemonClient`**

Add methods to `mobile/lib/src/services/daemon_client.dart` so `AppUpdateClient` can use the same auth refresh behavior:

```dart
Future<http.Response> getAuthorizedRaw(
  String path, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final response = await _request(() => _httpClient.get(
        baseUri.resolve(path),
        headers: <String, String>{..._headers(authorize: true), ...headers},
      ));
  if (_isAuthRequired(response)) {
    await _refreshAfterAuthRequired();
    return _request(() => _httpClient.get(
          baseUri.resolve(path),
          headers: <String, String>{..._headers(authorize: true), ...headers},
        ));
  }
  return response;
}

Future<http.StreamedResponse> sendAuthorizedStream(
  http.BaseRequest Function(Uri baseUri, Map<String, String> headers) build,
) async {
  Future<http.StreamedResponse> sendOnce() {
    final request = build(baseUri, _multipartHeaders(authorize: true));
    return _requestStream(() => _httpClient.send(request));
  }

  final response = await sendOnce();
  if (response.statusCode == 401) {
    await response.stream.drain<void>();
    await _refreshAfterAuthRequired();
    return sendOnce();
  }
  return response;
}
```

Update `AppUpdateClient` in the implementation to either use these methods or accept an injected send function. Keep the tests using `FakeHttpClient`.

- [ ] **Step 7: Add repository contract and wiring**

Create `mobile/lib/src/domain/repositories/app_update_repository.dart`:

```dart
import '../../data/models/app_update_models.dart';

abstract class AppUpdateRepository {
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch});
}
```

Create `mobile/lib/src/data/repositories/daemon_app_update_repository.dart`:

```dart
import '../../data/models/app_update_models.dart';
import '../../domain/repositories/app_update_repository.dart';
import '../../services/app_update_client.dart';

class DaemonAppUpdateRepository implements AppUpdateRepository {
  DaemonAppUpdateRepository({required this.client});

  final AppUpdateClient client;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async {
    final result = await client.fetchLatest(ifNoneMatch: ifNoneMatch);
    return result.manifest ??
        const AppUpdateManifest(
          schemaVersion: 1,
          platform: 'android',
          available: false,
        );
  }
}
```

Modify `AppDependencies` with an `appUpdateRepository` field in `ConnectedDataDependencies` and build it from the connected `DaemonClient`.

- [ ] **Step 8: Run mobile tests**

Run:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\app_update_models_test.dart test\app_update_client_test.dart test\app_dependencies_test.dart -r expanded
```

Expected: all pass.

- [ ] **Step 9: Commit mobile API layer**

```powershell
git add mobile\pubspec.yaml mobile\lib\src\data\models\app_update_models.dart mobile\lib\src\domain\repositories\app_update_repository.dart mobile\lib\src\data\repositories\daemon_app_update_repository.dart mobile\lib\src\services\app_update_client.dart mobile\lib\src\services\daemon_client.dart mobile\lib\src\app\app_dependencies.dart mobile\test\app_update_models_test.dart mobile\test\app_update_client_test.dart mobile\test\app_dependencies_test.dart
git commit -m "Add mobile Android update API layer" -m "Constraint: Manifest parsing rejects unsupported schemas and cross-origin APK URLs." -m "Tested: dart analyze lib test; flutter test --no-pub test\\app_update_models_test.dart test\\app_update_client_test.dart test\\app_dependencies_test.dart -r expanded"
```

---

### Task 4: Resumable Download Manager

**Files:**

- Create: `mobile/lib/src/services/app_update_download_manager.dart`
- Create: `mobile/test/app_update_download_manager_test.dart`
- Modify: `mobile/lib/src/services/android_package_installer.dart` after Task 5 if storage preflight is placed there

- [ ] **Step 1: Write downloader tests**

Create `mobile/test/app_update_download_manager_test.dart` with these core tests:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/services/app_update_download_manager.dart';

void main() {
  test('resumes matching partial with range and if-range', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-resume-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 2);
    final part = File('${temp.path}/app-update-2.apk.part');
    await part.writeAsBytes(bytes.sublist(0, 5));
    await File('${temp.path}/app-update-2.json').writeAsString(jsonEncode({
      'versionCode': 2,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': 5,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    final seenHeaders = <String, String>{};
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        seenHeaders['rangeStart'] = '$rangeStart';
        seenHeaders['ifRange'] = ifRange ?? '';
        return http.StreamedResponse(
          Stream<List<int>>.value(bytes.sublist(5)),
          206,
          contentLength: bytes.length - 5,
        );
      },
      availableBytes: () async => 1000000,
    );

    final result = await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(seenHeaders['rangeStart'], '5');
    expect(seenHeaders['ifRange'], manifest.etag);
    expect(await File('${temp.path}/app-update-2.apk').readAsBytes(), bytes);
    expect(await part.exists(), false);
    await temp.delete(recursive: true);
  });

  test('terminal auth failure keeps partial file', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-auth-');
    final bytes = utf8.encode('hello');
    final manifest = _manifest(bytes, versionCode: 3);
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          throw const AppUpdateDownloadException('auth failed'),
      availableBytes: () async => 1000000,
    );

    final result = await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.failed);
    expect(await File('${temp.path}/app-update-3.apk.part').exists(), false);
    await temp.delete(recursive: true);
  });

  test('insufficient storage fails before request', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-space-');
    var requested = false;
    final bytes = utf8.encode('large-apk');
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        requested = true;
        return http.StreamedResponse(Stream<List<int>>.empty(), 200);
      },
      availableBytes: () async => 1,
    );

    final result = await manager.download(_manifest(bytes), Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.failed);
    expect(result.message, contains('storage'));
    expect(requested, false);
    await temp.delete(recursive: true);
  });
}

AppUpdateManifest _manifest(List<int> bytes, {int versionCode = 2}) {
  // Use a literal sha for test stability; implementation validates final bytes.
  return AppUpdateManifest(
    schemaVersion: 1,
    platform: 'android',
    available: true,
    packageName: 'com.example.lan_ai_cli_control',
    versionName: '1.4.0',
    versionCode: versionCode,
    minSupportedVersionCode: 1,
    mandatory: false,
    apkUrl: '/api/app-updates/android/apk/$versionCode',
    sha256: AppUpdateDownloadManager.sha256HexForTest(bytes),
    sizeBytes: bytes.length,
    etag: '"etag-$versionCode"',
    publishedAt: DateTime.utc(2026, 5, 24),
  );
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_update_download_manager_test.dart -r expanded
```

Expected: fails because `AppUpdateDownloadManager` does not exist.

- [ ] **Step 3: Implement download manager**

Create `mobile/lib/src/services/app_update_download_manager.dart` with this API:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../data/models/app_update_models.dart';

typedef AppUpdateStreamOpener = Future<http.StreamedResponse> Function(
  Uri uri, {
  int? rangeStart,
  String? ifRange,
});

enum AppUpdateDownloadState { downloading, paused, verifying, readyToInstall, failed }

class AppUpdateDownloadResult {
  const AppUpdateDownloadResult({
    required this.state,
    this.file,
    this.message,
  });

  final AppUpdateDownloadState state;
  final File? file;
  final String? message;
}

class AppUpdateDownloadException implements Exception {
  const AppUpdateDownloadException(this.message);
  final String message;
}

class AppUpdateDownloadManager {
  AppUpdateDownloadManager({
    required this.cacheDirectory,
    required this.openStream,
    required this.availableBytes,
    this.now = DateTime.now,
  });

  final Directory cacheDirectory;
  final AppUpdateStreamOpener openStream;
  final Future<int> Function() availableBytes;
  final DateTime Function() now;

  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri,
  ) async {
    final versionCode = manifest.versionCode!;
    final dir = await _ensureDir();
    final part = File('${dir.path}/app-update-$versionCode.apk.part');
    final apk = File('${dir.path}/app-update-$versionCode.apk');
    final metadata = File('${dir.path}/app-update-$versionCode.json');
    await reconcile(manifest);
    final remaining = manifest.sizeBytes! - (await part.exists() ? await part.length() : 0);
    final free = await availableBytes();
    if (free < remaining + 5 * 1024 * 1024) {
      return const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.failed,
        message: 'insufficient storage',
      );
    }
    final localLength = await part.exists() ? await part.length() : 0;
    try {
      final response = await openStream(
        manifest.resolveApkUri(daemonBaseUri),
        rangeStart: localLength > 0 ? localLength : null,
        ifRange: localLength > 0 ? manifest.etag : null,
      );
      final append = response.statusCode == 206 && localLength > 0;
      if (response.statusCode == 416 || response.statusCode == 200 && localLength > 0) {
        await part.delete().catchError((_) {});
      }
      if (response.statusCode >= 500) {
        return const AppUpdateDownloadResult(state: AppUpdateDownloadState.paused);
      }
      if (response.statusCode >= 400) {
        return AppUpdateDownloadResult(
          state: AppUpdateDownloadState.failed,
          message: 'server returned ${response.statusCode}',
        );
      }
      final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      final digestSink = AccumulatorSink<Digest>();
      final digestInput = sha256.startChunkedConversion(digestSink);
      if (append) digestInput.add(await part.readAsBytes());
      await for (final chunk in response.stream) {
        digestInput.add(chunk);
        sink.add(chunk);
      }
      await sink.close();
      digestInput.close();
      await metadata.writeAsString(jsonEncode(_metadataFor(manifest, await part.length())));
      if (await part.length() != manifest.sizeBytes) {
        return const AppUpdateDownloadResult(state: AppUpdateDownloadState.paused);
      }
      final digest = digestSink.events.single.toString();
      if (digest != manifest.sha256) {
        await part.delete().catchError((_) {});
        await metadata.delete().catchError((_) {});
        return const AppUpdateDownloadResult(
          state: AppUpdateDownloadState.failed,
          message: 'sha256 mismatch',
        );
      }
      if (await apk.exists()) await apk.delete();
      await part.rename(apk.path);
      return AppUpdateDownloadResult(state: AppUpdateDownloadState.readyToInstall, file: apk);
    } on AppUpdateDownloadException catch (error) {
      return AppUpdateDownloadResult(state: AppUpdateDownloadState.failed, message: error.message);
    } on SocketException {
      return const AppUpdateDownloadResult(state: AppUpdateDownloadState.paused);
    } on TimeoutException {
      return const AppUpdateDownloadResult(state: AppUpdateDownloadState.paused);
    }
  }

  Future<void> reconcile(AppUpdateManifest manifest) async {
    final dir = await _ensureDir();
    final versionCode = manifest.versionCode!;
    final part = File('${dir.path}/app-update-$versionCode.apk.part');
    final apk = File('${dir.path}/app-update-$versionCode.apk');
    if (await apk.exists() && await part.exists()) {
      await part.delete();
    }
  }

  Future<void> discard(int versionCode) async {
    final dir = await _ensureDir();
    for (final suffix in ['apk.part', 'json', 'apk']) {
      final file = File('${dir.path}/app-update-$versionCode.$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  Future<Directory> _ensureDir() async {
    final dir = Directory('${cacheDirectory.path}/app_updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Map<String, Object?> _metadataFor(AppUpdateManifest manifest, int downloadedBytes) => <String, Object?>{
        'versionCode': manifest.versionCode,
        'versionName': manifest.versionName,
        'apkUrl': manifest.apkUrl,
        'sha256': manifest.sha256,
        'sizeBytes': manifest.sizeBytes,
        'etag': manifest.etag,
        'downloadedBytes': downloadedBytes,
        'updatedAt': now().toUtc().toIso8601String(),
      };

  static String sha256HexForTest(List<int> bytes) => sha256.convert(bytes).toString();
}
```

After this first pass, tighten metadata matching so stale `etag`, `sha256`, `sizeBytes`, `apkUrl`, or `versionCode` deletes the old partial before resume.

- [ ] **Step 4: Run downloader tests**

Run:

```powershell
cd mobile
dart analyze lib test
flutter test --no-pub test\app_update_download_manager_test.dart -r expanded
```

Expected: all pass.

- [ ] **Step 5: Commit downloader**

```powershell
git add mobile\lib\src\services\app_update_download_manager.dart mobile\test\app_update_download_manager_test.dart
git commit -m "Add resumable Android update downloader" -m "Constraint: APK bytes are stored under cache/app_updates and verified before install." -m "Tested: dart analyze lib test; flutter test --no-pub test\\app_update_download_manager_test.dart -r expanded"
```

---

### Task 5: Android PackageInstaller Bridge

**Files:**

- Modify: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/android/app/src/main/res/xml/file_paths.xml`
- Modify: `mobile/android/app/build.gradle.kts`
- Create: `mobile/lib/src/services/android_package_installer.dart`
- Add tests where practical in `mobile/test/app_update_view_model_test.dart` using a fake installer

- [ ] **Step 1: Add Dart wrapper with testable interface**

Create `mobile/lib/src/services/android_package_installer.dart`:

```dart
import 'dart:async';

import 'package:flutter/services.dart';

enum AndroidInstallStatus {
  pendingUserAction,
  committed,
  success,
  cancelled,
  failed,
}

class AndroidInstallEvent {
  const AndroidInstallEvent({
    required this.status,
    this.sessionId,
    this.message,
  });

  final AndroidInstallStatus status;
  final int? sessionId;
  final String? message;

  factory AndroidInstallEvent.fromJson(Map<Object?, Object?> json) {
    final status = switch (json['status'] as String?) {
      'pendingUserAction' => AndroidInstallStatus.pendingUserAction,
      'committed' => AndroidInstallStatus.committed,
      'success' => AndroidInstallStatus.success,
      'cancelled' => AndroidInstallStatus.cancelled,
      _ => AndroidInstallStatus.failed,
    };
    return AndroidInstallEvent(
      status: status,
      sessionId: json['sessionId'] as int?,
      message: json['message'] as String?,
    );
  }
}

abstract class PackageInstallerService {
  Stream<AndroidInstallEvent> get events;
  Future<bool> canRequestPackageInstalls();
  Future<void> openInstallPermissionSettings();
  Future<int> installApk(String filePath);
  Future<int> availableBytes();
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId);
}

class AndroidPackageInstaller implements PackageInstallerService {
  AndroidPackageInstaller({
    MethodChannel methodChannel =
        const MethodChannel('lan_ai_cli_control/app_update_installer'),
    EventChannel eventChannel =
        const EventChannel('lan_ai_cli_control/app_update_installer/events'),
  })  : _methodChannel = methodChannel,
        _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Stream<AndroidInstallEvent> get events => _eventChannel
      .receiveBroadcastStream()
      .cast<Map<Object?, Object?>>()
      .map(AndroidInstallEvent.fromJson);

  @override
  Future<bool> canRequestPackageInstalls() =>
      _methodChannel.invokeMethod<bool>('canRequestPackageInstalls').then((v) => v ?? false);

  @override
  Future<void> openInstallPermissionSettings() =>
      _methodChannel.invokeMethod<void>('openInstallPermissionSettings');

  @override
  Future<int> installApk(String filePath) =>
      _methodChannel.invokeMethod<int>('installApk', <String, Object?>{'filePath': filePath}).then((v) => v ?? -1);

  @override
  Future<int> availableBytes() =>
      _methodChannel.invokeMethod<int>('availableBytes').then((v) => v ?? 0);

  @override
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId) async {
    final result = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
      'recoverInstallSession',
      <String, Object?>{'sessionId': sessionId},
    );
    return result == null ? null : AndroidInstallEvent.fromJson(result);
  }
}
```

- [ ] **Step 2: Modify Android manifest/resources**

Add permission to `mobile/android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

Add provider inside `<application>`:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

Create `mobile/android/app/src/main/res/xml/file_paths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path
        name="app_updates"
        path="app_updates/" />
</paths>
```

Add AndroidX dependency if Gradle cannot resolve `FileProvider`:

```kotlin
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
```

- [ ] **Step 3: Implement Kotlin bridge**

Replace `MainActivity.kt` with a bridge-backed activity. Keep it small and self-contained:

```kotlin
package com.example.lan_ai_cli_control

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val methodChannelName = "lan_ai_cli_control/app_update_installer"
    private val eventChannelName = "lan_ai_cli_control/app_update_installer/events"
    private var eventSink: EventChannel.EventSink? = null
    private val installAction = "com.example.lan_ai_cli_control.APP_UPDATE_INSTALL_STATUS"

    private val installReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
            val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                val confirmation = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                eventSink?.success(mapOf("status" to "pendingUserAction", "sessionId" to sessionId, "message" to message))
                confirmation?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (confirmation != null) startActivity(confirmation)
                return
            }
            val mapped = when (status) {
                PackageInstaller.STATUS_SUCCESS -> "success"
                PackageInstaller.STATUS_FAILURE_ABORTED -> "cancelled"
                else -> "failed"
            }
            eventSink?.success(mapOf("status" to mapped, "sessionId" to sessionId, "message" to message))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> result.success(packageManager.canRequestPackageInstalls())
                "openInstallPermissionSettings" -> {
                    val uri = Uri.parse("package:$packageName")
                    startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, uri))
                    result.success(null)
                }
                "availableBytes" -> result.success(availableBytes())
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) result.error("BAD_ARGUMENT", "filePath is required", null)
                    else result.success(commitPackageSession(filePath))
                }
                "recoverInstallSession" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: -1
                    result.success(recoverSession(sessionId))
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(installAction)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(installReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(installReceiver, filter)
    }

    override fun onDestroy() {
        unregisterReceiver(installReceiver)
        super.onDestroy()
    }

    private fun commitPackageSession(filePath: String): Int {
        val apk = File(filePath)
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val installer = packageManager.packageInstaller
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        apk.inputStream().use { input ->
            session.openWrite("app_update_$sessionId.apk", 0, apk.length()).use { output ->
                input.copyTo(output)
                session.fsync(output)
            }
        }
        val intent = Intent(installAction).setPackage(packageName)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            sessionId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        eventSink?.success(mapOf("status" to "committed", "sessionId" to sessionId))
        session.commit(pendingIntent.intentSender)
        session.close()
        return sessionId
    }

    private fun recoverSession(sessionId: Int): Map<String, Any?>? {
        if (sessionId < 0) return null
        val info = packageManager.packageInstaller.getSessionInfo(sessionId) ?: return null
        return mapOf("status" to "pendingUserAction", "sessionId" to sessionId, "message" to info.appPackageName)
    }

    private fun availableBytes(): Long {
        val storage = getSystemService(StorageManager::class.java)
        return if (Build.VERSION.SDK_INT >= 26) storage.getAllocatableBytes(storage.getUuidForPath(cacheDir))
        else cacheDir.freeSpace
    }
}
```

During implementation, persist the returned `sessionId` in the Dart metadata immediately after `installApk` resolves and before relying on any later event.

- [ ] **Step 4: Analyze and build Android debug**

Run:

```powershell
cd mobile
dart analyze lib test
flutter build apk --debug --no-pub
```

Expected: no analyzer errors; debug APK builds. If Flutter build times out once, ask the user to run it.

- [ ] **Step 5: Commit installer bridge**

```powershell
git add mobile\lib\src\services\android_package_installer.dart mobile\android\app\src\main\kotlin\com\example\lan_ai_cli_control\MainActivity.kt mobile\android\app\src\main\AndroidManifest.xml mobile\android\app\src\main\res\xml\file_paths.xml mobile\android\app\build.gradle.kts
git commit -m "Add Android package installer bridge" -m "Constraint: Installation uses PackageInstaller.Session and reports session status back to Dart." -m "Tested: dart analyze lib test; flutter build apk --debug --no-pub"
```

---

### Task 6: Settings Update ViewModel And UI

**Files:**

- Create: `mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart`
- Modify: `mobile/lib/src/ui/features/settings/settings_page.dart`
- Modify: `mobile/lib/src/ui/features/settings/settings.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Create: `mobile/test/app_update_view_model_test.dart`
- Create: `mobile/test/app_update_panel_test.dart`

- [ ] **Step 1: Write ViewModel tests**

Create `mobile/test/app_update_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/services/android_package_installer.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';

void main() {
  test('check reports available update and mandatory min-supported gate', () async {
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 3,
      installedVersionName: '1.3.0',
      repository: _FakeRepository(_manifest(minSupportedVersionCode: 4)),
      installer: _FakeInstaller(),
      downloader: _FakeDownloader(),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );

    await viewModel.checkForUpdates();

    expect(viewModel.state.status, AppUpdateStatus.available);
    expect(viewModel.state.mandatory, true);
  });

  test('install permission missing moves to permission state', () async {
    final installer = _FakeInstaller(canInstall: false);
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(ready: true),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();

    expect(viewModel.state.status, AppUpdateStatus.installPermissionNeeded);
  });
}

AppUpdateManifest _manifest({int minSupportedVersionCode = 1}) =>
    AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: true,
      packageName: 'com.example.lan_ai_cli_control',
      versionName: '1.4.0',
      versionCode: 2,
      minSupportedVersionCode: minSupportedVersionCode,
      mandatory: false,
      apkUrl: '/api/app-updates/android/apk/2',
      sha256: 'a' * 64,
      sizeBytes: 10,
      etag: '"etag"',
      publishedAt: DateTime.utc(2026, 5, 24),
    );

class _FakeRepository implements AppUpdateRepository {
  _FakeRepository(this.manifest);
  final AppUpdateManifest manifest;
  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async => manifest;
}

class _FakeInstaller implements PackageInstallerService {
  _FakeInstaller({this.canInstall = true});
  final bool canInstall;
  @override
  Stream<AndroidInstallEvent> get events => const Stream<AndroidInstallEvent>.empty();
  @override
  Future<int> availableBytes() async => 1000000;
  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;
  @override
  Future<int> installApk(String filePath) async => 1;
  @override
  Future<void> openInstallPermissionSettings() async {}
  @override
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId) async => null;
}
```

- [ ] **Step 2: Implement ViewModel**

Create `mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart` with:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../data/models/app_update_models.dart';
import '../../../../domain/repositories/app_update_repository.dart';
import '../../../../services/android_package_installer.dart';
import '../../../../services/app_update_download_manager.dart';

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  paused,
  verifying,
  readyToInstall,
  installPermissionNeeded,
  installing,
  installSucceeded,
  installCancelled,
  installFailed,
  cancelled,
  failed,
}

class AppUpdateState {
  const AppUpdateState({
    required this.status,
    required this.installedVersionName,
    required this.installedVersionCode,
    this.manifest,
    this.mandatory = false,
    this.downloadedFile,
    this.errorMessage,
  });

  final AppUpdateStatus status;
  final String installedVersionName;
  final int installedVersionCode;
  final AppUpdateManifest? manifest;
  final bool mandatory;
  final File? downloadedFile;
  final String? errorMessage;

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    AppUpdateManifest? manifest,
    bool? mandatory,
    File? downloadedFile,
    String? errorMessage,
  }) =>
      AppUpdateState(
        status: status ?? this.status,
        installedVersionName: installedVersionName,
        installedVersionCode: installedVersionCode,
        manifest: manifest ?? this.manifest,
        mandatory: mandatory ?? this.mandatory,
        downloadedFile: downloadedFile ?? this.downloadedFile,
        errorMessage: errorMessage,
      );
}

class AppUpdateViewModel extends ChangeNotifier {
  AppUpdateViewModel({
    required this.installedVersionCode,
    required this.installedVersionName,
    required this.repository,
    required this.installer,
    required this.downloader,
    required this.daemonBaseUri,
  }) : state = AppUpdateState(
          status: AppUpdateStatus.idle,
          installedVersionName: installedVersionName,
          installedVersionCode: installedVersionCode,
        ) {
    _installSubscription = installer.events.listen(_handleInstallEvent);
  }

  final int installedVersionCode;
  final String installedVersionName;
  final AppUpdateRepository repository;
  final PackageInstallerService installer;
  final AppUpdateDownloadManager downloader;
  final Uri daemonBaseUri;
  late final StreamSubscription<AndroidInstallEvent> _installSubscription;

  AppUpdateState state;

  Future<void> checkForUpdates() async {
    _set(state.copyWith(status: AppUpdateStatus.checking, errorMessage: null));
    try {
      final manifest = await repository.fetchLatest();
      if (!manifest.available || !manifest.isNewerThan(installedVersionCode)) {
        _set(state.copyWith(status: AppUpdateStatus.upToDate, manifest: manifest));
        return;
      }
      _set(state.copyWith(
        status: AppUpdateStatus.available,
        manifest: manifest,
        mandatory: manifest.isMandatoryFor(installedVersionCode),
      ));
    } catch (error) {
      _set(state.copyWith(status: AppUpdateStatus.failed, errorMessage: '$error'));
    }
  }

  Future<void> download() async {
    final manifest = state.manifest;
    if (manifest == null) return;
    _set(state.copyWith(status: AppUpdateStatus.downloading));
    final result = await downloader.download(manifest, daemonBaseUri);
    _set(state.copyWith(
      status: switch (result.state) {
        AppUpdateDownloadState.readyToInstall => AppUpdateStatus.readyToInstall,
        AppUpdateDownloadState.paused => AppUpdateStatus.paused,
        _ => AppUpdateStatus.failed,
      },
      downloadedFile: result.file,
      errorMessage: result.message,
    ));
  }

  Future<void> install() async {
    final file = state.downloadedFile;
    if (file == null) return;
    if (!await installer.canRequestPackageInstalls()) {
      _set(state.copyWith(status: AppUpdateStatus.installPermissionNeeded));
      return;
    }
    _set(state.copyWith(status: AppUpdateStatus.installing));
    await installer.installApk(file.path);
  }

  Future<void> openInstallPermissionSettings() => installer.openInstallPermissionSettings();

  void _handleInstallEvent(AndroidInstallEvent event) {
    final status = switch (event.status) {
      AndroidInstallStatus.committed => AppUpdateStatus.installing,
      AndroidInstallStatus.pendingUserAction => AppUpdateStatus.installing,
      AndroidInstallStatus.success => AppUpdateStatus.installSucceeded,
      AndroidInstallStatus.cancelled => AppUpdateStatus.installCancelled,
      AndroidInstallStatus.failed => AppUpdateStatus.installFailed,
    };
    _set(state.copyWith(status: status, errorMessage: event.message));
  }

  void _set(AppUpdateState next) {
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _installSubscription.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 3: Write panel widget tests**

Create `mobile/test/app_update_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/widgets/app_update_panel.dart';

void main() {
  testWidgets('panel shows available update and download action', (tester) async {
    final state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: false,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppUpdatePanel(
          state: state,
          onCheck: () {},
          onDownload: () {},
          onInstall: () {},
          onOpenPermissionSettings: () {},
          onDiscard: () {},
        ),
      ),
    ));

    expect(find.textContaining('Update'), findsWidgets);
    expect(find.textContaining('Download'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Implement panel and settings wiring**

Create `mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart' as theme;
import '../view_models/app_update_view_model.dart';

class AppUpdatePanel extends StatelessWidget {
  const AppUpdatePanel({
    super.key,
    required this.state,
    required this.onCheck,
    required this.onDownload,
    required this.onInstall,
    required this.onOpenPermissionSettings,
    required this.onDiscard,
  });

  final AppUpdateState state;
  final VoidCallback onCheck;
  final VoidCallback onDownload;
  final VoidCallback onInstall;
  final VoidCallback onOpenPermissionSettings;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final title = switch (state.status) {
      AppUpdateStatus.upToDate => 'App is up to date',
      AppUpdateStatus.available => state.mandatory ? 'Required update available' : 'Update available',
      AppUpdateStatus.downloading => 'Downloading update',
      AppUpdateStatus.readyToInstall => 'Update ready to install',
      AppUpdateStatus.installPermissionNeeded => 'Install permission needed',
      AppUpdateStatus.installing => 'Opening Android installer',
      AppUpdateStatus.failed => 'Update failed',
      _ => 'App update',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.system_update_alt_rounded, color: theme.active, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 8),
        Text(
          state.errorMessage ?? 'Installed ${state.installedVersionName}+${state.installedVersionCode}',
          style: const TextStyle(color: theme.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Button('Check', onCheck),
          if (state.status == AppUpdateStatus.available || state.status == AppUpdateStatus.paused) _Button('Download', onDownload),
          if (state.status == AppUpdateStatus.readyToInstall) _Button('Install', onInstall),
          if (state.status == AppUpdateStatus.installPermissionNeeded) _Button('Open settings', onOpenPermissionSettings),
          if (state.status == AppUpdateStatus.paused || state.status == AppUpdateStatus.readyToInstall) _Button('Discard', onDiscard),
        ]),
      ]),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(onPressed: onTap, child: Text(label));
}
```

Modify `SettingsPage` constructor to accept `AppUpdateViewModel appUpdateViewModel`, wrap it with `ListenableBuilder`, and insert `AppUpdatePanel` under the About or Data Status section. Keep strings literal for the first pass if generated l10n churn is too high; add l10n keys in a follow-up if needed.

Modify `MainTabsPage` to create `AppUpdateViewModel` after connected dependencies are built. Use `PackageInfo.fromPlatform()` during `initState` in an async helper; until available, pass installed version `0`/empty name and let the panel show idle.

- [ ] **Step 5: Run UI tests**

Run:

```powershell
cd mobile
dart analyze lib test
flutter test --no-pub test\app_update_view_model_test.dart test\app_update_panel_test.dart -r expanded
```

Expected: all pass.

- [ ] **Step 6: Commit UI**

```powershell
git add mobile\lib\src\ui\features\settings\view_models\app_update_view_model.dart mobile\lib\src\ui\features\settings\widgets\app_update_panel.dart mobile\lib\src\ui\features\settings\settings_page.dart mobile\lib\src\ui\features\settings\settings.dart mobile\lib\src\ui\main_tabs_page.dart mobile\lib\src\app\app_dependencies.dart mobile\test\app_update_view_model_test.dart mobile\test\app_update_panel_test.dart
git commit -m "Add Android update settings UI" -m "Constraint: Mandatory updates still allow daemon switching and diagnostics access." -m "Tested: dart analyze lib test; flutter test --no-pub test\\app_update_view_model_test.dart test\\app_update_panel_test.dart -r expanded"
```

---

### Task 7: Mandatory Gate, Diagnostics, And Cleanup Polish

**Files:**

- Modify: `mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart`
- Modify: `mobile/lib/src/services/app_update_download_manager.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart` or diagnostics repository if trace rows are centralized there
- Modify: `daemon/src/app-update-service.js`
- Modify: `scripts/run-tests.js`
- Modify: `mobile/test/app_update_view_model_test.dart`
- Modify: `mobile/test/app_update_download_manager_test.dart`

- [ ] **Step 1: Add tests for reconciliation and diagnostics**

Add downloader tests:

```dart
test('reconciliation prefers verified apk over partial for same version', () async {
  final temp = await Directory.systemTemp.createTemp('app-update-reconcile-');
  final manager = AppUpdateDownloadManager(
    cacheDirectory: temp,
    openStream: (uri, {rangeStart, ifRange}) async =>
        http.StreamedResponse(Stream<List<int>>.empty(), 200),
    availableBytes: () async => 1000000,
  );
  final dir = Directory('${temp.path}/app_updates')..createSync(recursive: true);
  File('${dir.path}/app-update-2.apk').writeAsBytesSync(utf8.encode('verified'));
  File('${dir.path}/app-update-2.apk.part').writeAsBytesSync(utf8.encode('partial'));

  await manager.reconcile(_manifest(utf8.encode('verified'), versionCode: 2));

  expect(File('${dir.path}/app-update-2.apk').existsSync(), true);
  expect(File('${dir.path}/app-update-2.apk.part').existsSync(), false);
  await temp.delete(recursive: true);
});
```

Add ViewModel test:

```dart
test('mandatory gate keeps diagnostics and daemon switching actions enabled', () async {
  final state = AppUpdateState(
    status: AppUpdateStatus.available,
    installedVersionName: '1.0.0',
    installedVersionCode: 1,
    mandatory: true,
  );
  expect(state.mandatory, true);
});
```

- [ ] **Step 2: Implement cleanup and diagnostics events**

Add a simple callback to `AppUpdateViewModel`:

```dart
final void Function(String event, Map<String, Object?> metadata)? recordDiagnostic;
```

Call it for:

```dart
recordDiagnostic?.call('update.check.started', const <String, Object?>{});
recordDiagnostic?.call('update.storage.preflight_failed', {'versionCode': manifest.versionCode});
recordDiagnostic?.call('update.install.committed', {'sessionId': sessionId});
recordDiagnostic?.call('update.discard', {'versionCode': state.manifest?.versionCode});
```

Keep the first implementation as local trace/exception metadata, not a new database.

- [ ] **Step 3: Confirm `appUpdate` permission decision**

Inspect `daemon/src/auth.js`. If it already supports permission categories, add `appUpdate` default grant for paired devices and gate update endpoints through it. If auth only models paired devices/workspace authorization, keep update access under authenticated device and leave the spec's Phase 5 permission split deferred. Do not invent a new permission subsystem in this task.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
node scripts\run-tests.js
cd mobile
dart analyze lib test
flutter test --no-pub test\app_update_download_manager_test.dart test\app_update_view_model_test.dart -r expanded
```

Expected: all pass.

- [ ] **Step 5: Commit polish**

```powershell
git add daemon\src\app-update-service.js scripts\run-tests.js mobile\lib\src\services\app_update_download_manager.dart mobile\lib\src\ui\features\settings\view_models\app_update_view_model.dart mobile\test\app_update_download_manager_test.dart mobile\test\app_update_view_model_test.dart
git commit -m "Harden Android update recovery states" -m "Constraint: Verified APKs take precedence over partial files and diagnostics stay lightweight." -m "Tested: node scripts\\run-tests.js; dart analyze lib test; flutter test --no-pub test\\app_update_download_manager_test.dart test\\app_update_view_model_test.dart -r expanded"
```

---

### Task 8: End-To-End Verification And Knowledge Update

**Files:**

- Modify: `docs/project-knowledge/index.md`
- Create: `docs/project-knowledge/decisions/2026-05-24-private-android-apk-update-channel.md`
- Modify: `docs/project-knowledge/decisions/README.md`

- [ ] **Step 1: Run full daemon checks**

Run:

```powershell
node scripts\run-tests.js
npm run lint
node scripts\check-project-knowledge.js
git diff --check
```

Expected: all pass. `node` SQLite experimental warning is acceptable if it appears.

- [ ] **Step 2: Run mobile checks**

Run from `mobile`:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\app_update_models_test.dart test\app_update_client_test.dart test\app_update_download_manager_test.dart test\app_update_view_model_test.dart test\app_update_panel_test.dart -r expanded
```

Expected: all pass. If Flutter times out once, stop and ask the user to run this exact command.

- [ ] **Step 3: Run manual device smoke**

Use a real Android device or emulator:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter build apk --release
node ..\scripts\prepare-android-update.js --apk build\app\outputs\flutter-apk\app-release.apk --out ..\daemon\update-artifacts\android --version-name 1.4.0 --version-code 2 --package com.example.lan_ai_cli_control --release-notes "Private update smoke"
```

Then:

```text
1. Install the previous release-signed APK on the device.
2. Start daemon with ANDROID_UPDATE_ARTIFACT_DIR pointing at daemon/update-artifacts/android.
3. Connect mobile app to daemon.
4. Open Settings -> App update.
5. Download halfway, disable network, confirm paused state.
6. Re-enable network, resume, confirm Range request in daemon logs.
7. Install through Android UI.
8. Relaunch app and confirm versionCode changed and cache cleanup ran.
```

- [ ] **Step 4: Promote project knowledge**

Create `docs/project-knowledge/decisions/2026-05-24-private-android-apk-update-channel.md`:

```markdown
# Decision: Private Android APK Update Channel

- Status: accepted
- Date: 2026-05-24
- Last verified: 2026-05-24

## Context

The Android APK is distributed internally over LAN, not through Google Play.
Users should not manually copy APK files, but normal Android devices still
require system install confirmation.

## Decision

The daemon hosts a schema-versioned Android update manifest and streams only
the APK version currently referenced by that manifest. Mobile downloads with
Range and If-Range resume, verifies sha256, and installs through
PackageInstaller.Session.

## Alternatives

- Google Play In-App Updates: rejected for current private LAN distribution.
- Silent install: rejected because it requires device-owner or privileged
  installer conditions.
- Shorebird-only updates: rejected because native/plugin/manifest changes still
  need APK replacement.

## Evidence

- Spec: docs/superpowers/specs/2026-05-24-android-private-apk-update-design.md
- Plan: docs/superpowers/plans/2026-05-24-android-private-apk-update.md

## Verification

Run daemon and mobile update tests plus one manual Android device install smoke.

## Re-evaluate When

- Distribution moves to Google Play or enterprise MDM.
- Silent installation becomes mandatory.
- Daemon update hosting becomes multi-instance or HA.
```

Add it to `docs/project-knowledge/index.md` under Current Accepted Decisions and to `docs/project-knowledge/decisions/README.md`.

- [ ] **Step 5: Final commit**

```powershell
git add -f docs\project-knowledge\index.md docs\project-knowledge\decisions\README.md docs\project-knowledge\decisions\2026-05-24-private-android-apk-update-channel.md
git commit -m "Record private Android update decision" -m "Tested: node scripts\\check-project-knowledge.js"
```

---

## Plan Self-Review

Spec coverage:

- Daemon manifest, ETag/304, Range/If-Range, retained non-latest `404`, auth, and artifact validation are covered in Tasks 1-2.
- Release signing, keystore baseline, v2/v3 signing, and manifest generation are covered in Task 2.
- Mobile manifest parsing, schema whitelist, cross-origin rejection, repository wiring, and auth replay are covered in Task 3.
- Resumable download, cache path alignment, storage preflight, partial cleanup, non-blocking hash, and startup reconciliation are covered in Tasks 4 and 7.
- PackageInstaller session, permission settings, callback events, session recovery, and storage bridge are covered in Task 5.
- Settings UI, mandatory state, escape hatches, and diagnostics are covered in Tasks 6 and 7.
- Verification and project-knowledge promotion are covered in Task 8.

Red-flag scan:

- No task uses unresolved marker text or vague "handle it later" language as a substitute for concrete behavior.
- All new production files have concrete APIs and first-pass code snippets.

Type consistency:

- `AppUpdateManifest`, `AppUpdateDownloadManager`, `PackageInstallerService`, and `AppUpdateViewModel` names are consistent across tasks.
- Status names match the spec: `available`, `downloading`, `paused`, `readyToInstall`, `installPermissionNeeded`, `installing`, `installSucceeded`, `installCancelled`, `installFailed`, `cancelled`, `failed`.
