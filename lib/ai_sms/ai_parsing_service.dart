import 'models/ai_parse_result.dart';
import 'models/incoming_message.dart';

typedef AiSuggestionProvider = Future<AiParseResult?> Function(
  IncomingMessage message,
);

class AiParsingService {
  const AiParsingService({this.suggestionProvider});

  final AiSuggestionProvider? suggestionProvider;

  Future<AiParseResult?> suggest(IncomingMessage message) {
    final provider = suggestionProvider;
    if (provider == null) return Future<AiParseResult?>.value();
    return provider(message);
  }
}
