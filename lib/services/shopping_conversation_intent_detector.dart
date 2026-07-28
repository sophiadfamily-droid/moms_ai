final class ShoppingConversationItem {
  const ShoppingConversationItem({required this.title});

  final String title;
}

final class ShoppingConversationIntent {
  const ShoppingConversationIntent({
    required this.items,
    required this.isStockOut,
  });

  final List<ShoppingConversationItem> items;
  final bool isStockOut;
}

enum ShoppingConversationIntentKind {
  noMatch,
  stockoutDetected,
  explicitAddDetected,
  ambiguousMoreOrNoMore,
}

final class ShoppingConversationClassification {
  const ShoppingConversationClassification({
    required this.kind,
    this.items = const [],
  });

  final ShoppingConversationIntentKind kind;
  final List<ShoppingConversationItem> items;

  bool get isActionable =>
      kind == ShoppingConversationIntentKind.stockoutDetected ||
      kind == ShoppingConversationIntentKind.explicitAddDetected;
}

final class ShoppingConversationIntentDetector {
  const ShoppingConversationIntentDetector();

  static const int maximumItems = 12;
  static const Set<String> _stockVocabulary = {
    'banane',
    'bananes',
    'lait',
    'oeuf',
    'oeufs',
    'couche',
    'couches',
    'riz',
    'pain',
    'eau',
    'pates',
    'farine',
    'sucre',
    'cafe',
    'the',
    'beurre',
    'fromage',
    'yaourt',
    'yaourts',
    'savon',
    'shampoing',
    'dentifrice',
    'lessive',
    'papier toilette',
    'essuie tout',
  };

  ShoppingConversationIntent? detect(String input) {
    final classification = classify(input);
    if (!classification.isActionable) return null;
    return ShoppingConversationIntent(
      items: classification.items,
      isStockOut: classification.kind ==
          ShoppingConversationIntentKind.stockoutDetected,
    );
  }

  ShoppingConversationClassification classify(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty) {
      return const ShoppingConversationClassification(
        kind: ShoppingConversationIntentKind.noMatch,
      );
    }

    final ambiguous = _matchAmbiguousMoreOrNoMore(normalized);
    if (ambiguous != null) {
      final items = _parseItems(ambiguous);
      if (items.isNotEmpty) {
        return ShoppingConversationClassification(
          kind: ShoppingConversationIntentKind.ambiguousMoreOrNoMore,
          items: items,
        );
      }
    }
    if (_isNegativeContext(normalized)) {
      return const ShoppingConversationClassification(
        kind: ShoppingConversationIntentKind.noMatch,
      );
    }

    final explicit = _matchExplicitAddition(normalized);
    if (explicit != null) {
      return _classification(
        explicit,
        kind: ShoppingConversationIntentKind.explicitAddDetected,
      );
    }

    final missing = _matchMissingOrFinished(normalized);
    if (missing != null) {
      return _classification(
        missing,
        kind: ShoppingConversationIntentKind.stockoutDetected,
      );
    }

    final stockOut = _matchStockOut(normalized);
    if (stockOut == null) {
      return const ShoppingConversationClassification(
        kind: ShoppingConversationIntentKind.noMatch,
      );
    }
    final parsed = _parseItems(stockOut);
    if (parsed.isEmpty ||
        parsed.any((item) => !_isKnownStockItem(item.title))) {
      return const ShoppingConversationClassification(
        kind: ShoppingConversationIntentKind.noMatch,
      );
    }
    return ShoppingConversationClassification(
      kind: ShoppingConversationIntentKind.stockoutDetected,
      items: parsed,
    );
  }

  static String _normalize(String input) {
    var value = input.toLowerCase().trim();
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'œ': 'oe',
      '’': "'",
    };
    replacements.forEach((source, target) {
      value = value.replaceAll(source, target);
    });
    value = value
        .replaceAll(RegExp(r"['`´]"), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    value = value
        .replaceFirst(RegExp(r'^jai\b'), 'j ai')
        .replaceFirst(RegExp(r'^ya\b'), 'y a')
        .replaceFirst(RegExp(r'^on na\b'), 'on n a')
        .replaceFirst(RegExp(r'^jveu\b'), 'je veux')
        .replaceFirst(RegExp(r'^je veu\b'), 'je veux')
        .replaceAll(RegExp(r'\bplu\b'), 'plus')
        .replaceAll(RegExp(r'\bpu\b'), 'plus')
        .replaceAll(RegExp(r'\bdoeufs\b'), 'd oeufs')
        .replaceAll(RegExp(r'\bdoeuf\b'), 'd oeuf')
        .replaceAll(RegExp(r'\bcourse\b'), 'courses')
        .replaceFirst(RegExp(r'^met\b'), 'mets');
    return value;
  }

  static bool _isNegativeContext(String value) =>
      value.contains(RegExp(r'\bplus de .+ que\b')) ||
      value.startsWith('j ai achete ') ||
      value.startsWith('j ai acheté ') ||
      value.startsWith('achete en plus ') ||
      value.startsWith('ajoute plus ') ||
      value.startsWith('explique') ||
      value.startsWith('modifie la tache') ||
      value.startsWith('deplace le rendez-vous') ||
      value.contains('bonnes pour la sante') ||
      value.startsWith('j aime ');

  static String? _matchAmbiguousMoreOrNoMore(String value) {
    if (value.startsWith('je ne veux plus ') ||
        value.startsWith('je n en veux plus ')) {
      return null;
    }
    return RegExp(
      r'^(?:je veux|on veut|il veut)\s+plus\s+(?:de |du |de la |des |d )?(.+)$',
    ).firstMatch(value)?.group(1);
  }

  static String? _matchExplicitAddition(String value) {
    final match = RegExp(
      r'^(?:ajoute|mets?|achete)\s+(.+?)(?:\s+(?:aux?|dans (?:la liste de|les))\s+courses)$',
    ).firstMatch(value);
    return match?.group(1);
  }

  static String? _matchMissingOrFinished(String value) {
    final missing =
        RegExp(r'^(?:il\s+)?manque\s+(.+)$').firstMatch(value)?.group(1);
    if (missing != null) return missing;
    return RegExp(r'^(?:j ai|on a)\s+fini\s+(.+)$').firstMatch(value)?.group(1);
  }

  static String? _matchStockOut(String value) => RegExp(
        r'^(?:j ai|je n ai|y a|il y a|on a|on n a)\s+plus\s+(.+)$',
      ).firstMatch(value)?.group(1);

  static ShoppingConversationClassification _classification(
    String raw, {
    required ShoppingConversationIntentKind kind,
  }) {
    final items = _parseItems(raw);
    return items.isEmpty
        ? const ShoppingConversationClassification(
            kind: ShoppingConversationIntentKind.noMatch,
          )
        : ShoppingConversationClassification(kind: kind, items: items);
  }

  static List<ShoppingConversationItem> _parseItems(String raw) {
    final cleaned = raw
        .replaceFirst(
          RegExp(r'^(?:de |du |de la |des |d |le |la |les |un |une )'),
          '',
        )
        .trim();
    if (cleaned.isEmpty) return const [];
    final seen = <String>{};
    final items = <ShoppingConversationItem>[];
    for (var part in cleaned.split(RegExp(r'\s+(?:ni|et)\s+'))) {
      part = part
          .replaceFirst(
            RegExp(r'^(?:de |du |de la |des |d |le |la |les |un |une )'),
            '',
          )
          .trim();
      if (part.isEmpty || part.length > 120 || !seen.add(part)) continue;
      items.add(ShoppingConversationItem(title: _displayTitle(part)));
      if (items.length == maximumItems) break;
    }
    return List.unmodifiable(items);
  }

  static String _displayTitle(String value) => value
      .replaceAll(RegExp(r'\boeufs\b'), 'œufs')
      .replaceAll(RegExp(r'\boeuf\b'), 'œuf');

  static bool _isKnownStockItem(String title) {
    final normalized = title.replaceAll('œ', 'oe');
    return _stockVocabulary.any(
      (item) =>
          normalized == item ||
          normalized.endsWith(' $item') ||
          normalized.startsWith('$item '),
    );
  }
}
