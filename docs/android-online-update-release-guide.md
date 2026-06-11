# Android 在线更新发布手册

本文档是给当前仓库的私有 Android APK 更新通道用的操作手册。它放在 `docs/`
下并应纳入版本控制；发布密钥、APK artifact、运行时 manifest 和本地 smoke
输出仍然不要提交。

## 当前能力边界

当前已经支持：

- daemon 在 LAN 内托管 Android 更新 manifest 和 APK。
- 移动端从已配对 daemon 检查更新。
- 移动端断点下载 APK。
- 移动端按 `sizeBytes` 和 `sha256` 校验 APK。
- 移动端通过 Android `PackageInstaller` 发起安装。
- 安装流程被打断后，App 创建和恢复前台时会尝试恢复安装 session。

当前不支持：

- App 启动后自动弹出更新提示。
- 用户无感自动安装。
- 普通 Android 设备上的静默安装。

所以现在的用户路径是：

```text
Settings -> App update -> Check -> Download -> Install -> Android 系统确认安装
```

如果产品需要更接近“自动更新”，还需要额外开发：

- 连接 daemon 成功后自动 `checkForUpdates()`。
- 有新版本时显示设置页外的更新提示。
- 强制更新时阻断 Coding 主流程，只保留更新、诊断、切换 daemon 等安全入口。
- 下载策略：是否自动下载、是否只在 Wi-Fi 下载、是否需要用户确认。
- 安装仍必须进入 Android 系统确认页，除非设备是企业 MDM/device owner 或系统特权安装器。

## 发布前必须确认

Android 能否升级成功取决于三个条件：

```text
packageName 相同
签名证书相同
versionCode 更大
```

当前包名是：

```text
com.example.lan_ai_cli_control
```

如果设备上安装的是 debug 签名包，而本次发布的是 release 私钥签名包，Android
不会允许覆盖升级。第一次切换到正式更新通道时，需要先卸载 debug 包，再安装一个
release-signed baseline APK。之后所有正式更新都必须使用同一把 release keystore。

## 第一次准备 release 签名

如果还没有 release keystore，先生成一把稳定私钥。

```powershell
cd D:\AIProject\vibe-coding\mobile\android

keytool -genkeypair `
  -v `
  -keystore app\release-upload-key.jks `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias lan-ai-cli-control
```

然后创建：

```text
D:\AIProject\vibe-coding\mobile\android\key.properties
```

内容示例：

```properties
storePassword=你的store密码
keyPassword=你的key密码
keyAlias=lan-ai-cli-control
storeFile=app/release-upload-key.jks
```

注意：

- `mobile/android/key.properties` 不要提交。
- `mobile/android/app/release-upload-key.jks` 不要提交。
- keystore 必须备份好，丢失后已安装用户无法继续升级。

当前 Gradle 配置会在 release build 时强制要求 `android/key.properties` 存在，避免误发无效签名包。

## 每次发布更新的步骤

下面以发布 `1.4.0+2` 为例。实际发布时替换成你的版本号。

### 1. 提升版本号

推荐修改：

```text
mobile/pubspec.yaml
```

例如：

```yaml
version: 1.4.0+2
```

其中：

- `1.4.0` 是 `versionName`。
- `2` 是 `versionCode`。

Android 判断是否能更新主要看 `versionCode`，所以它必须比设备上已安装版本更大。

如果只是临时 smoke，也可以不改 `pubspec.yaml`，构建时用参数覆盖：

```powershell
--build-name 1.4.0 --build-number 2
```

正式发布建议把版本号写进 `pubspec.yaml`。

### 2. 构建 release APK

```powershell
cd D:\AIProject\vibe-coding\mobile

$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'

flutter pub get
flutter build apk --release --build-name 1.4.0 --build-number 2
```

构建产物路径：

```text
D:\AIProject\vibe-coding\mobile\build\app\outputs\flutter-apk\app-release.apk
```

如果这里失败，优先检查：

- `mobile/android/key.properties` 是否存在。
- `storeFile` 指向的 keystore 是否存在。
- 密码和 alias 是否正确。
- 本机 Android SDK/NDK 是否完整。

### 3. 生成 daemon 更新包

从仓库根目录执行：

```powershell
cd D:\AIProject\vibe-coding

node scripts\prepare-android-update.js `
  --apk mobile\build\app\outputs\flutter-apk\app-release.apk `
  --out daemon\update-artifacts\android `
  --version-name 1.4.0 `
  --version-code 2 `
  --package com.example.lan_ai_cli_control `
  --min-supported-version-code 1 `
  --mandatory false `
  --release-notes "Private Android update"
```

脚本会生成或覆盖：

```text
daemon\update-artifacts\android\latest.json
daemon\update-artifacts\android\com.example.lan_ai_cli_control-1.4.0+2.apk
daemon\update-artifacts\android\com.example.lan_ai_cli_control-1.4.0+2.apk.sha256
```

`latest.json` 是移动端检查更新时读取的 manifest。

### 4. 启动或刷新 daemon

默认 artifact 目录就是：

```text
D:\AIProject\vibe-coding\daemon\update-artifacts\android
```

如果你使用上面的 `--out daemon\update-artifacts\android`，一般不需要额外配置。

启动 daemon：

```powershell
cd D:\AIProject\vibe-coding
npm run start:daemon
```

如果 daemon 已经在运行，只是替换了同一个 artifact 目录里的 APK 和 `latest.json`，通常不需要重启。
daemon 每次请求 `/api/app-updates/android/latest` 时都会重新读取 artifact。

如果你要使用其他 artifact 目录：

```powershell
$env:ANDROID_UPDATE_ARTIFACT_DIR='D:\somewhere\android-updates'
npm run start:daemon
```

这种情况下要重启 daemon，因为 artifact 目录是在 daemon 创建更新服务时注入的。

### 5. 手机端触发更新

手机必须已经和这个 daemon 配对并连接。

当前操作路径：

```text
Settings -> App update -> Check -> Download -> Install
```

安装时 Android 会弹系统确认页。用户确认后，Android 才会真正替换 APK。

## mandatory 和 min-supported 怎么选

普通可选更新：

```powershell
--min-supported-version-code 1 --mandatory false
```

低于某个版本必须提示 required：

```powershell
--min-supported-version-code 2 --mandatory false
```

所有看到这个版本的客户端都提示 required：

```powershell
--mandatory true
```

注意：当前代码里的 `mandatory` 只影响 App update 面板的状态和文案，不会真正阻断用户继续使用。
如果要做到“不更新不能继续使用”，需要额外实现强制更新门禁。

## 发布 smoke 检查

每次正式发给用户前，至少做一次真机 smoke。

1. 准备一台 Android 设备。
2. 安装旧的 release-signed APK，例如 `versionCode=1`。
3. 确保 daemon artifact 里的 `latest.json` 指向新 APK，例如 `versionCode=2`。
4. 启动 daemon。
5. 手机连接 daemon。
6. 进入 `Settings -> App update`。
7. 点 `Check`，应看到 update available 或 required update available。
8. 点 `Download`，等待下载完成。
9. 点 `Install`，应出现 Android 系统安装确认页。
10. 确认安装。
11. App 重启后确认安装版本已经变成新的 `versionCode`。
12. 再点 `Check`，应显示 up to date。

## 常见问题

### 手机显示安装失败

优先检查：

- 新旧 APK 的 packageName 是否都是 `com.example.lan_ai_cli_control`。
- 新旧 APK 是否用同一把 release keystore 签名。
- 新 APK 的 `versionCode` 是否更大。
- 设备上是否还装着 debug 签名版本。

### Check 看不到新版本

检查：

- daemon 是否连接的是你刚生成 artifact 的那台机器。
- `daemon\update-artifacts\android\latest.json` 是否存在。
- `latest.json` 里的 `versionCode` 是否大于手机当前安装版本。
- `latest.json` 里的 `available` 是否为 true。
- daemon 是否使用了不同的 `ANDROID_UPDATE_ARTIFACT_DIR`。

### Download 失败或一直 paused

检查：

- 手机和 daemon 是否在同一网络。
- 设备是否有足够存储空间。
- APK 文件是否还在 artifact 目录。
- `latest.json` 里的 `sizeBytes` 是否等于 APK 实际大小。
- `latest.json` 里的 `sha256` 是否匹配 APK。

### 断点续传后校验失败

移动端会删除不匹配的 `.part` 和 metadata，然后让用户重试下载。
如果反复出现，重新运行 `scripts\prepare-android-update.js`，避免手工改坏 `latest.json` 或 APK。

## 一条龙命令模板

发布 `1.4.0+2` 的模板：

```powershell
cd D:\AIProject\vibe-coding\mobile

$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'

flutter pub get
flutter build apk --release --build-name 1.4.0 --build-number 2

cd D:\AIProject\vibe-coding

node scripts\prepare-android-update.js `
  --apk mobile\build\app\outputs\flutter-apk\app-release.apk `
  --out daemon\update-artifacts\android `
  --version-name 1.4.0 `
  --version-code 2 `
  --package com.example.lan_ai_cli_control `
  --min-supported-version-code 1 `
  --mandatory false `
  --release-notes "Private Android update"

npm run start:daemon
```

如果 daemon 已经在同一个 artifact 目录上运行，最后一行可以不执行；手机端直接点 `Check`。
