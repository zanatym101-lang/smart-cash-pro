import 'package:meta/meta.dart';
import '../models/money.dart';
import '../models/wallet_ledger.dart';

/// Base class for all wallet-related accounting events.
@immutable
abstract class WalletAccountingEvent {
  const WalletAccountingEvent();
}

/// Emitted when a transaction is recorded against a wallet.
@immutable
class WalletTransactionRecordedEvent extends WalletAccountingEvent {
  const WalletTransactionRecordedEvent({
    required this.eventId,
    required this.walletId,
    required this.transactionId,
    required this.type,
    required this.amount,
    required this.fee,
    required this.timestamp,
    this.customerId,
    this.reference,
  });

  final String eventId;
  final String walletId;
  final String transactionId;
  final WalletTransactionType type;
  final Money amount;
  final Money fee;
  final DateTime timestamp;
  final String? customerId;
  final String? reference;
}
