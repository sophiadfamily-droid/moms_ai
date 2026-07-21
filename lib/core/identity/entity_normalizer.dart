final class EntityNormalizedValue {
  final String displayValue;
  final String normalizedLabel;
  final String comparisonKey;

  const EntityNormalizedValue({
    required this.displayValue,
    required this.normalizedLabel,
    required this.comparisonKey,
  });
}

abstract final class EntityNormalizer {
  static EntityNormalizedValue normalize(String value) {
    final displayValue = _cleanSpacingAndPunctuation(value);
    final normalizedLabel = displayValue.toLowerCase();
    final comparisonKey = _stripDiacritics(normalizedLabel);
    return EntityNormalizedValue(
      displayValue: displayValue,
      normalizedLabel: normalizedLabel,
      comparisonKey: comparisonKey,
    );
  }

  static String comparisonKey(String value) => normalize(value).comparisonKey;

  static String _cleanSpacingAndPunctuation(String value) {
    var result = value
        .replaceAll(RegExp(r'[\u200B-\u200D\u2060\uFEFF]'), '')
        .replaceAll(RegExp(r'[\u00A0\u202F]'), ' ')
        .replaceAll(RegExp(r'[‘’‛`´]'), "'")
        .replaceAll(RegExp(r'[‐‑‒–—―]'), '-')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    result = result.replaceAll(
      RegExp(r'''^[\s.,;:!?"'«»()[\]{}]+|[\s.,;:!?"'«»()[\]{}]+$'''),
      '',
    );
    return result.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _stripDiacritics(String value) {
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'å': 'a',
      'ā': 'a',
      'ă': 'a',
      'ą': 'a',
      'æ': 'ae',
      'ç': 'c',
      'ć': 'c',
      'č': 'c',
      'ď': 'd',
      'đ': 'd',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ē': 'e',
      'ė': 'e',
      'ę': 'e',
      'ě': 'e',
      'ğ': 'g',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ī': 'i',
      'į': 'i',
      'ł': 'l',
      'ñ': 'n',
      'ń': 'n',
      'ň': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ø': 'o',
      'ō': 'o',
      'œ': 'oe',
      'ř': 'r',
      'ś': 's',
      'š': 's',
      'ß': 'ss',
      'ť': 't',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ū': 'u',
      'ů': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'ž': 'z',
      'ź': 'z',
      'ż': 'z',
    };
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x0300 && rune <= 0x036f) continue;
      final character = String.fromCharCode(rune);
      buffer.write(replacements[character] ?? character);
    }
    return buffer.toString();
  }
}
