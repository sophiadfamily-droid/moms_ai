abstract final class FrenchQuestionDetector {
  static bool isQuestion(String text) {
    final raw = text.trim().toLowerCase();
    if (raw.isEmpty) return false;
    if (raw.contains('?')) return true;

    final normalized = raw
        .replaceAll('’', "'")
        .replaceAll('œ', 'oe')
        .replaceAll(RegExp(r"[^a-z0-9àâäéèêëîïôöùûüç']+"), ' ')
        .replaceAll("'", ' ')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c')
        .trim();

    return RegExp(
          r'^(?:est ce que|est ce qu|est ce|qu est ce que|qu est ce qu|'
          r'a quel(?:le|les|s)?|quel(?:le|les|s)?|'
          r'lequel|laquelle|lesquels|lesquelles|'
          r'pourquoi|comment|combien|qui|que|quoi|ou)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^quand (?:est ce que|est ce qu|dois je|puis je|vais je|suis je|'
          r'je (?:dois|peux|vais|suis|fais|prefere|travaille)|'
          r'mon|ma|mes|notre|nos|le|la|les)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(?:peux tu|tu peux|pourrais tu|pouvez vous|pourriez vous|'
          r'sais tu|savez vous|dis moi|dites moi)\b',
        ).hasMatch(normalized);
  }
}
