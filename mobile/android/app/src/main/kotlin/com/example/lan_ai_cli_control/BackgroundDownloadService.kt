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
import android.os.PowerManager
import android.os.SystemClock
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
        startForeground(
            notificationIdFor(request.id),
            notification(request, request.resumeFromBytes, request.expectedBytes)
        )
        emit(
            request.id,
            "queued",
            request.resumeFromBytes,
            request.expectedBytes,
            request.destinationPath,
            null
        )
        thread(name = "bg-download-${request.id}") {
            runDownload(request, token)
        }
    }

    private fun runDownload(request: BackgroundDownloadRequest, token: ActiveDownload) {
        val wakeLock = acquireWakeLock(request.id)
        try {
            val destination = File(request.destinationPath)
            destination.parentFile?.mkdirs()
            val connection = URL(request.url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            request.headers.forEach { (name, value) ->
                connection.setRequestProperty(name, value)
            }
            connection.connect()
            val code = connection.responseCode
            if (code !in listOf(HttpURLConnection.HTTP_OK, HttpURLConnection.HTTP_PARTIAL)) {
                throw IllegalStateException("Download server returned HTTP $code")
            }
            val append = request.resumeFromBytes > 0 && code == HttpURLConnection.HTTP_PARTIAL
            val stream = connection.inputStream.buffered()
            var downloaded = if (append) request.resumeFromBytes else 0L
            token.lastProgressBytes = downloaded
            token.lastProgressAtMs = SystemClock.elapsedRealtime()
            FileOutputStream(destination, append).buffered().use { output ->
                stream.use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        if (token.cancelled) {
                            if (isCurrent(request.id, token)) {
                                emit(
                                    request.id,
                                    "cancelled",
                                    downloaded,
                                    request.expectedBytes,
                                    request.destinationPath,
                                    "Cancelled"
                                )
                            }
                            return
                        }
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        downloaded += read
                        if (shouldPublishProgress(token, downloaded, request.expectedBytes)) {
                            emit(
                                request.id,
                                "downloading",
                                downloaded,
                                request.expectedBytes,
                                request.destinationPath,
                                null
                            )
                            updateNotification(request, downloaded)
                        }
                    }
                    output.flush()
                }
            }
            if (isCurrent(request.id, token)) {
                emit(request.id, "completed", downloaded, request.expectedBytes, request.destinationPath, null)
            }
        } catch (error: Exception) {
            if (isCurrent(request.id, token)) {
                emit(
                    request.id,
                    "failed",
                    request.resumeFromBytes,
                    request.expectedBytes,
                    request.destinationPath,
                    error.message
                )
            }
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
            if (active.remove(request.id, token)) {
                stopSelfIfIdle(request.id)
            }
        }
    }

    private fun updateNotification(request: BackgroundDownloadRequest, downloaded: Long) {
        notificationManager().notify(
            notificationIdFor(request.id),
            notification(request, downloaded, request.expectedBytes)
        )
    }

    private fun shouldPublishProgress(
        token: ActiveDownload,
        downloaded: Long,
        total: Long
    ): Boolean {
        val now = SystemClock.elapsedRealtime()
        val byteStep = if (total > 0) {
            (total / 100).coerceAtLeast(256L * 1024L)
        } else {
            256L * 1024L
        }
        if (downloaded - token.lastProgressBytes < byteStep &&
            now - token.lastProgressAtMs < 500
        ) {
            return false
        }
        token.lastProgressBytes = downloaded
        token.lastProgressAtMs = now
        return true
    }

    private fun notification(
        request: BackgroundDownloadRequest,
        downloaded: Long,
        total: Long
    ) = NotificationCompat.Builder(this, CHANNEL_ID)
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
        val manager = notificationManager()
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Background downloads",
                NotificationManager.IMPORTANCE_LOW
            )
        )
    }

    private fun cancelDownload(id: String?) {
        if (id == null) return
        active[id]?.cancelled = true
    }

    private fun acquireWakeLock(id: String): PowerManager.WakeLock {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:BackgroundDownload:$id"
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun isCurrent(id: String, token: ActiveDownload): Boolean = active[id] === token

    private fun stopSelfIfIdle(id: String) {
        notificationManager().cancel(notificationIdFor(id))
        clearNotificationId(id)
        clearSnapshot(id)
        if (active.isEmpty()) stopSelf()
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        private const val CHANNEL_ID = "background_downloads"
        private const val NOTIFICATION_PROGRESS_MAX = 1000
        private const val WAKE_LOCK_TIMEOUT_MS = 2L * 60L * 60L * 1000L
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

        fun emit(
            id: String,
            status: String,
            downloaded: Long,
            total: Long,
            path: String,
            message: String?
        ) {
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
    @Volatile
    var cancelled: Boolean = false

    @Volatile
    var lastProgressAtMs: Long = 0

    @Volatile
    var lastProgressBytes: Long = 0
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
