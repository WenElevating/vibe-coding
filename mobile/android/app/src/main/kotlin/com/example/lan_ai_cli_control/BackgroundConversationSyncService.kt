package com.example.lan_ai_cli_control

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class BackgroundConversationSyncService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        val request = currentRequest
        currentRequest = null
        stopForegroundCompat()
        emit(
            "stopped",
            request?.runningCount ?: 0,
            request?.waitingApprovalCount ?: 0,
            "Background sync stopped"
        )
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startAnchor(intent)
            ACTION_STOP -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startAnchor(intent: Intent) {
        val request = BackgroundConversationSyncRequest(
            runningCount = intent.getIntExtra("runningCount", 0),
            waitingApprovalCount = intent.getIntExtra("waitingApprovalCount", 0),
            notificationTitle = intent.getStringExtra("notificationTitle") ?: "Vibe Coding",
            notificationBody = intent.getStringExtra("notificationBody")
                ?: "Background sync active"
        )
        currentRequest = request
        ensureChannel()
        startForeground(NOTIFICATION_ID, notification(request))
        emit(
            "active",
            request.runningCount,
            request.waitingApprovalCount,
            request.notificationBody
        )
    }

    private fun notification(request: BackgroundConversationSyncRequest) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(request.notificationTitle)
            .setContentText(request.notificationBody)
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopIntent()
            )
            .build()

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager()
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Conversation background sync",
                NotificationManager.IMPORTANCE_LOW
            )
        )
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun openAppIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutablePendingIntentFlag()
        )
    }

    private fun stopIntent(): PendingIntent =
        PendingIntent.getService(
            this,
            1,
            Intent(this, BackgroundConversationSyncService::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or immutablePendingIntentFlag()
        )

    companion object {
        private const val CHANNEL_ID = "conversation_background_sync"
        private const val NOTIFICATION_ID = 20_001
        private const val ACTION_START = "lan_ai_cli_control.background_conversation_sync.START"
        private const val ACTION_STOP = "lan_ai_cli_control.background_conversation_sync.STOP"
        private val mainHandler = Handler(Looper.getMainLooper())
        @Volatile
        private var currentRequest: BackgroundConversationSyncRequest? = null

        fun start(context: Context, request: BackgroundConversationSyncRequest) {
            val intent = Intent(context, BackgroundConversationSyncService::class.java).apply {
                action = ACTION_START
                putExtra("runningCount", request.runningCount)
                putExtra("waitingApprovalCount", request.waitingApprovalCount)
                putExtra("notificationTitle", request.notificationTitle)
                putExtra("notificationBody", request.notificationBody)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BackgroundConversationSyncService::class.java))
        }

        private fun emit(
            status: String,
            runningCount: Int,
            waitingApprovalCount: Int,
            message: String?
        ) {
            val snapshot = BackgroundConversationSyncChannels.snapshot(
                status,
                runningCount,
                waitingApprovalCount,
                message
            )
            mainHandler.post {
                BackgroundConversationSyncChannels.emit(snapshot)
            }
        }

        private fun immutablePendingIntentFlag(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
    }
}
