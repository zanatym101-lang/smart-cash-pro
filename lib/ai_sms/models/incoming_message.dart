class IncomingMessage {
  final String? id;
  final String sender;
  final String body;
  final DateTime? receivedAt;

  const IncomingMessage({
    this.id,
    required this.sender,
    required this.body,
    this.receivedAt,
  });

  String get normalizedSender => sender.trim().toLowerCase();

  String get normalizedBody => body.trim();
}
