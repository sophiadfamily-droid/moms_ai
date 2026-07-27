import 'natural_date_service.dart';

final class TaskCreationDraft {
  const TaskCreationDraft({
    required this.title,
    required this.dueDate,
    required this.priority,
    required this.isImportant,
  });

  final String title;
  final String dueDate;
  final String priority;
  final bool isImportant;
}

final class TaskCreationDraftService {
  const TaskCreationDraftService();

  static const _creationPhrases = [
    'cree une tache',
    'creer une tache',
    'ajoute une tache',
    'note moi une tache',
    'mets dans mes taches',
    'ajoute a ma liste de taches',
  ];

  TaskCreationDraft? extract(
    String message, {
    required DateTime referenceDate,
  }) {
    final normalized = _normalize(message);
    String? phrase;
    for (final candidate in _creationPhrases) {
      if (_containsPhrase(normalized, candidate)) {
        phrase = candidate;
        break;
      }
    }
    if (phrase == null) return null;
    var remainder = ' $normalized '.replaceFirst(' $phrase ', ' ').trim();
    final isImportant = RegExp(
      r'\b(prioritaire|priorite haute|haute priorite|urgent)\b',
    ).hasMatch(remainder);
    remainder = remainder
        .replaceAll(
          RegExp(r'\b(prioritaire|priorite haute|haute priorite|urgent)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'\b(pour|a faire|echeance|demain)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return TaskCreationDraft(
      title: remainder,
      dueDate: NaturalDateService.resolveDateFromText(
        message,
        now: referenceDate,
      ),
      priority: isImportant ? 'Haute' : '',
      isImportant: isImportant,
    );
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[àáâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll(RegExp('[ç]'), 'c')
      .replaceAll(RegExp("[’']"), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _containsPhrase(String text, String phrase) =>
      ' $text '.contains(' $phrase ');
}
