class SmsFlowAnalyticsSnapshot {
  const SmsFlowAnalyticsSnapshot({
    required this.parsedMessages,
    required this.successfulExecutions,
    required this.duplicateBlocks,
    required this.duplicateWarnings,
    required this.overrideExecutions,
  });

  final int parsedMessages;
  final int successfulExecutions;
  final int duplicateBlocks;
  final int duplicateWarnings;
  final int overrideExecutions;

  double get successRate =>
      parsedMessages == 0 ? 0 : successfulExecutions / parsedMessages;

  double get duplicateRate =>
      parsedMessages == 0 ? 0 : (duplicateBlocks + duplicateWarnings) / parsedMessages;

  double get overrideRate =>
      successfulExecutions == 0 ? 0 : overrideExecutions / successfulExecutions;

  Map<String, Object?> toJson() {
    return {
      'parsedMessages': parsedMessages,
      'successfulExecutions': successfulExecutions,
      'duplicateBlocks': duplicateBlocks,
      'duplicateWarnings': duplicateWarnings,
      'overrideExecutions': overrideExecutions,
      'successRate': successRate,
      'duplicateRate': duplicateRate,
      'overrideRate': overrideRate,
    };
  }
}

class SmsFlowAnalyticsTracker {
  int _parsedMessages = 0;
  int _successfulExecutions = 0;
  int _duplicateBlocks = 0;
  int _duplicateWarnings = 0;
  int _overrideExecutions = 0;

  void recordParsedMessage() => _parsedMessages++;

  void recordSuccessfulExecution({bool usedOverride = false}) {
    _successfulExecutions++;
    if (usedOverride) {
      _overrideExecutions++;
    }
  }

  void recordDuplicateBlock() => _duplicateBlocks++;

  void recordDuplicateWarning() => _duplicateWarnings++;

  SmsFlowAnalyticsSnapshot snapshot() {
    return SmsFlowAnalyticsSnapshot(
      parsedMessages: _parsedMessages,
      successfulExecutions: _successfulExecutions,
      duplicateBlocks: _duplicateBlocks,
      duplicateWarnings: _duplicateWarnings,
      overrideExecutions: _overrideExecutions,
    );
  }
}
