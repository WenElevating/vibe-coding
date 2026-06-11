package com.example.lan_ai_cli_control

import android.content.Context
import androidx.annotation.MainThread
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object BackgroundConversationSyncChannels {
    private const val METHOD_CHANNEL = "lan_ai_cli_control/background_conversation_sync"
    private const val EVENT_CHANNEL = "lan_ai_cli_control/background_conversation_sync/events"
    private var eventSink: EventChannel.EventSink? = null
    private var lastSnapshot: Map<String, Any?>? = null

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "start" -> {
                        val args = call.arguments as? Map<*, *>
                        val request = requestFromMap(args)
                        if (request == null) {
                            result.error(
                                "BAD_ARGUMENT",
                                "Invalid background conversation sync request",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            BackgroundConversationSyncService.start(
                                context.applicationContext,
                                request
                            )
                            val snapshot = snapshot(
                                "starting",
                                request.runningCount,
                                request.waitingApprovalCount,
                                "Starting background sync"
                            )
                            emit(snapshot)
                            result.success(snapshot)
                        } catch (error: Exception) {
                            val snapshot = snapshot(
                                "denied",
                                request.runningCount,
                                request.waitingApprovalCount,
                                error.message ?: "Android rejected background sync"
                            )
                            emit(snapshot)
                            result.success(snapshot)
                        }
                    }
                    "stop" -> {
                        BackgroundConversationSyncService.stop(context.applicationContext)
                        emit(snapshot("stopped", 0, 0, "Background sync stopped"))
                        result.success(null)
                    }
                    "snapshot" -> result.success(lastSnapshot)
                    else -> result.notImplemented()
                }
            }

        var ownedSink: EventChannel.EventSink? = null
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ownedSink = events
                    eventSink = events
                    lastSnapshot?.let { events?.success(it) }
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
        val status = snapshot["status"] as? String
        if (status == "stopped") {
            lastSnapshot = null
        } else {
            lastSnapshot = snapshot
        }
        eventSink?.success(snapshot)
    }

    fun snapshot(
        status: String,
        runningCount: Int,
        waitingApprovalCount: Int,
        message: String?
    ): Map<String, Any?> = mapOf(
        "status" to status,
        "runningCount" to runningCount,
        "waitingApprovalCount" to waitingApprovalCount,
        "message" to message
    )

    private fun requestFromMap(args: Map<*, *>?): BackgroundConversationSyncRequest? {
        if (args == null) return null
        return BackgroundConversationSyncRequest(
            runningCount = (args["runningCount"] as? Number)?.toInt() ?: 0,
            waitingApprovalCount = (args["waitingApprovalCount"] as? Number)?.toInt() ?: 0,
            notificationTitle = args["notificationTitle"] as? String ?: "Vibe Coding",
            notificationBody = args["notificationBody"] as? String ?: "Background sync active"
        )
    }
}

data class BackgroundConversationSyncRequest(
    val runningCount: Int,
    val waitingApprovalCount: Int,
    val notificationTitle: String,
    val notificationBody: String
)
