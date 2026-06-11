import Flutter
import UIKit

final class BackgroundConversationSyncChannels: NSObject, FlutterStreamHandler {
  private static let methodChannelName = "lan_ai_cli_control/background_conversation_sync"
  private static let eventChannelName = "lan_ai_cli_control/background_conversation_sync/events"

  private weak var application: UIApplication?
  private var eventSink: FlutterEventSink?
  private var lastSnapshot: [String: Any?]?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  init(application: UIApplication = .shared) {
    self.application = application
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    let eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: binaryMessenger
    )
    eventChannel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let snapshot = lastSnapshot {
      events(snapshot)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "start":
      guard let request = request(from: call.arguments as? [String: Any]) else {
        result(FlutterError(
          code: "BAD_ARGUMENT",
          message: "Invalid background conversation sync request",
          details: nil
        ))
        return
      }
      result(startCleanupTask(request: request))
    case "snapshot":
      result(lastSnapshot ?? stoppedSnapshot(message: "iOS background cleanup is inactive"))
    case "stop":
      finishCleanupTask(message: "iOS background cleanup stopped")
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startCleanupTask(request: BackgroundConversationSyncRequest) -> [String: Any?] {
    endBackgroundTaskIfNeeded()
    backgroundTask = application?.beginBackgroundTask(withName: "ConversationSyncCleanup") { [weak self] in
      self?.finishCleanupTask(message: "iOS background cleanup expired")
    } ?? .invalid

    if backgroundTask == .invalid {
      let snapshot = makeSnapshot(
        status: "failed",
        runningCount: request.runningCount,
        waitingApprovalCount: request.waitingApprovalCount,
        message: "iOS background cleanup was rejected"
      )
      emit(snapshot)
      return snapshot
    }

    let snapshot = makeSnapshot(
      status: "stopped",
      runningCount: request.runningCount,
      waitingApprovalCount: request.waitingApprovalCount,
      message: "iOS uses resume backfill instead of continuous background sync"
    )
    emit(snapshot)
    finishCleanupTask(message: "iOS background cleanup completed")
    return snapshot
  }

  private func finishCleanupTask(message: String) {
    endBackgroundTaskIfNeeded()
    emit(stoppedSnapshot(message: message))
  }

  private func endBackgroundTaskIfNeeded() {
    guard backgroundTask != .invalid else { return }
    application?.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  private func stoppedSnapshot(message: String) -> [String: Any?] {
    makeSnapshot(
      status: "stopped",
      runningCount: 0,
      waitingApprovalCount: 0,
      message: message
    )
  }

  private func emit(_ snapshot: [String: Any?]) {
    if snapshot["status"] as? String == "stopped" {
      lastSnapshot = nil
    } else {
      lastSnapshot = snapshot
    }
    eventSink?(snapshot)
  }

  private func makeSnapshot(
    status: String,
    runningCount: Int,
    waitingApprovalCount: Int,
    message: String?
  ) -> [String: Any?] {
    [
      "status": status,
      "runningCount": runningCount,
      "waitingApprovalCount": waitingApprovalCount,
      "message": message,
    ]
  }

  private func request(from args: [String: Any]?) -> BackgroundConversationSyncRequest? {
    guard let args else { return nil }
    return BackgroundConversationSyncRequest(
      runningCount: args["runningCount"] as? Int ?? 0,
      waitingApprovalCount: args["waitingApprovalCount"] as? Int ?? 0
    )
  }
}

private struct BackgroundConversationSyncRequest {
  let runningCount: Int
  let waitingApprovalCount: Int
}
