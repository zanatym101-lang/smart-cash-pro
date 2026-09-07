import 'models/parsed_transaction_draft.dart';

class RecentDraftStore {
  final List<ParsedTransactionDraft> _drafts = [];

  List<ParsedTransactionDraft> getAll() => List.unmodifiable(_drafts);

  void add(ParsedTransactionDraft draft) {
    _drafts.add(draft);
  }

  void addAll(Iterable<ParsedTransactionDraft> drafts) {
    _drafts.addAll(drafts);
  }

  void clear() {
    _drafts.clear();
  }
}
