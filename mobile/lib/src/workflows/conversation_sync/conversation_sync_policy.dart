class ConversationSyncPolicy {
  const ConversationSyncPolicy({
    this.terminalGrace = const Duration(seconds: 45),
    this.backgroundDisconnectGrace = const Duration(seconds: 30),
    this.consumerLagQueueLimit = 256,
  });

  final Duration terminalGrace;
  final Duration backgroundDisconnectGrace;
  final int consumerLagQueueLimit;
}
