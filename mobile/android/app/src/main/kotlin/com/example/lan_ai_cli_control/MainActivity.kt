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
    private val installAction: String
        get() = "$packageName.APP_UPDATE_INSTALL_STATUS"
    private val installStatusPermission: String
        get() = "$packageName.permission.APP_UPDATE_INSTALL_STATUS"

    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private val pendingInstallSessionIds = mutableSetOf<Int>()

    private val installReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE
            )
            val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
            if (!pendingInstallSessionIds.contains(sessionId)) return
            val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            val installedPackageName = intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME)

            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                val confirmation = confirmationIntent(intent)
                if (confirmation == null) {
                    pendingInstallSessionIds.remove(sessionId)
                    sendInstallEvent(
                        "failed",
                        sessionId,
                        "Android installer confirmation was unavailable.",
                        installedPackageName
                    )
                    return
                }
                confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirmation)
                    sendInstallEvent("pendingUserAction", sessionId, message, installedPackageName)
                } catch (error: Exception) {
                    pendingInstallSessionIds.remove(sessionId)
                    sendInstallEvent(
                        "failed",
                        sessionId,
                        error.message ?: "Android installer confirmation could not be opened.",
                        installedPackageName
                    )
                }
                return
            }

            val mapped = when (status) {
                PackageInstaller.STATUS_SUCCESS -> "success"
                PackageInstaller.STATUS_FAILURE_ABORTED -> "cancelled"
                else -> "failed"
            }
            pendingInstallSessionIds.remove(sessionId)
            sendInstallEvent(mapped, sessionId, message, installedPackageName)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(canRequestPackageInstalls())
                }
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "availableBytes" -> {
                    result.success(availableBytes())
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("BAD_ARGUMENT", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(commitPackageSession(filePath))
                    } catch (error: Exception) {
                        result.error("INSTALL_COMMIT_FAILED", error.message, null)
                    }
                }
                "recoverInstallSession" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: -1
                    result.success(recoverSession(sessionId))
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        BackgroundDownloadChannels.register(this, flutterEngine)
        BackgroundConversationSyncChannels.register(this, flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerInstallReceiver()
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(installReceiver)
            } catch (_: IllegalArgumentException) {
                // Receiver can already be gone during activity teardown on some ROMs.
            }
            receiverRegistered = false
        }
        super.onDestroy()
    }

    private fun commitPackageSession(filePath: String): Int {
        val apk = File(filePath)
        require(apk.isFile) { "APK file does not exist: $filePath" }

        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply {
            setAppPackageName(packageName)
        }
        val sessionId = installer.createSession(params)
        var session: PackageInstaller.Session? = null
        try {
            val activeSession = installer.openSession(sessionId)
            session = activeSession
            apk.inputStream().use { input ->
                activeSession.openWrite("app_update_$sessionId.apk", 0, apk.length()).use { output ->
                    input.copyTo(output)
                    activeSession.fsync(output)
                }
            }

            val intent = Intent(installAction).setPackage(packageName)
            val mutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                sessionId,
                intent,
                flags
            )

            pendingInstallSessionIds.add(sessionId)
            activeSession.commit(pendingIntent.intentSender)
            return sessionId
        } catch (error: Exception) {
            pendingInstallSessionIds.remove(sessionId)
            try {
                installer.abandonSession(sessionId)
            } catch (_: Exception) {
                // Preserve the original install failure for Dart callers.
            }
            throw error
        } finally {
            session?.close()
        }
    }

    private fun recoverSession(sessionId: Int): Map<String, Any?>? {
        if (sessionId < 0) return null
        val info = packageManager.packageInstaller.getSessionInfo(sessionId) ?: return null
        if (!isRecoverableInstallerSession(info)) return null
        pendingInstallSessionIds.add(sessionId)
        return mapOf(
            "status" to "pendingUserAction",
            "sessionId" to sessionId,
            "message" to "Package installer session is awaiting user confirmation.",
            "appPackageName" to info.appPackageName
        )
    }

    private fun isRecoverableInstallerSession(info: PackageInstaller.SessionInfo): Boolean {
        if (info.isActive) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        if (isSessionCommitted(info)) return true
        if (isSessionSealed(info)) return true
        return false
    }

    private fun isSessionCommitted(info: PackageInstaller.SessionInfo): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && info.isCommitted
    }

    private fun isSessionSealed(info: PackageInstaller.SessionInfo): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && info.isSealed
    }

    private fun availableBytes(): Long {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return cacheDir.freeSpace
        return try {
            val storage = getSystemService(StorageManager::class.java)
            storage.getAllocatableBytes(storage.getUuidForPath(cacheDir))
        } catch (_: Exception) {
            cacheDir.freeSpace
        }
    }

    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallPermissionSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun registerInstallReceiver() {
        val filter = IntentFilter(installAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                installReceiver,
                filter,
                installStatusPermission,
                null,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(installReceiver, filter, installStatusPermission, null)
        }
        receiverRegistered = true
    }

    private fun confirmationIntent(intent: Intent): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
    }

    private fun sendInstallEvent(
        status: String,
        sessionId: Int,
        message: String?,
        appPackageName: String? = null
    ) {
        eventSink?.success(
            mapOf(
                "status" to status,
                "sessionId" to if (sessionId >= 0) sessionId else null,
                "appPackageName" to appPackageName,
                "message" to message
            )
        )
    }
}
