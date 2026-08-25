import '../models/life_context/life_context_projection.dart';

final class DashboardAnticipationInsight {
  const DashboardAnticipationInsight({
    required this.title,
    required this.message,
    required this.preparedChatMessage,
    this.sourceId,
  });

  final String title;
  final String message;
  final String preparedChatMessage;
  final String? sourceId;
}

/// Selects one read-only thought from the canonical Life Context.
///
/// It never creates a Task, Event or Shopping item. It only identifies a
/// preparation worth discussing and gives Chat the verified context.
final class DashboardAnticipationEngine {
  const DashboardAnticipationEngine();

  DashboardAnticipationInsight evaluate(LifeContextProjection projection) {
    final now = projection.generatedAt.toUtc();
    final items =
        projection.sections.expand((section) => section.items).toList();
    final candidates = <_DashboardCandidate>[];

    for (final item in items.where((item) => item.type == 'event')) {
      final facts = _facts(item);
      final title = facts[LifeContextProjectionFactKeys.title]?.trim() ?? '';
      final start = DateTime.tryParse(
        facts[LifeContextProjectionFactKeys.start] ?? '',
      )?.toUtc();
      if (title.isEmpty || start == null || start.isBefore(now)) continue;
      final kind = _eventKind(title);
      if (kind == null) continue;
      final horizon =
          kind.major ? const Duration(days: 90) : const Duration(days: 30);
      if (start.difference(now) > horizon) continue;

      final related = _relatedPreparationCount(
        items,
        title: title,
        keywords: kind.keywords,
      );
      candidates.add(
        _DashboardCandidate(
          id: 'dashboard:event:${item.id}',
          score: kind.score + (related > 0 ? 8 : 0),
          date: start,
          title: kind.cardTitle,
          message: kind.message(title, related),
          prompt: kind.prompt(title, start, related),
        ),
      );
    }

    for (final item in items.where((item) => item.type == 'person')) {
      final facts = _facts(item);
      if (facts[LifeContextProjectionFactKeys.personRole] != 'related') {
        continue;
      }
      final name =
          facts[LifeContextProjectionFactKeys.displayName]?.trim() ?? '';
      final birthDate = DateTime.tryParse(
        facts[LifeContextProjectionFactKeys.birthDate] ?? '',
      );
      if (name.isEmpty || birthDate == null) continue;
      final birthday = _nextOccurrence(birthDate, now);
      if (birthday.difference(now) > const Duration(days: 90)) continue;
      candidates.add(
        _DashboardCandidate(
          id: 'dashboard:birthday:${item.id}:${birthday.year}',
          score: 72,
          date: birthday,
          title: 'À garder en tête',
          message:
              'L’anniversaire de $name approche. On anticipe tranquillement ?',
          prompt: 'L’anniversaire de $name approche le '
              '${_frenchDate(birthday)}. Je peux t’aider à anticiper les préparatifs.',
        ),
      );
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });
    final selected = candidates.firstOrNull;
    if (selected != null) {
      return DashboardAnticipationInsight(
        title: selected.title,
        message: selected.message,
        preparedChatMessage: selected.prompt,
        sourceId: selected.id,
      );
    }

    return _calmFallback(projection, items);
  }

  DashboardAnticipationInsight _calmFallback(
    LifeContextProjection projection,
    List<LifeContextProjectionItem> items,
  ) {
    final primaryNames = items
        .where((item) => item.type == 'person')
        .map(_facts)
        .where(
          (facts) =>
              facts[LifeContextProjectionFactKeys.personRole] == 'primary',
        )
        .map((facts) => facts[LifeContextProjectionFactKeys.displayName] ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();
    final primary = primaryNames.firstOrNull;
    final futureEvents = items
        .where((item) => item.type == 'event')
        .map((item) => _EventLabel.tryFrom(item, projection.generatedAt))
        .whereType<_EventLabel>()
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (projection.state == LifeContextProjectionState.partial) {
      return DashboardAnticipationInsight(
        title:
            primary == null ? 'Je garde le fil' : 'Je garde le fil, $primary',
        message:
            'Je referai un point dès que toutes tes informations seront disponibles.',
        preparedChatMessage: 'Je n’ai pas encore toutes les informations pour '
            'faire une suggestion fiable. Je peux quand même t’aider sur ce que '
            'tu as en tête maintenant.',
      );
    }
    if (futureEvents.isNotEmpty) {
      final title = futureEvents.first.title;
      return DashboardAnticipationInsight(
        title:
            primary == null ? 'Je garde le fil' : 'Je garde le fil, $primary',
        message: 'Je garde un œil sur « $title ». Rien de nouveau à préparer.',
        preparedChatMessage: 'Pour le moment, je ne vois rien de nouveau à '
            'préparer autour de « $title ». Si tu veux, on peut quand même faire '
            'le point ensemble.',
      );
    }
    return DashboardAnticipationInsight(
      title:
          primary == null ? 'Tu peux souffler' : 'Tu peux souffler, $primary',
      message: 'Rien ne presse pour le moment.',
      preparedChatMessage: 'Pour le moment, je ne vois rien qui mérite de te '
          'charger davantage. Je suis là si tu veux faire le point.',
    );
  }

  int _relatedPreparationCount(
    List<LifeContextProjectionItem> items, {
    required String title,
    required Set<String> keywords,
  }) {
    final normalizedTitle = _normalize(title);
    return items.where((item) {
      if (item.type != 'task' && item.type != 'shoppingItem') return false;
      final label = _normalize(
        _facts(item)[LifeContextProjectionFactKeys.title] ?? '',
      );
      if (label.isEmpty) return false;
      return keywords.any(label.contains) ||
          normalizedTitle.split(' ').any(
                (word) => word.length >= 5 && label.contains(word),
              );
    }).length;
  }

  _EventPreparationKind? _eventKind(String title) {
    final value = _normalize(title);
    for (final kind in _eventKinds) {
      if (kind.keywords.any(value.contains)) return kind;
    }
    return null;
  }
}

final class _DashboardCandidate {
  const _DashboardCandidate({
    required this.id,
    required this.score,
    required this.date,
    required this.title,
    required this.message,
    required this.prompt,
  });

  final String id;
  final int score;
  final DateTime date;
  final String title;
  final String message;
  final String prompt;
}

final class _EventLabel {
  const _EventLabel(this.title, this.start);

  static _EventLabel? tryFrom(
    LifeContextProjectionItem item,
    DateTime now,
  ) {
    final facts = _facts(item);
    final title = facts[LifeContextProjectionFactKeys.title]?.trim() ?? '';
    final start = DateTime.tryParse(
      facts[LifeContextProjectionFactKeys.start] ?? '',
    )?.toUtc();
    if (title.isEmpty || start == null || start.isBefore(now.toUtc())) {
      return null;
    }
    return _EventLabel(title, start);
  }

  final String title;
  final DateTime start;
}

final class _EventPreparationKind {
  const _EventPreparationKind({
    required this.keywords,
    required this.major,
    required this.score,
    required this.cardTitle,
    required this.messagePrefix,
  });

  final Set<String> keywords;
  final bool major;
  final int score;
  final String cardTitle;
  final String messagePrefix;

  String message(String title, int relatedCount) => relatedCount > 0
      ? '$messagePrefix « $title » approche. Il y a déjà des éléments liés à réunir.'
      : '$messagePrefix « $title » approche. On anticipe tranquillement ?';

  String prompt(String title, DateTime date, int relatedCount) {
    final evidence = relatedCount > 0
        ? ' J’ai aussi repéré $relatedCount élément${relatedCount > 1 ? 's' : ''} lié${relatedCount > 1 ? 's' : ''} dans tes tâches ou tes courses.'
        : '';
    return '« $title » est prévu le ${_frenchDate(date)}.$evidence '
        'On peut préparer ce qu’il faut ensemble.';
  }
}

const _eventKinds = <_EventPreparationKind>[
  _EventPreparationKind(
    keywords: {'voyage', 'vacances', 'vol', 'train', 'depart', 'sejour'},
    major: true,
    score: 90,
    cardTitle: 'À préparer doucement',
    messagePrefix: 'Ton déplacement',
  ),
  _EventPreparationKind(
    keywords: {'demenagement', 'emmenagement'},
    major: true,
    score: 88,
    cardTitle: 'À anticiper',
    messagePrefix: 'Ce changement',
  ),
  _EventPreparationKind(
    keywords: {'rentree', 'inscription', 'ecole', 'creche'},
    major: true,
    score: 84,
    cardTitle: 'À garder en tête',
    messagePrefix: 'Cette étape',
  ),
  _EventPreparationKind(
    keywords: {'anniversaire', 'mariage', 'bapteme', 'ceremonie'},
    major: true,
    score: 80,
    cardTitle: 'À garder en tête',
    messagePrefix: 'Cet événement',
  ),
  _EventPreparationKind(
    keywords: {
      'passeport',
      'renouvellement',
      'dossier',
      'impot',
      'administratif'
    },
    major: false,
    score: 76,
    cardTitle: 'À anticiper',
    messagePrefix: 'Cette démarche',
  ),
  _EventPreparationKind(
    keywords: {'entretien', 'presentation', 'examen', 'concours'},
    major: false,
    score: 74,
    cardTitle: 'À préparer',
    messagePrefix: 'Ce rendez-vous',
  ),
  _EventPreparationKind(
    keywords: {'operation', 'hospital', 'consultation', 'medecin', 'dentiste'},
    major: false,
    score: 70,
    cardTitle: 'À préparer',
    messagePrefix: 'Ton rendez-vous',
  ),
];

Map<String, String> _facts(LifeContextProjectionItem item) => {
      for (final fact in item.facts) fact.key: fact.value,
    };

DateTime _nextOccurrence(DateTime source, DateTime now) {
  var candidate = DateTime.utc(now.year, source.month, source.day);
  if (candidate.month != source.month) {
    candidate = DateTime.utc(now.year, source.month, 28);
  }
  if (candidate.isBefore(DateTime.utc(now.year, now.month, now.day))) {
    candidate = DateTime.utc(now.year + 1, source.month, source.day);
    if (candidate.month != source.month) {
      candidate = DateTime.utc(now.year + 1, source.month, 28);
    }
  }
  return candidate;
}

String _frenchDate(DateTime value) {
  const months = <String>[
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[àâä]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[îï]'), 'i')
    .replaceAll(RegExp(r'[ôö]'), 'o')
    .replaceAll(RegExp(r'[ùûü]'), 'u')
    .replaceAll('ç', 'c');
