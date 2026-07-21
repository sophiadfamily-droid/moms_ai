enum ConversationAnswer { positive, negative, ambiguous }

final class ConversationAnswerClassifier {
  const ConversationAnswerClassifier();

  ConversationAnswer classify(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty) return ConversationAnswer.ambiguous;
    final positive = _matchesPositive(normalized);
    final negative = _matchesNegative(normalized);
    if (positive == negative) return ConversationAnswer.ambiguous;
    return positive ? ConversationAnswer.positive : ConversationAnswer.negative;
  }

  bool _matchesPositive(String value) {
    const exact = {
      'oui',
      'd accord',
      'confirme',
      'garde cette information',
      'tu peux la memoriser',
      'oui retiens le',
      'oui retiens la',
    };
    if (exact.contains(value)) return true;
    return value.startsWith('oui ') &&
        const ['retiens', 'garde', 'memorise', 'confirme']
            .any(value.substring(4).startsWith);
  }

  bool _matchesNegative(String value) {
    const exact = {
      'non',
      'oublie',
      'annule',
      'ne retiens pas ca',
      'ne retiens pas cette information',
      'je ne veux pas que tu le memorises',
      'je ne veux pas que tu la memorises',
    };
    if (exact.contains(value)) return true;
    return value.startsWith('non ') || value.startsWith('ne retiens pas ');
  }

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.!?;,]+'), '')
        .replaceAll('’', "'")
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ç', 'c')
        .replaceAll("'", ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
