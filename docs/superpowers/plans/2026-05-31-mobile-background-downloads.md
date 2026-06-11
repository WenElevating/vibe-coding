# Mobile Background Downloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ASR model and Android app update downloads continue after the mobile app is sent to the background, while preserving current resume, checksum, and UI progress behavior.

**Architecture:** Add one Android-native foreground download bridge under `mobile/lib/src/services/` and `mobile/android/app/src/main/kotlin/...`. Dart remains the owner of product workflows and verification; Android owns only the long-running byte transfer into the same `.part` files the current Dart downloaders already understand. Non-Android and tests keep the existing Dart HTTP fallback.

**Tech Stack:** Flutter/Dart, Android Kotlin, `MethodChannel`, `EventChannel`, Android foreground service with `HttpURLConnection`, existing `http`, `crypto`, `archive`, `path_provider`, and `flutter_local_notifications` packages.

---

## Current Findings

- ASR downloads run in Dart inside `AsrModelManager._download()` and stream bytes from `AsrModelClient.download()`.
- App update downloads run in Dart inside `AppUpdateDownloadManager._downloadFromDaemon()` and `_writeStream()`.
- `AndroidManifest.xml` has `INTERNET` and `POST_NOTIFICATIONS`, but no foreground service permissions or service declaration.
- Existing `.part` files and Range support are valuable and should be reused instead of replaced.
- The minimum viable fix is not "keep the dialog open"; Android must own the active transfer once the user starts it.

## File Structure

- Create `mobile/lib/src/services/background_download_bridge.dart`
  - Dart interface and data models shared by ASR and update downloaders.
- Create `mobile/lib/src/services/method_channel_background_download_bridge.dart`
  - Production MethodChannel/EventChannel adapter for Android.
- Create `mobile/lib/src/services/noop_background_download_bridge.dart`
  - Fallback implementation for tests/non-Android that reports unsupported.
- Modify `mobile/lib/src/app/app_dependencies.dart`
  - Construct one bridge and inject it into ASR/update downloaders.
- Modify `mobile/lib/src/services/asr_model_manager.dart`
  - Prefer native background transfer for the ZIP bytes, then keep current verify/extract logic.
- Modify `mobile/lib/src/services/app_update_download_manager.dart`
  - Prefer native background transfer for APK bytes, then keep current verify/promote logic.
- Modify `mobile/android/app/src/main/AndroidManifest.xml`
  - Add foreground service permissions and declare the download service.
- Create `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadService.kt`
  - Runs download jobs, writes `.part` files, shows progress notification, supports cancel.
- Create `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadChannels.kt`
  - Owns MethodChannel/EventChannel registration and service event fan-out.
- Modify `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt`
  - Register background download channels without mixing logic into the installer channel.
- Modify `mobile/lib/l10n/app_en.arb` and `mobile/lib/l10n/app_zh.arb`
  - Replace "keep app open" update download copy with background-capable copy.
- Test `mobile/test/background_download_bridge_test.dart`
  - MethodChannel serialization and event parsing.
- Modify `mobile/test/asr_model_manager_test.dart`
  - Native download path, completed part promotion, unsupported fallback.
- Modify `mobile/test/app_update_download_manager_test.dart`
  - Native download path, progress, fallback, and `.part` verification.
- Modify `mobile/test/app_dependencies_test.dart`
  - Composition creates/injects the bridge.

---

### Task 1: Add Dart Background Download Contract

**Files:**
- Create: `mobile/lib/src/services/background_download_bridge.dart`
- Create: `mobile/lib/src/services/noop_background_download_bridge.dart`
- Test: `mobile/test/background_download_bridge_test.dart`

- [ ] **Step 1: Write the model test**

Create `mobile/test/background_download_bridge_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/background_download_bridge.dart';

void main() {
  test('snapshot parses native progress payload', () {
    final snapshot = BackgroundDownloadSnapshot.fromJson(const <String, Object?>{
      'id': 'asr:model-v1',
      'status': 'downloading',
      'downloadedBytes': 12,
      'totalBytes': 40,
      'destinationPath': '/tmp/model-v1.zip.part',
      'message': 'ok',
    });

    expect(snapshot.id, 'asr:model-v1');
    expect(snapshot.status, BackgroundDownloadStatus.downloading);
    expect(snapshot.downloadedBytes, 12);
    expect(snapshot.totalBytes, 40);
    expect(snapshot.destinationPath, '/tmp/model-v1.zip.part');
    expect(snapshot.fraction, 0.3);
  });

  test('request serializes headers and destination', () {
    const request = BackgroundDownloadRequest(
      id: 'update:17',
      kind: BackgroundDownloadKind.appUpdate,
      url: 'http://127.0.0.1:4317/api/app-updates/android/app.apk',
      destinationPath: '/tmp/app-update-17.apk.part',
      headers: <String, String>{
        'authorization': 'Bearer token',
        'range': 'bytes=10-',
      },
      expectedBytes: 120,
      resumeFromBytes: 10,
      notificationTitle: 'Downloading update',
      notificationBody: 'Version 1.4.15',
    );

    expect(request.toJson(), <String, Object?>{
      'id': 'update:17',
      'kind': 'appUpdate',
      'url': 'http://127.0.0.1:4317/api/app-updates/android/app.apk',
      'destinationPath': '/tmp/app-update-17.apk.part',
      'headers': <String, String>{
        'authorization': 'Bearer token',
        'range': 'bytes=10-',
      },
      'expectedBytes': 120,
      'resumeFromBytes': 10,
      'notificationTitle': 'Downloading update',
      'notificationBody': 'Version 1.4.15',
    });
  });

  test('noop bridge reports unsupported without throwing', () async {
    final bridge = UnsupportedBackgroundDownloadBridge();

    expect(await bridge.isSupported, false);
    expect(await bridge.prepareNotifications(), false);
    expect(
      bridge.events,
      emitsInOrder(<Matcher>[
        isA<BackgroundDownloadSnapshot>().having(
          (event) => event.status,
          'status',
          BackgroundDownloadStatus.failed,
        ),
      ]),
    );
    await bridge.start(const BackgroundDownloadRequest(
      id: 'unsupported',
      kind: BackgroundDownloadKind.asrModel,
      url: 'http://127.0.0.1/file.zip',
      destinationPath: '/tmp/file.zip.part',
      headers: <String, String>{},
      expectedBytes: 1,
      resumeFromBytes: 0,
      notificationTitle: 'Downloading',
      notificationBody: 'Background downloads are unavailable.',
    ));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
cd mobile
flutter test --no-pub test\background_download_bridge_test.dart -r expanded
```

Expected: FAIL because `background_download_bridge.dart` does not exist.

- [ ] **Step 3: Create the contract**

Create `mobile/lib/src/services/background_download_bridge.dart`:

```dart
enum BackgroundDownloadKind {
  asrModel,
  appUpdate;

  String get wireName => switch (this) {
        BackgroundDownloadKind.asrModel => 'asrModel',
        BackgroundDownloadKind.appUpdate => 'appUpdate',
      };

  static BackgroundDownloadKind fromWireName(String value) => switch (value) {
        'asrModel' => BackgroundDownloadKind.asrModel,
        'appUpdate' => BackgroundDownloadKind.appUpdate,
        _ => throw FormatException('Unknown background download kind: $value'),
      };
}

enum BackgroundDownloadStatus {
  queued,
  downloading,
  completed,
  cancelled,
  failed;

  static BackgroundDownloadStatus fromWireName(String value) => switch (value) {
        'queued' => BackgroundDownloadStatus.queued,
        'downloading' => BackgroundDownloadStatus.downloading,
        'completed' => BackgroundDownloadStatus.completed,
        'cancelled' => BackgroundDownloadStatus.cancelled,
        'failed' => BackgroundDownloadStatus.failed,
        _ => throw FormatException('Unknown background download status: $value'),
      };

  String get wireName => switch (this) {
        BackgroundDownloadStatus.queued => 'queued',
        BackgroundDownloadStatus.downloading => 'downloading',
        BackgroundDownloadStatus.completed => 'completed',
        BackgroundDownloadStatus.cancelled => 'cancelled',
        BackgroundDownloadStatus.failed => 'failed',
      };
}

class BackgroundDownloadRequest {
  const BackgroundDownloadRequest({
    required this.id,
    required this.kind,
    required this.url,
    required this.destinationPath,
    required this.headers,
    required this.expectedBytes,
    required this.resumeFromBytes,
    required this.notificationTitle,
    required this.notificationBody,
  });

  final String id;
  final BackgroundDownloadKind kind;
  final String url;
  final String destinationPath;
  final Map<String, String> headers;
  final int expectedBytes;
  final int resumeFromBytes;
  final String notificationTitle;
  final String notificationBody;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.wireName,
        'url': url,
        'destinationPath': destinationPath,
        'headers': headers,
        'expectedBytes': expectedBytes,
        'resumeFromBytes': resumeFromBytes,
        'notificationTitle': notificationTitle,
        'notificationBody': notificationBody,
      };
}

class BackgroundDownloadSnapshot {
  const BackgroundDownloadSnapshot({
    required this.id,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    this.destinationPath,
    this.message,
  });

  factory BackgroundDownloadSnapshot.fromJson(Map<String, Object?> json) {
    return BackgroundDownloadSnapshot(
      id: json['id'] as String,
      status: BackgroundDownloadStatus.fromWireName(json['status'] as String),
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      destinationPath: json['destinationPath'] as String?,
      message: json['message'] as String?,
    );
  }

  final String id;
  final BackgroundDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final String? destinationPath;
  final String? message;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0, 1).toDouble();
  }
}

abstract class BackgroundDownloadBridge {
  const BackgroundDownloadBridge();

  Future<bool> get isSupported;

  Future<bool> prepareNotifications();

  Stream<BackgroundDownloadSnapshot> get events;

  Future<BackgroundDownloadSnapshot> start(BackgroundDownloadRequest request);

  Future<void> cancel(String id);

  Future<BackgroundDownloadSnapshot?> snapshot(String id);
}
```

- [ ] **Step 4: Add unsupported fallback**

Create `mobile/lib/src/services/noop_background_download_bridge.dart`:

```dart
import 'dart:async';

import 'background_download_bridge.dart';

class UnsupportedBackgroundDownloadBridge implements BackgroundDownloadBridge {
  UnsupportedBackgroundDownloadBridge();

  @override
  Future<bool> get isSupported async => false;

  @override
  Future<bool> prepareNotifications() async => false;

  @override
  Stream<BackgroundDownloadSnapshot> get events => _controller.stream;

  final StreamController<BackgroundDownloadSnapshot> _controller =
      StreamController<BackgroundDownloadSnapshot>.broadcast();

  @override
  Future<BackgroundDownloadSnapshot> start(
    BackgroundDownloadRequest request,
  ) async {
    final snapshot = BackgroundDownloadSnapshot(
      id: request.id,
      status: BackgroundDownloadStatus.failed,
      downloadedBytes: request.resumeFromBytes,
      totalBytes: request.expectedBytes,
      destinationPath: request.destinationPath,
      message: 'Background downloads are not supported on this platform.',
    );
    _controller.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<BackgroundDownloadSnapshot?> snapshot(String id) async => null;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```powershell
cd mobile
flutter test --no-pub test\background_download_bridge_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/src/services/background_download_bridge.dart mobile/lib/src/services/noop_background_download_bridge.dart mobile/test/background_download_bridge_test.dart
git commit -m "Define a mobile background download contract"
```

---

### Task 2: Add MethodChannel Bridge

**Files:**
- Create: `mobile/lib/src/services/method_channel_background_download_bridge.dart`
- Modify: `mobile/test/background_download_bridge_test.dart`
- Verify: `mobile/pubspec.yaml`

- [ ] **Step 1: Verify notification dependency exists**

Run:

```powershell
rg -n "flutter_local_notifications" mobile\pubspec.yaml
```

Expected: one dependency row for `flutter_local_notifications`. If it is missing in the execution workspace, add it before continuing:

```powershell
cd mobile
flutter pub add flutter_local_notifications
```

- [ ] **Step 2: Add MethodChannel test**

Append to `mobile/test/background_download_bridge_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:lan_ai_cli_control/src/services/method_channel_background_download_bridge.dart';
```

Add this test inside `main()`:

```dart
  test('method channel bridge starts native download and parses result',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    const methodChannel =
        MethodChannel('lan_ai_cli_control/background_downloads');
    const eventChannel =
        EventChannel('lan_ai_cli_control/background_downloads/events');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      if (call.method == 'isSupported') return true;
      if (call.method == 'start') {
        return <String, Object?>{
          'id': 'update:17',
          'status': 'completed',
          'downloadedBytes': 120,
          'totalBytes': 120,
          'destinationPath': '/tmp/app-update-17.apk.part',
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, (_) async => null);

    final bridge = MethodChannelBackgroundDownloadBridge(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    final supported = await bridge.isSupported;
    final result = await bridge.start(const BackgroundDownloadRequest(
      id: 'update:17',
      kind: BackgroundDownloadKind.appUpdate,
      url: 'http://127.0.0.1:4317/apk',
      destinationPath: '/tmp/app-update-17.apk.part',
      headers: <String, String>{},
      expectedBytes: 120,
      resumeFromBytes: 0,
      notificationTitle: 'Downloading update',
      notificationBody: 'Version 1.4.15',
    ));

    expect(supported, true);
    expect(result.status, BackgroundDownloadStatus.completed);
    expect(calls.map((call) => call.method), <String>['isSupported', 'start']);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, null);
  });

  test('method channel bridge keeps listening when native ack is malformed',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const methodChannel =
        MethodChannel('lan_ai_cli_control/background_downloads');
    const eventChannel =
        EventChannel('lan_ai_cli_control/background_downloads/events');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'start') {
        return <String, Object?>{'unexpected': 'shape'};
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, (_) async => null);

    final bridge = MethodChannelBackgroundDownloadBridge(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    final result = await bridge.start(const BackgroundDownloadRequest(
      id: 'update:18',
      kind: BackgroundDownloadKind.appUpdate,
      url: 'http://127.0.0.1:4317/apk',
      destinationPath: '/tmp/app-update-18.apk.part',
      headers: <String, String>{},
      expectedBytes: 120,
      resumeFromBytes: 0,
      notificationTitle: 'Downloading update',
      notificationBody: 'Version 1.4.16',
    ));

    expect(result.id, 'update:18');
    expect(result.status, BackgroundDownloadStatus.queued);
    expect(result.message, contains('Malformed native start acknowledgement'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, null);
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```powershell
cd mobile
flutter test --no-pub test\background_download_bridge_test.dart -r expanded
```

Expected: FAIL because `method_channel_background_download_bridge.dart` does not exist.

- [ ] **Step 4: Implement MethodChannel bridge**

Create `mobile/lib/src/services/method_channel_background_download_bridge.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import 'background_download_bridge.dart';

class MethodChannelBackgroundDownloadBridge implements BackgroundDownloadBridge {
  MethodChannelBackgroundDownloadBridge({
    MethodChannel methodChannel =
        const MethodChannel('lan_ai_cli_control/background_downloads'),
    EventChannel eventChannel =
        const EventChannel('lan_ai_cli_control/background_downloads/events'),
    FlutterLocalNotificationsPlugin? notificationsPlugin,
  })  : _methodChannel = methodChannel,
        _notificationsPlugin =
            notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _events = eventChannel
            .receiveBroadcastStream()
            .where((event) => event is Map)
            .map((event) => BackgroundDownloadSnapshot.fromJson(
                  Map<String, Object?>.from(event as Map),
                ))
            .asBroadcastStream();

  final MethodChannel _methodChannel;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final Stream<BackgroundDownloadSnapshot> _events;
  Future<void>? _notificationInitialization;
  Future<bool>? _notificationPreparation;

  @override
  Future<bool> get isSupported async {
    final result = await _methodChannel.invokeMethod<bool>('isSupported');
    return result ?? false;
  }

  @override
  Future<bool> prepareNotifications() {
    return _notificationPreparation ??= _prepareNotifications();
  }

  Future<bool> _prepareNotifications() async {
    if (!Platform.isAndroid) return true;
    _notificationInitialization ??= _notificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _notificationInitialization;
    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Stream<BackgroundDownloadSnapshot> get events => _events;

  @override
  Future<BackgroundDownloadSnapshot> start(
    BackgroundDownloadRequest request,
  ) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'start',
      request.toJson(),
    );
    if (result == null) {
      throw StateError('Background download start returned no result.');
    }
    try {
      return BackgroundDownloadSnapshot.fromJson(result);
    } on Object catch (error) {
      return BackgroundDownloadSnapshot(
        id: request.id,
        status: BackgroundDownloadStatus.queued,
        downloadedBytes: request.resumeFromBytes,
        totalBytes: request.expectedBytes,
        destinationPath: request.destinationPath,
        message: 'Malformed native start acknowledgement: $error',
      );
    }
  }

  @override
  Future<void> cancel(String id) {
    return _methodChannel.invokeMethod<void>('cancel', <String, Object?>{
      'id': id,
    });
  }

  @override
  Future<BackgroundDownloadSnapshot?> snapshot(String id) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'snapshot',
      <String, Object?>{'id': id},
    );
    return result == null ? null : BackgroundDownloadSnapshot.fromJson(result);
  }
}
```

- [ ] **Step 5: Run test**

Run:

```powershell
cd mobile
flutter test --no-pub test\background_download_bridge_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/src/services/method_channel_background_download_bridge.dart mobile/test/background_download_bridge_test.dart
git commit -m "Bridge background downloads through platform channels"
```

---

### Task 3: Inject Bridge From App Composition

**Files:**
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/test/app_dependencies_test.dart`

- [ ] **Step 1: Add composition assertion**

Add imports to `mobile/test/app_dependencies_test.dart`:

```dart
import 'package:lan_ai_cli_control/src/services/background_download_bridge.dart';
```

Add this test:

```dart
  test('default feature dependencies provide a background download bridge',
      () {
    final data = DataDependencies(
      connectionConfigRepository: _FakeConnectionConfigRepository(),
    );
    final features = FeatureDependencies.createDefault(
      data: data,
      domain: DomainDependencies.createDefault(
        data: data,
        network: NetworkDependencies(
          tokenStore: MemoryTokenStore(),
          deviceIdentityStore: MemoryDeviceIdentityStore(deviceId: 'device'),
        ),
      ),
    );

    expect(features.backgroundDownloadBridge, isA<BackgroundDownloadBridge>());
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_dependencies_test.dart -r expanded --plain-name "background download bridge"
```

Expected: FAIL because `FeatureDependencies.backgroundDownloadBridge` does not exist.

- [ ] **Step 3: Add bridge to composition**

Modify `mobile/lib/src/app/app_dependencies.dart`:

```dart
import 'dart:io' show Platform;
import '../services/background_download_bridge.dart';
import '../services/method_channel_background_download_bridge.dart';
import '../services/noop_background_download_bridge.dart';
```

Update `FeatureDependencies` constructor and fields:

```dart
class FeatureDependencies {
  FeatureDependencies({
    required this.createDaemonConnectionViewModel,
    required this.createHomeViewModel,
    required this.createSettingsViewModel,
    required this.createDiagnosticsViewModel,
    required this.createRunDetailViewModel,
    required this.createAppUpdateViewModel,
    required this.createWorkbenchDependencies,
    BackgroundDownloadBridge? backgroundDownloadBridge,
  }) : backgroundDownloadBridge = backgroundDownloadBridge ??
            (Platform.isAndroid
                ? MethodChannelBackgroundDownloadBridge()
                : UnsupportedBackgroundDownloadBridge());

  final BackgroundDownloadBridge backgroundDownloadBridge;
```

Update the ASR and update constructors:

```dart
downloaderService: AppUpdateDownloadManager(
  cacheDirectory: cacheDirectory,
  openStream: appUpdateClient.openApkStream,
  availableBytes: installer.availableBytes,
  backgroundDownloadBridge: backgroundDownloadBridge,
),
```

```dart
asrModelManager: AsrModelManager(
  client: client.createAsrModelClient(),
  backgroundDownloadBridge: backgroundDownloadBridge,
),
```

- [ ] **Step 4: Temporarily make constructors compile**

Add optional parameters but do not use them yet:

In `AppUpdateDownloadManager`:

```dart
import 'background_download_bridge.dart';

AppUpdateDownloadManager({
  required Directory cacheDirectory,
  required AppUpdateStreamOpener openStream,
  required Future<int> Function() availableBytes,
  BackgroundDownloadBridge? backgroundDownloadBridge,
  DateTime Function() now = DateTime.now,
})  : _cacheDirectory = cacheDirectory,
      _openStream = openStream,
      _availableBytes = availableBytes,
      _backgroundDownloadBridge = backgroundDownloadBridge,
      _now = now;

final BackgroundDownloadBridge? _backgroundDownloadBridge;
```

In `AsrModelManager`:

```dart
import 'background_download_bridge.dart';

AsrModelManager({
  required AsrModelClient client,
  BackgroundDownloadBridge? backgroundDownloadBridge,
  Future<Directory> Function()? supportDirectoryProvider,
  DateTime Function()? now,
})  : _client = client,
      _backgroundDownloadBridge = backgroundDownloadBridge,
      _supportDirectoryProvider =
          supportDirectoryProvider ?? getApplicationSupportDirectory,
      _now = now ?? DateTime.now;

final BackgroundDownloadBridge? _backgroundDownloadBridge;
```

- [ ] **Step 5: Run test**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_dependencies_test.dart -r expanded --plain-name "background download bridge"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/src/app/app_dependencies.dart mobile/lib/src/services/asr_model_manager.dart mobile/lib/src/services/app_update_download_manager.dart mobile/test/app_dependencies_test.dart
git commit -m "Provide background download bridge from composition"
```

---

### Task 4: Implement Android Foreground Download Service

**Files:**
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadService.kt`
- Create: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadChannels.kt`
- Modify: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt`

- [ ] **Step 1: Update Manifest**

Modify `mobile/android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

Inside `<application>` add:

```xml
<service
    android:name=".BackgroundDownloadService"
    android:exported="false"
    android:foregroundServiceType="dataSync" />
```

- [ ] **Step 2: Add native service**

Create `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadService.kt`:

```kotlin
package com.example.lan_ai_cli_control

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.annotation.MainThread
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class BackgroundDownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startDownload(intent)
            ACTION_CANCEL -> cancelDownload(intent.getStringExtra(EXTRA_ID))
        }
        return START_NOT_STICKY
    }

    private fun startDownload(intent: Intent) {
        val request = BackgroundDownloadRequest.fromIntent(intent) ?: return
        active[request.id]?.cancelled = true
        val token = ActiveDownload()
        active[request.id] = token
        ensureChannel()
        startForeground(notificationIdFor(request.id), notification(request, 0, request.expectedBytes))
        emit(request.id, "queued", request.resumeFromBytes, request.expectedBytes, request.destinationPath, null)
        thread(name = "bg-download-${request.id}") {
            runDownload(request, token)
        }
    }

    private fun runDownload(request: BackgroundDownloadRequest, token: ActiveDownload) {
        try {
            val destination = File(request.destinationPath)
            destination.parentFile?.mkdirs()
            val connection = URL(request.url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            request.headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            connection.connect()
            val code = connection.responseCode
            if (code !in listOf(200, 206)) {
                throw IllegalStateException("Download server returned HTTP $code")
            }
            val append = request.resumeFromBytes > 0 && code == 206
            val stream = connection.inputStream.buffered()
            var downloaded = if (append) request.resumeFromBytes else 0L
            token.lastProgressBytes = downloaded
            token.lastProgressAtMs = SystemClock.elapsedRealtime()
            FileOutputStream(destination, append).buffered().use { output ->
                stream.use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        if (token.cancelled) {
                            emit(request.id, "cancelled", downloaded, request.expectedBytes, request.destinationPath, "Cancelled")
                            stopSelfIfIdle(request.id)
                            return
                        }
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        downloaded += read
                        if (shouldPublishProgress(token, downloaded, request.expectedBytes)) {
                            emit(request.id, "downloading", downloaded, request.expectedBytes, request.destinationPath, null)
                            updateNotification(request, downloaded)
                        }
                    }
                    output.flush()
                }
            }
            emit(request.id, "completed", downloaded, request.expectedBytes, request.destinationPath, null)
        } catch (error: Exception) {
            emit(request.id, "failed", request.resumeFromBytes, request.expectedBytes, request.destinationPath, error.message)
        } finally {
            active.remove(request.id)
            stopSelfIfIdle(request.id)
        }
    }

    private fun updateNotification(request: BackgroundDownloadRequest, downloaded: Long) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(notificationIdFor(request.id), notification(request, downloaded, request.expectedBytes))
    }

    private fun shouldPublishProgress(token: ActiveDownload, downloaded: Long, total: Long): Boolean {
        val now = SystemClock.elapsedRealtime()
        val byteStep = if (total > 0) (total / 100).coerceAtLeast(256 * 1024) else 256 * 1024
        if (downloaded - token.lastProgressBytes < byteStep && now - token.lastProgressAtMs < 500) {
            return false
        }
        token.lastProgressBytes = downloaded
        token.lastProgressAtMs = now
        return true
    }

    private fun notification(request: BackgroundDownloadRequest, downloaded: Long, total: Long) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(request.notificationTitle)
            .setContentText(request.notificationBody)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(NOTIFICATION_PROGRESS_MAX, notificationProgress(downloaded, total), total <= 0)
            .build()

    private fun notificationProgress(downloaded: Long, total: Long): Int {
        if (total <= 0) return 0
        return ((downloaded.coerceAtLeast(0) * NOTIFICATION_PROGRESS_MAX) / total)
            .coerceIn(0, NOTIFICATION_PROGRESS_MAX.toLong())
            .toInt()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Background downloads", NotificationManager.IMPORTANCE_LOW)
        )
    }

    private fun cancelDownload(id: String?) {
        if (id == null) return
        active[id]?.cancelled = true
    }

    private fun stopSelfIfIdle(id: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.cancel(notificationIdFor(id))
        clearNotificationId(id)
        clearSnapshot(id)
        if (active.isEmpty()) stopSelf()
    }

    companion object {
        private const val CHANNEL_ID = "background_downloads"
        private const val NOTIFICATION_PROGRESS_MAX = 1000
        private const val ACTION_START = "lan_ai_cli_control.background_downloads.START"
        private const val ACTION_CANCEL = "lan_ai_cli_control.background_downloads.CANCEL"
        private const val EXTRA_ID = "id"
        private val active = ConcurrentHashMap<String, ActiveDownload>()
        private val notificationIds = ConcurrentHashMap<String, Int>()
        private val nextNotificationId = AtomicInteger(10_000)
        private val mainHandler = Handler(Looper.getMainLooper())

        fun start(context: Context, request: BackgroundDownloadRequest) {
            val intent = request.toIntent(context, ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun cancel(context: Context, id: String) {
            context.startService(Intent(context, BackgroundDownloadService::class.java).apply {
                action = ACTION_CANCEL
                putExtra(EXTRA_ID, id)
            })
        }

        fun emit(id: String, status: String, downloaded: Long, total: Long, path: String, message: String?) {
            val snapshot = mapOf(
                "id" to id,
                "status" to status,
                "downloadedBytes" to downloaded,
                "totalBytes" to total,
                "destinationPath" to path,
                "message" to message
            )
            mainHandler.post {
                BackgroundDownloadChannels.emit(snapshot)
            }
        }

        fun clearSnapshot(id: String) {
            mainHandler.post {
                BackgroundDownloadChannels.clear(id)
            }
        }

        private fun notificationIdFor(id: String): Int =
            notificationIds.computeIfAbsent(id) { nextNotificationId.getAndIncrement() }

        private fun clearNotificationId(id: String) {
            notificationIds.remove(id)
        }
    }
}

private class ActiveDownload {
    @Volatile var cancelled: Boolean = false
    @Volatile var lastProgressAtMs: Long = 0
    @Volatile var lastProgressBytes: Long = 0
}

data class BackgroundDownloadRequest(
    val id: String,
    val kind: String,
    val url: String,
    val destinationPath: String,
    val headers: Map<String, String>,
    val expectedBytes: Long,
    val resumeFromBytes: Long,
    val notificationTitle: String,
    val notificationBody: String
) {
    fun toIntent(context: Context, actionName: String): Intent =
        Intent(context, BackgroundDownloadService::class.java).apply {
            action = actionName
            putExtra("id", id)
            putExtra("kind", kind)
            putExtra("url", url)
            putExtra("destinationPath", destinationPath)
            putExtra("expectedBytes", expectedBytes)
            putExtra("resumeFromBytes", resumeFromBytes)
            putExtra("notificationTitle", notificationTitle)
            putExtra("notificationBody", notificationBody)
            headers.forEach { (key, value) -> putExtra("header:$key", value) }
        }

    companion object {
        fun fromIntent(intent: Intent): BackgroundDownloadRequest? {
            val id = intent.getStringExtra("id") ?: return null
            val kind = intent.getStringExtra("kind") ?: return null
            val url = intent.getStringExtra("url") ?: return null
            val destinationPath = intent.getStringExtra("destinationPath") ?: return null
            val headers = intent.extras?.keySet()
                ?.filter { it.startsWith("header:") }
                ?.associate { it.removePrefix("header:") to (intent.getStringExtra(it) ?: "") }
                ?: emptyMap()
            return BackgroundDownloadRequest(
                id = id,
                kind = kind,
                url = url,
                destinationPath = destinationPath,
                headers = headers,
                expectedBytes = intent.getLongExtra("expectedBytes", 0),
                resumeFromBytes = intent.getLongExtra("resumeFromBytes", 0),
                notificationTitle = intent.getStringExtra("notificationTitle") ?: "Downloading",
                notificationBody = intent.getStringExtra("notificationBody") ?: ""
            )
        }
    }
}
```

- [ ] **Step 3: Add channel registration**

Create `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadChannels.kt`:

```kotlin
package com.example.lan_ai_cli_control

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object BackgroundDownloadChannels {
    private const val METHOD_CHANNEL = "lan_ai_cli_control/background_downloads"
    private const val EVENT_CHANNEL = "lan_ai_cli_control/background_downloads/events"
    private var eventSink: EventChannel.EventSink? = null
    private val lastSnapshots = linkedMapOf<String, Map<String, Any?>>()

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "start" -> {
                        val args = call.arguments as? Map<*, *>
                        val request = requestFromMap(args)
                        if (request == null) {
                            result.error("BAD_ARGUMENT", "Invalid background download request", null)
                            return@setMethodCallHandler
                        }
                        BackgroundDownloadService.start(context.applicationContext, request)
                        val snapshot = mapOf(
                            "id" to request.id,
                            "status" to "queued",
                            "downloadedBytes" to request.resumeFromBytes,
                            "totalBytes" to request.expectedBytes,
                            "destinationPath" to request.destinationPath,
                            "message" to null
                        )
                        emit(snapshot)
                        result.success(snapshot)
                    }
                    "cancel" -> {
                        val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                        if (id != null) BackgroundDownloadService.cancel(context.applicationContext, id)
                        result.success(null)
                    }
                    "snapshot" -> {
                        val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                        result.success(lastSnapshots[id])
                    }
                    else -> result.notImplemented()
                }
            }

        var ownedSink: EventChannel.EventSink? = null
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ownedSink = events
                    eventSink = events
                    lastSnapshots.values.forEach { events?.success(it) }
                }

                override fun onCancel(arguments: Any?) {
                    if (eventSink === ownedSink) {
                        eventSink = null
                    }
                    ownedSink = null
                }
            })
    }

    @MainThread
    fun emit(snapshot: Map<String, Any?>) {
        val id = snapshot["id"] as? String ?: return
        val status = snapshot["status"] as? String
        if (status == "queued" || status == "downloading") {
            lastSnapshots[id] = snapshot
        } else {
            lastSnapshots.remove(id)
        }
        eventSink?.success(snapshot)
    }

    @MainThread
    fun clear(id: String) {
        lastSnapshots.remove(id)
    }

    private fun requestFromMap(args: Map<*, *>?): BackgroundDownloadRequest? {
        if (args == null) return null
        val id = args["id"] as? String ?: return null
        val kind = args["kind"] as? String ?: return null
        val url = args["url"] as? String ?: return null
        val destinationPath = args["destinationPath"] as? String ?: return null
        val rawHeaders = args["headers"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val headers = rawHeaders.entries.associate { "${it.key}" to "${it.value}" }
        return BackgroundDownloadRequest(
            id = id,
            kind = kind,
            url = url,
            destinationPath = destinationPath,
            headers = headers,
            expectedBytes = (args["expectedBytes"] as? Number)?.toLong() ?: 0L,
            resumeFromBytes = (args["resumeFromBytes"] as? Number)?.toLong() ?: 0L,
            notificationTitle = args["notificationTitle"] as? String ?: "Downloading",
            notificationBody = args["notificationBody"] as? String ?: ""
        )
    }
}
```

- [ ] **Step 4: Register channels from MainActivity**

In `MainActivity.configureFlutterEngine()` add after installer channel registration:

```kotlin
BackgroundDownloadChannels.register(this, flutterEngine)
```

- [ ] **Step 5: Build Android debug to catch Kotlin/manifest errors**

Run:

```powershell
cd mobile
flutter build apk --debug
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```bash
git add mobile/android/app/src/main/AndroidManifest.xml mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadService.kt mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadChannels.kt mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt
git commit -m "Run mobile downloads in an Android foreground service"
```

---

### Task 5: Route App Update Downloads Through Native Bridge

**Files:**
- Modify: `mobile/lib/src/services/app_update_download_manager.dart`
- Modify: `mobile/test/app_update_download_manager_test.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add failing native update test**

In `mobile/test/app_update_download_manager_test.dart`, add a fake bridge:

```dart
class _FakeBackgroundDownloadBridge implements BackgroundDownloadBridge {
  _FakeBackgroundDownloadBridge({required this.supported});

  final bool supported;
  final requests = <BackgroundDownloadRequest>[];
  final _events = StreamController<BackgroundDownloadSnapshot>.broadcast();

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<bool> prepareNotifications() async => true;

  @override
  Stream<BackgroundDownloadSnapshot> get events => _events.stream;

  @override
  Future<BackgroundDownloadSnapshot> start(BackgroundDownloadRequest request) async {
    requests.add(request);
    final file = File(request.destinationPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode('hello-world'));
    final snapshot = BackgroundDownloadSnapshot(
      id: request.id,
      status: BackgroundDownloadStatus.completed,
      downloadedBytes: request.expectedBytes,
      totalBytes: request.expectedBytes,
      destinationPath: request.destinationPath,
    );
    _events.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<BackgroundDownloadSnapshot?> snapshot(String id) async => null;
}
```

Add test:

```dart
  test('uses native background bridge before verifying downloaded APK', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 21);
    final bridge = _FakeBackgroundDownloadBridge(supported: true);
    var dartStreamOpened = false;
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      openStream: (uri, {rangeStart, ifRange}) async {
        dartStreamOpened = true;
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(dartStreamOpened, false);
    expect(bridge.requests.single.kind, BackgroundDownloadKind.appUpdate);
    await temp.delete(recursive: true);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_update_download_manager_test.dart -r expanded --plain-name "uses native background bridge"
```

Expected: FAIL because manager still opens Dart stream.

- [ ] **Step 3: Implement native branch**

In `AppUpdateDownloadManager._downloadWithoutGuard()`, before `_downloadFromDaemon(...)`, add:

```dart
      final nativeResult = await _downloadWithNativeBridge(
        manifest: manifest,
        daemonBaseUri: daemonBaseUri,
        paths: paths,
        resumeLength: resumeLength,
        onProgress: onProgress,
      );
      if (nativeResult != null) return nativeResult;
```

Add helper:

```dart
  Future<AppUpdateDownloadResult?> _downloadWithNativeBridge({
    required AppUpdateManifest manifest,
    required Uri daemonBaseUri,
    required _AppUpdatePaths paths,
    required int resumeLength,
    AppUpdateDownloadProgressCallback? onProgress,
  }) async {
    final bridge = _backgroundDownloadBridge;
    if (bridge == null || !await bridge.isSupported) return null;
    if (!await bridge.prepareNotifications()) {
      return const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'Notification permission is required for background update downloads.',
      );
    }
    final apkUri = manifest.resolveApkUri(daemonBaseUri);
    final headers = <String, String>{
      if (resumeLength > 0) 'range': 'bytes=$resumeLength-',
      if (resumeLength > 0 && manifest.etag != null) 'if-range': manifest.etag!,
    };
    final downloadId = 'app-update:${manifest.versionCode}';
    final terminal = Completer<BackgroundDownloadSnapshot>();
    late final StreamSubscription<BackgroundDownloadSnapshot> subscription;
    subscription = bridge.events
        .where((event) => event.id == downloadId)
        .listen((event) {
      if (event.status == BackgroundDownloadStatus.downloading ||
          event.status == BackgroundDownloadStatus.completed) {
        _emitProgress(
          onProgress,
          event.downloadedBytes,
          event.totalBytes <= 0 ? manifest.sizeBytes! : event.totalBytes,
        );
      }
      if (!terminal.isCompleted &&
          (event.status == BackgroundDownloadStatus.completed ||
              event.status == BackgroundDownloadStatus.cancelled ||
              event.status == BackgroundDownloadStatus.failed)) {
        terminal.complete(event);
      }
    });
    try {
      await bridge.start(BackgroundDownloadRequest(
        id: downloadId,
        kind: BackgroundDownloadKind.appUpdate,
        url: daemonBaseUri.resolveUri(apkUri).toString(),
        destinationPath: paths.part.path,
        headers: headers,
        expectedBytes: manifest.sizeBytes!,
        resumeFromBytes: resumeLength,
        notificationTitle: 'Downloading update',
        notificationBody: manifest.versionName ?? 'Android update',
      ));
      final result = await terminal.future;
      if (result.status == BackgroundDownloadStatus.completed) {
        await _writeMetadata(paths.metadata, manifest, manifest.sizeBytes!);
        return await _verifyAndPromote(paths, manifest);
      }
      if (result.status == BackgroundDownloadStatus.cancelled) {
        return AppUpdateDownloadResult(
          state: AppUpdateDownloadState.paused,
          message: result.message ?? 'Update download was cancelled.',
        );
      }
      if (result.status == BackgroundDownloadStatus.failed) {
        return AppUpdateDownloadResult(
          state: AppUpdateDownloadState.paused,
          message: result.message ?? 'Update download was interrupted.',
        );
      }
      return null;
    } finally {
      await subscription.cancel();
    }
  }
```

- [ ] **Step 4: Update copy**

Change `mobile/lib/l10n/app_en.arb`:

```json
"appUpdateProgressDownloadingMessage": "Downloading the update package. You can leave the app while it continues in the background.",
```

Change `mobile/lib/l10n/app_zh.arb`:

```json
"appUpdateProgressDownloadingMessage": "正在下载更新包，切到后台后会继续下载。",
```

- [ ] **Step 5: Run tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_update_download_manager_test.dart -r expanded
flutter test --no-pub test\app_update_panel_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/src/services/app_update_download_manager.dart mobile/test/app_update_download_manager_test.dart mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb
git commit -m "Move update package transfer into background downloads"
```

---

### Task 6: Route ASR Model Downloads Through Native Bridge

**Files:**
- Modify: `mobile/lib/src/services/asr_model_manager.dart`
- Modify: `mobile/test/asr_model_manager_test.dart`

- [ ] **Step 1: Add failing ASR native test**

In `mobile/test/asr_model_manager_test.dart`, import the bridge:

```dart
import 'package:lan_ai_cli_control/src/services/background_download_bridge.dart';
```

Add fake bridge:

```dart
class _FakeBackgroundDownloadBridge implements BackgroundDownloadBridge {
  _FakeBackgroundDownloadBridge({
    required this.bytes,
    this.supported = true,
    this.notificationsPrepared = true,
  });

  final List<int> bytes;
  final bool supported;
  final bool notificationsPrepared;
  final requests = <BackgroundDownloadRequest>[];
  final _events = StreamController<BackgroundDownloadSnapshot>.broadcast();

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<bool> prepareNotifications() async => notificationsPrepared;

  @override
  Stream<BackgroundDownloadSnapshot> get events => _events.stream;

  @override
  Future<BackgroundDownloadSnapshot> start(BackgroundDownloadRequest request) async {
    requests.add(request);
    final file = File(request.destinationPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    final snapshot = BackgroundDownloadSnapshot(
      id: request.id,
      status: BackgroundDownloadStatus.completed,
      downloadedBytes: bytes.length,
      totalBytes: bytes.length,
      destinationPath: request.destinationPath,
    );
    _events.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<BackgroundDownloadSnapshot?> snapshot(String id) async => null;
}
```

Add test:

```dart
  test('uses native background bridge for ASR archive transfer', () async {
    final bytes = _zipBytes();
    final bridge = _FakeBackgroundDownloadBridge(bytes: bytes);
    final client = _FakeAsrModelClient(metadata: _metadata(bytes));
    final manager = AsrModelManager(
      client: client,
      backgroundDownloadBridge: bridge,
      supportDirectoryProvider: () async => tempDir,
    );

    final modelPath = await manager.ensureReady();

    expect(bridge.requests.single.kind, BackgroundDownloadKind.asrModel);
    expect(client.downloadCalls, 0);
    expect(File('$modelPath/encoder.onnx').existsSync(), true);
    expect(manager.state.status, AsrModelStatus.ready);
  });
```

Add permission-denied test:

```dart
  test('native ASR path reports failure when notification permission is denied',
      () async {
    final bytes = _zipBytes();
    final bridge = _FakeBackgroundDownloadBridge(
      bytes: bytes,
      notificationsPrepared: false,
    );
    final client = _FakeAsrModelClient(metadata: _metadata(bytes));
    final manager = AsrModelManager(
      client: client,
      backgroundDownloadBridge: bridge,
      supportDirectoryProvider: () async => tempDir,
    );

    await expectLater(
      manager.ensureReady(),
      throwsA(isA<StateError>().having(
        (error) => '$error',
        'message',
        contains('Notification permission is required'),
      )),
    );

    expect(manager.state.status, AsrModelStatus.failed);
    expect(client.downloadCalls, 0);
    expect(bridge.requests, isEmpty);
  });
```

Add completed-part test:

```dart
  test('completed ASR part is promoted without reopening network stream', () async {
    final bytes = _zipBytes();
    final metadata = _metadata(bytes);
    final root = Directory('${tempDir.path}/asr_models')..createSync();
    File('${root.path}/model-v1.zip.part').writeAsBytesSync(bytes);
    final client = _FakeAsrModelClient(metadata: metadata);
    final manager = AsrModelManager(
      client: client,
      supportDirectoryProvider: () async => tempDir,
    );

    await manager.ensureReady();

    expect(client.downloadCalls, 0);
    expect(manager.state.status, AsrModelStatus.ready);
  });
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
cd mobile
flutter test --no-pub test\asr_model_manager_test.dart -r expanded --plain-name "native background bridge"
flutter test --no-pub test\asr_model_manager_test.dart -r expanded --plain-name "notification permission is denied"
flutter test --no-pub test\asr_model_manager_test.dart -r expanded --plain-name "completed ASR part"
```

Expected: FAIL because ASR still opens Dart stream, notification-denied behavior is not implemented, and completed `.part` still tries the network path.

- [ ] **Step 3: Add completed-part fast path**

At the start of `AsrModelManager._download()` after computing `start`:

```dart
    if (start == metadata.sizeBytes) {
      if (await paths.zip.exists()) await paths.zip.delete();
      return paths.part.rename(paths.zip.path);
    }
```

- [ ] **Step 4: Add native transfer path**

Before the existing `while (true)` loop in `_download()`:

```dart
    final nativeZip = await _downloadWithNativeBridge(metadata, paths, start);
    if (nativeZip != null) return nativeZip;
```

Add helper:

```dart
  Future<File?> _downloadWithNativeBridge(
    AsrModelMetadata metadata,
    _AsrModelPaths paths,
    int start,
    ) async {
    final bridge = _backgroundDownloadBridge;
    if (bridge == null || !await bridge.isSupported) return null;
    if (!await bridge.prepareNotifications()) {
      throw StateError(
        'Notification permission is required for background voice model downloads.',
      );
    }
    final requestHeaders = <String, String>{
      if (start > 0) 'range': 'bytes=$start-',
    };
    final downloadId = 'asr-model:${metadata.version}';
    final terminal = Completer<BackgroundDownloadSnapshot>();
    late final StreamSubscription<BackgroundDownloadSnapshot> subscription;
    subscription = bridge.events
        .where((event) => event.id == downloadId)
        .listen((event) {
      if (event.status == BackgroundDownloadStatus.downloading ||
          event.status == BackgroundDownloadStatus.completed) {
        _emit(_state.copyWith(
          status: AsrModelStatus.downloading,
          version: metadata.version,
          downloadedBytes: event.downloadedBytes,
          totalBytes: metadata.sizeBytes,
        ));
      }
      if (!terminal.isCompleted &&
          (event.status == BackgroundDownloadStatus.completed ||
              event.status == BackgroundDownloadStatus.cancelled ||
              event.status == BackgroundDownloadStatus.failed)) {
        terminal.complete(event);
      }
    });
    try {
      _nativeDownloadActive = true;
      await bridge.start(BackgroundDownloadRequest(
        id: downloadId,
        kind: BackgroundDownloadKind.asrModel,
        url: _client.baseUri.resolve(metadata.downloadPath).toString(),
        destinationPath: paths.part.path,
        headers: requestHeaders,
        expectedBytes: metadata.sizeBytes,
        resumeFromBytes: start,
        notificationTitle: 'Downloading voice model',
        notificationBody: metadata.version,
      ));
      final result = await terminal.future;
      if (result.status == BackgroundDownloadStatus.cancelled) {
        throw const _PreparationStopped(AsrModelStatus.paused);
      }
      if (result.status == BackgroundDownloadStatus.failed) {
        throw StateError(result.message ?? 'Voice model download was interrupted.');
      }
      if (await paths.zip.exists()) await paths.zip.delete();
      return paths.part.rename(paths.zip.path);
    } finally {
      _nativeDownloadActive = false;
      await subscription.cancel();
    }
  }
```

Also add the state field near `_activePreparation`:

```dart
bool _nativeDownloadActive = false;
```

- [ ] **Step 5: Run tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\asr_model_manager_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/src/services/asr_model_manager.dart mobile/test/asr_model_manager_test.dart
git commit -m "Move ASR archive transfer into background downloads"
```

---

### Task 7: Polish Lifecycle, Cancellation, And Diagnostics

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart`
- Modify: `mobile/test/app_update_view_model_test.dart`

- [ ] **Step 1: Add update pause semantics test**

In `mobile/test/app_update_view_model_test.dart`, add:

```dart
  test('background native interruption remains paused and resumable', () async {
    final manifest = _manifest(versionCode: 30);
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      workflow: _FakeWorkflow(
        manifest: manifest,
        downloader: _FakeDownloader(
          result: const AppUpdateDownloadResult(
            state: AppUpdateDownloadState.paused,
            message: 'Download can continue later.',
          ),
        ),
      ),
    );

    await viewModel.checkForUpdates();
    await viewModel.download();

    expect(viewModel.state.status, AppUpdateStatus.paused);
    expect(viewModel.state.manifest, manifest);
    expect(viewModel.state.errorMessage, contains('continue later'));
  });
```

- [ ] **Step 2: Run test**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_update_view_model_test.dart -r expanded --plain-name "background native interruption"
```

Expected: PASS if existing paused state behavior is preserved; otherwise fix before continuing.

- [ ] **Step 3: Keep ASR manager alive across tab changes**

Inspect `MainTabsPage._disposeWorkbenchDependencies()`. If ASR download is active and native bridge owns transfer, disposing the manager should not cancel the native service. Keep `AsrModelManager.dispose()` as UI-listener cleanup only after native migration by changing:

```dart
  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    super.dispose();
  }
```

to:

```dart
  @override
  void dispose() {
    _disposed = true;
    if (!_nativeDownloadActive) {
      _cancelRequested = true;
    }
    super.dispose();
  }
```

This preserves old fallback cancellation but avoids killing native background work.

- [ ] **Step 4: Confirm app update disposal does not cancel native work**

Do not add `_nativeDownloadActive` to `AppUpdateDownloadManager` unless a cancellation path is introduced. Current app update flow has no manager-level `dispose()` and `AppUpdateViewModel.dispose()` only suppresses UI notifications; it does not cancel the in-flight `workflow.download()` future. Add this code comment near `AppUpdateViewModel.dispose()` only if the implementation makes that behavior non-obvious:

```dart
// Do not cancel an active native update download here. The Android service owns
// the byte transfer and the next foreground update check reconciles the .part
// or verified APK file.
```

If implementation later adds explicit update-download cancellation, it must call `BackgroundDownloadBridge.cancel(id)` intentionally rather than relying on ViewModel disposal.

- [ ] **Step 5: Add diagnostics for native fallback**

In both download managers, when native bridge is supported but returns failed, preserve `result.message` in existing failed/paused state. Do not swallow the native message.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_update_view_model_test.dart -r expanded
flutter test --no-pub test\asr_model_manager_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/src/services/asr_model_manager.dart mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart mobile/test/app_update_view_model_test.dart
git commit -m "Preserve resumable download state across backgrounding"
```

---

### Task 8: Full Verification And Manual Android Smoke

**Files:**
- Modify only if failures are found.

- [ ] **Step 1: Dart analysis**

Run:

```powershell
cd mobile
dart analyze lib test
```

Expected: no issues.

- [ ] **Step 2: Architecture check**

Run:

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

- [ ] **Step 3: Flutter tests**

Run:

```powershell
cd mobile
flutter test --no-pub
```

Expected: PASS.

- [ ] **Step 4: Android build**

Run:

```powershell
cd mobile
flutter build apk --debug
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Manual ASR smoke**

On an Android device:

1. Uninstall ASR model files or clear app data.
2. Open a conversation and tap voice input.
3. Start ASR model download.
4. Grant notification permission if Android asks.
5. Press Home immediately.
6. Confirm an Android notification shows download progress.
7. Wait until notification completes.
8. Reopen app.
9. Confirm ASR model verifies/extracts and voice input can start.

Expected: download does not restart from zero and no "keep app open" requirement appears.

- [ ] **Step 6: Manual app update smoke**

On an Android device with a newer daemon update manifest:

1. Open Settings.
2. Start update download.
3. Grant notification permission if Android asks.
4. Press Home immediately.
5. Confirm notification progress continues.
6. Reopen app after completion.
7. Confirm update state is `readyToInstall`.
8. Tap install and confirm Android installer opens.

Expected: APK file verifies and installer starts.

- [ ] **Step 7: Optional kill/resume smoke**

On an Android device:

1. Start an ASR or app update download.
2. Wait until progress is above 10%.
3. Force stop the app from Android settings or kill the process with `adb shell am force-stop com.example.lan_ai_cli_control`.
4. Reopen the app.
5. Start the same download again.
6. Confirm it resumes from the existing `.part` file instead of restarting from zero.

Expected: forced process death stops the active service, but the next foreground launch resumes from partial bytes.

- [ ] **Step 8: Project knowledge update**

Add an entry to `docs/project-knowledge/troubleshooting-playbook.md`:

```markdown
## Symptom: Mobile Downloads Stop After App Backgrounding

- Symptom: ASR model or Android update downloads pause/fail when the app is sent
  to the background.
- Action: keep byte transfers in the Android foreground download service and
  let Dart workflows verify/promote the completed `.part` file on resume.
- Related files:
  [BackgroundDownloadService.kt](../../mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadService.kt),
  [background_download_bridge.dart](../../mobile/lib/src/services/background_download_bridge.dart)
- Verification:

```powershell
cd mobile
flutter test --no-pub test\background_download_bridge_test.dart test\asr_model_manager_test.dart test\app_update_download_manager_test.dart
flutter build apk --debug
```

- Last verified: 2026-05-31
```

- [ ] **Step 9: Final commit**

```bash
git add docs/project-knowledge/troubleshooting-playbook.md
git commit -m "Document mobile background download recovery"
```

---

## Self-Review

- Spec coverage: ASR download, app update download, background continuation, progress notification, resume, fallback, and tests are covered.
- Placeholder scan: no red-flag placeholder strings remain.
- Type consistency: `BackgroundDownloadBridge`, `BackgroundDownloadRequest`, and `BackgroundDownloadSnapshot` names are used consistently across tasks.
- Scope risk: Android foreground service is intentionally narrower than WorkManager/DownloadManager. It fixes user-initiated in-progress downloads without moving ASR extraction or APK verification into native code.
- Test helper duplication: Task 5 and Task 6 keep private `_FakeBackgroundDownloadBridge` implementations in their own test files. This is acceptable for now because each fake is small and scenario-specific; extract `mobile/test/helpers/fake_background_download_bridge.dart` only if the bridge interface changes again or a third test file needs the same fake.
- Known limitation: if the Android OS kills the entire process despite the foreground service, the active transfer stops and the next app open resumes from `.part`; this plan targets "backgrounding does not interrupt" rather than guaranteed reboot-surviving transfers.
- Timeout behavior: native `HttpURLConnection` connect/read timeouts surface as paused/interrupted states. The first implementation does not auto-retry in the background; the user can resume from the preserved partial file, matching existing update pause semantics.
