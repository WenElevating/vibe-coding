package com.example.lan_ai_cli_control

import android.content.Context
import androidx.annotation.MainThread
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
                            result.error(
                                "BAD_ARGUMENT",
                                "Invalid background download request",
                                null
                            )
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
                        if (id != null) {
                            BackgroundDownloadService.cancel(context.applicationContext, id)
                        }
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
