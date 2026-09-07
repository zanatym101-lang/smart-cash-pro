abstract class TransactionRepository {
  Future<void> reverseTransaction(String txnId, {String? reason});
}
