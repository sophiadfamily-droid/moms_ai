import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/routine_model.dart';
import 'auth_service.dart';
import 'conversation_answer_classifier.dart';
import 'routine_repository.dart';

enum RoutineConversationResultType {
  notRoutine,
  clarification,
  confirmation,
  created,
  cancelled,
  ambiguous,
  unavailable,
}

final class RoutineConversationResult {
  const RoutineConversationResult(this.type, this.message);
  final RoutineConversationResultType type;
  final String message;
}

final class RoutineConversationService {
  factory RoutineConversationService.production() {
    final service = RoutineConversationService(
      repository: FirestoreRoutineRepository(),
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    unawaited(service.restoreActive());
    return service;
  }

  RoutineConversationService({
    required RoutineRepository repository,
    required String? Function() currentAccountScopeId,
    DateTime Function()? clock,
  })  : _repository = repository,
        _currentAccountScopeId = currentAccountScopeId,
        _clock = clock ?? DateTime.now;

  final RoutineRepository _repository;
  final String? Function() _currentAccountScopeId;
  final DateTime Function() _clock;
  final ConversationAnswerClassifier _answers =
      const ConversationAnswerClassifier();
  RoutineProposal? _pending;

  bool get hasPending => _pending != null;

  Future<bool> restoreActive({bool includeCommitted = false}) async {
    if (_pending != null) return true;
    try {
      final scope = _currentAccountScopeId();
      if (scope == null || scope.isEmpty) return false;
      var restored = await _repository.findActiveProposal(scope);
      if (restored == null && includeCommitted) {
        final latest = await _repository.findLatestProposal(scope);
        if (latest?.state == RoutineProposalState.committed) {
          restored = latest;
        }
      }
      if (restored == null || restored.accountScopeId != scope) return false;
      _pending = restored;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<RoutineConversationResult> process(
    String message, {
    required String logicalRequestId,
  }) async {
    if (_pending != null &&
        _isExplicitRoutine(message) &&
        _pending!.logicalRequestId != logicalRequestId) {
      _pending = null;
    }
    if (_pending == null &&
        !_isExplicitRoutine(message) &&
        _couldContinueRoutine(message)) {
      await restoreActive(
        includeCommitted:
            _answers.classify(message) == ConversationAnswer.positive,
      );
    }
    final pending = _pending;
    if (pending != null) {
      final answer = _answers.classify(message);
      if (pending.isComplete && answer == ConversationAnswer.positive) {
        final result = await _repository.commitProposal(
          pending,
          _clock().toUtc(),
        );
        if (!result.isSuccess) {
          return const RoutineConversationResult(
            RoutineConversationResultType.unavailable,
            'Je n’ai pas pu vérifier la création. Tu pourras réessayer sans '
            'créer de doublon.',
          );
        }
        _pending = null;
        return const RoutineConversationResult(
          RoutineConversationResultType.created,
          'C’est fait. La routine est maintenant prise en compte.',
        );
      }
      if (pending.isComplete && answer == ConversationAnswer.negative) {
        final declined = pending.copyWith(
          state: RoutineProposalState.declined,
          updatedAt: _clock().toUtc(),
        );
        final persisted = await _repository.updateProposal(declined);
        if (persisted == null) {
          return const RoutineConversationResult(
            RoutineConversationResultType.unavailable,
            'Je n’ai pas pu vérifier l’annulation pour le moment.',
          );
        }
        _pending = null;
        return const RoutineConversationResult(
          RoutineConversationResultType.cancelled,
          'D’accord, cette routine n’a pas été créée.',
        );
      }
      if (pending.isComplete) {
        return const RoutineConversationResult(
          RoutineConversationResultType.ambiguous,
          'Dis-moi simplement oui ou non pour confirmer cette routine.',
        );
      }
      if (RoutineTimeExpressionNormalizer.hasUnrecognizedExpression(message)) {
        return const RoutineConversationResult(
          RoutineConversationResultType.clarification,
          'À quelle heure commence cette routine ?',
        );
      }
      final draft = _RoutineDraft.fromProposal(pending).completeFrom(message);
      final updated = draft.toProposal(
        proposalId: pending.proposalId,
        state: draft.isComplete
            ? RoutineProposalState.awaitingConfirmation
            : RoutineProposalState.collecting,
        createdAt: pending.createdAt,
        updatedAt: _clock().toUtc(),
        expiresAt: pending.expiresAt,
      );
      final persisted = await _repository.updateProposal(updated);
      if (persisted == null) {
        return const RoutineConversationResult(
          RoutineConversationResultType.unavailable,
          'Je n’ai pas pu conserver cette précision pour le moment.',
        );
      }
      _pending = persisted;
      return persisted.isComplete
          ? RoutineConversationResult(
              RoutineConversationResultType.confirmation,
              _RoutineDraft.fromProposal(persisted).summary,
            )
          : RoutineConversationResult(
              RoutineConversationResultType.clarification,
              _RoutineDraft.fromProposal(persisted).question,
            );
    }

    if (!_isExplicitRoutine(message)) {
      return const RoutineConversationResult(
        RoutineConversationResultType.notRoutine,
        '',
      );
    }
    final scope = _currentAccountScopeId();
    if (scope == null || scope.isEmpty) {
      return const RoutineConversationResult(
        RoutineConversationResultType.unavailable,
        'Je ne peux pas préparer cette routine pour le moment.',
      );
    }
    if (RoutineTimeExpressionNormalizer.hasUnrecognizedExpression(message)) {
      return const RoutineConversationResult(
        RoutineConversationResultType.clarification,
        'À quelle heure commence cette routine ?',
      );
    }
    final draft = _RoutineDraft.parse(
      message,
      accountScopeId: scope,
      logicalRequestId: logicalRequestId,
    );
    if (draft == null) {
      return const RoutineConversationResult(
        RoutineConversationResultType.notRoutine,
        '',
      );
    }
    final now = _clock().toUtc();
    final proposalId = _proposalId(scope, logicalRequestId);
    final proposal = draft.toProposal(
      proposalId: proposalId,
      state: draft.isComplete
          ? RoutineProposalState.awaitingConfirmation
          : RoutineProposalState.collecting,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(const Duration(days: 30)),
    );
    final persisted = await _repository.createOrVerifyProposal(proposal);
    if (persisted == null) {
      return const RoutineConversationResult(
        RoutineConversationResultType.unavailable,
        'Je n’ai pas pu conserver cette proposition pour le moment.',
      );
    }
    if (persisted.state == RoutineProposalState.committed) {
      return const RoutineConversationResult(
        RoutineConversationResultType.created,
        'C’est fait. La routine est maintenant prise en compte.',
      );
    }
    if (persisted.state == RoutineProposalState.declined ||
        persisted.state == RoutineProposalState.cancelled) {
      return const RoutineConversationResult(
        RoutineConversationResultType.cancelled,
        'D’accord, cette routine n’a pas été créée.',
      );
    }
    _pending = persisted;
    final restoredDraft = _RoutineDraft.fromProposal(persisted);
    return persisted.isComplete
        ? RoutineConversationResult(
            RoutineConversationResultType.confirmation,
            restoredDraft.summary,
          )
        : RoutineConversationResult(
            RoutineConversationResultType.clarification,
            restoredDraft.question,
          );
  }

  static String _proposalId(String scope, String logicalRequestId) => sha256
      .convert(utf8.encode('routine-v1|$scope|$logicalRequestId'))
      .toString();

  bool _couldContinueRoutine(String input) {
    if (_answers.classify(input) != ConversationAnswer.ambiguous) return true;
    final normalized = _normalize(input);
    final normalizedTime =
        RoutineTimeExpressionNormalizer.normalizeForAnalysis(input);
    return _isExplicitRoutine(input) ||
        RegExp(r'\d{1,2}\s*h|\d+\s*(?:minutes?|heures?)')
            .hasMatch(normalized) ||
        RegExp(r'\b\d{2}:\d{2}\b').hasMatch(normalizedTime) ||
        RegExp(r'\d{1,2}/\d{1,2}/\d{4}|\d{4}-\d{2}-\d{2}').hasMatch(normalized);
  }

  static bool _isExplicitRoutine(String input) {
    final text = _normalize(input);
    if (text.contains('?') ||
        text.contains('peut etre') ||
        text.contains('peut-etre') ||
        text.contains("j'aimerais") ||
        text.startsWith('avant') ||
        text.contains('ma soeur ') ||
        text.contains('ma sœur ') ||
        text.contains('mon frere ')) {
      return false;
    }
    return text.contains('tous les ') ||
        text.contains('toutes les ') ||
        text.contains('du lundi au vendredi') ||
        text.contains('une semaine sur deux') ||
        text.contains('chaque mois');
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');
}

final class RoutineTimeExpressionNormalizer {
  const RoutineTimeExpressionNormalizer._();

  static const _hourWords = <String, int>{
    'zero': 0,
    'un': 1,
    'une': 1,
    'deux': 2,
    'trois': 3,
    'quatre': 4,
    'cinq': 5,
    'six': 6,
    'sept': 7,
    'huit': 8,
    'neuf': 9,
    'dix': 10,
    'onze': 11,
    'douze': 12,
    'treize': 13,
    'quatorze': 14,
    'quinze': 15,
    'seize': 16,
    'dix sept': 17,
    'dix huit': 18,
    'dix neuf': 19,
    'vingt': 20,
    'vingt et un': 21,
    'vingt et une': 21,
    'vingt deux': 22,
    'vingt trois': 23,
  };

  static final RegExp _expression = RegExp(
    '\\b(${[
      ..._hourWords.keys.toList()
        ..sort((left, right) => right.length.compareTo(left.length)),
      r'\d{1,2}',
    ].join('|')})'
    r'\s*(?:(?:heures?|h)(?:\s*(et\s+demie|demie|trente|\d{1,2}))?'
    r'|:\s*(\d{1,2}))\b(?!\s+moins\b)',
  );

  static String normalizeForAnalysis(String input) {
    var text = RoutineConversationService._normalize(input)
        .replaceAll("'", ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    text = text.replaceAllMapped(_expression, (match) {
      final hourToken = match.group(1)!;
      final hour = int.tryParse(hourToken) ?? _hourWords[hourToken];
      final minuteToken = match.group(2);
      final minute = match.group(3) == null
          ? switch (minuteToken) {
              'et demie' || 'demie' || 'trente' => 30,
              null => 0,
              _ => int.tryParse(minuteToken),
            }
          : int.tryParse(match.group(3)!);
      if (hour == null || minute == null || hour > 23 || minute > 59) {
        return match.group(0)!;
      }
      return '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
    });
    return text
        .replaceAllMapped(
          RegExp(r'\s*([,;.!?])\s*'),
          (match) => '${match.group(1)} ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool hasUnrecognizedExpression(String input) {
    final normalized = normalizeForAnalysis(input);
    return RegExp(
      r'\b(?:de|a|vers|entre)\b[^,;.!?]{0,40}\bheures?\b',
    ).hasMatch(normalized);
  }
}

final class _RoutineDraft {
  const _RoutineDraft({
    required this.accountScopeId,
    required this.logicalRequestId,
    required this.title,
    required this.recurrenceType,
    required this.days,
    required this.startTime,
    required this.durationMinutes,
    required this.anchorDateIso,
    required this.weekOfMonth,
  });

  final String accountScopeId;
  final String logicalRequestId;
  final String? title;
  final RoutineRecurrenceType? recurrenceType;
  final List<int> days;
  final String? startTime;
  final int? durationMinutes;
  final String? anchorDateIso;
  final int? weekOfMonth;

  factory _RoutineDraft.fromProposal(RoutineProposal proposal) => _RoutineDraft(
        accountScopeId: proposal.accountScopeId,
        logicalRequestId: proposal.logicalRequestId,
        title: proposal.title,
        recurrenceType: proposal.recurrenceType,
        days: proposal.days,
        startTime: proposal.startTime,
        durationMinutes: proposal.durationMinutes,
        anchorDateIso: proposal.anchorDateIso,
        weekOfMonth: proposal.weekOfMonth,
      );

  bool get isComplete =>
      title != null &&
      recurrenceType != null &&
      (recurrenceType == RoutineRecurrenceType.weekdays || days.isNotEmpty) &&
      startTime != null &&
      durationMinutes != null &&
      (recurrenceType != RoutineRecurrenceType.biweekly ||
          anchorDateIso != null) &&
      (recurrenceType != RoutineRecurrenceType.monthlyNthWeekday ||
          (days.length == 1 &&
              (weekOfMonth == -1 ||
                  (weekOfMonth != null &&
                      weekOfMonth! >= 1 &&
                      weekOfMonth! <= 5))));

  String get question {
    if (title == null) {
      return 'Quelle activité veux-tu ajouter à cette routine ?';
    }
    if (recurrenceType == null ||
        (days.isEmpty && recurrenceType != RoutineRecurrenceType.weekdays)) {
      return 'Quel jour ou quelle règle de récurrence faut-il utiliser ?';
    }
    if (startTime == null) {
      return 'À quelle heure cette routine commence-t-elle ?';
    }
    if (durationMinutes == null) return 'Combien de temps dure cette routine ?';
    if (recurrenceType == RoutineRecurrenceType.biweekly &&
        anchorDateIso == null) {
      return 'À partir de quelle date commence l’alternance ?';
    }
    return '';
  }

  String get summary =>
      'J’ai préparé la routine « $title », à $startTime pendant '
      '$durationMinutes minutes. Veux-tu la confirmer ?';

  _RoutineDraft completeFrom(String input) {
    final parsed = parse(
      input,
      accountScopeId: accountScopeId,
      logicalRequestId: logicalRequestId,
    );
    if (parsed == null) {
      final time = _time(input);
      final duration = _duration(input) ?? _rangeDuration(input);
      return _copy(
        startTime: time,
        durationMinutes: duration,
        anchorDateIso: _date(input),
      );
    }
    return _RoutineDraft(
      accountScopeId: accountScopeId,
      logicalRequestId: logicalRequestId,
      title: title ?? parsed.title,
      recurrenceType: recurrenceType ?? parsed.recurrenceType,
      days: days.isEmpty ? parsed.days : days,
      startTime: startTime ?? parsed.startTime,
      durationMinutes: durationMinutes ?? parsed.durationMinutes,
      anchorDateIso: anchorDateIso ?? parsed.anchorDateIso,
      weekOfMonth: weekOfMonth ?? parsed.weekOfMonth,
    );
  }

  _RoutineDraft _copy({
    String? startTime,
    int? durationMinutes,
    String? anchorDateIso,
  }) =>
      _RoutineDraft(
        accountScopeId: accountScopeId,
        logicalRequestId: logicalRequestId,
        title: title,
        recurrenceType: recurrenceType,
        days: days,
        startTime: this.startTime ?? startTime,
        durationMinutes: this.durationMinutes ?? durationMinutes,
        anchorDateIso: this.anchorDateIso ?? anchorDateIso,
        weekOfMonth: weekOfMonth,
      );

  RoutineProposal toProposal({
    required String proposalId,
    required RoutineProposalState state,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime expiresAt,
  }) =>
      RoutineProposal(
        proposalId: proposalId,
        accountScopeId: accountScopeId,
        logicalRequestId: logicalRequestId,
        state: state,
        title: title,
        recurrenceType: recurrenceType,
        days: days,
        startTime: startTime,
        durationMinutes: durationMinutes,
        anchorDateIso: anchorDateIso,
        weekOfMonth: weekOfMonth,
        travelGoMinutes: 0,
        travelBackMinutes: 0,
        marginMinutes: 0,
        createdAt: createdAt,
        updatedAt: updatedAt,
        expiresAt: expiresAt,
      );

  static _RoutineDraft? parse(
    String input, {
    required String accountScopeId,
    required String logicalRequestId,
  }) {
    final text = RoutineTimeExpressionNormalizer.normalizeForAnalysis(input);
    final days = <int>[];
    const names = {
      'lundi': 1,
      'mardi': 2,
      'mercredi': 3,
      'jeudi': 4,
      'vendredi': 5,
      'samedi': 6,
      'dimanche': 7,
    };
    for (final entry in names.entries) {
      if (text.contains(entry.key)) days.add(entry.value);
    }
    RoutineRecurrenceType? recurrence;
    int? weekOfMonth;
    if (text.contains('du lundi au vendredi')) {
      recurrence = RoutineRecurrenceType.weekdays;
      days.clear();
    } else if (text.contains('une semaine sur deux')) {
      recurrence = RoutineRecurrenceType.biweekly;
    } else if (text.contains('chaque mois')) {
      recurrence = RoutineRecurrenceType.monthlyNthWeekday;
      weekOfMonth = text.contains('dernier')
          ? -1
          : text.contains('deuxieme')
              ? 2
              : null;
    } else if (text.contains('tous les ') || text.contains('toutes les ')) {
      recurrence = RoutineRecurrenceType.weekly;
    }
    if (recurrence == null) return null;
    final start = _time(input);
    int? duration = _duration(input);
    final range = RegExp(r'\bde\s*(\d{2}):(\d{2})\s*a\s*(\d{2}):(\d{2})\b')
        .firstMatch(text);
    if (range != null) {
      final from = int.parse(range.group(1)!) * 60 + int.parse(range.group(2)!);
      final to = int.parse(range.group(3)!) * 60 + int.parse(range.group(4)!);
      if (to > from) duration = to - from;
    }
    final titleMatch = RegExp(
      r'(?:je vais au|je vais a|j ai une|je travaille)\s+(.+?)(?:\.|$)',
    ).firstMatch(text);
    return _RoutineDraft(
      accountScopeId: accountScopeId,
      logicalRequestId: logicalRequestId,
      title: titleMatch?.group(1)?.trim(),
      recurrenceType: recurrence,
      days: days,
      startTime: start,
      durationMinutes: duration,
      anchorDateIso: _date(input),
      weekOfMonth: weekOfMonth,
    );
  }

  static String? _time(String input) {
    final text = RoutineTimeExpressionNormalizer.normalizeForAnalysis(input);
    final match = RegExp(r'\b(\d{2}):(\d{2})\b').firstMatch(text);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static int? _duration(String input) {
    final text = RoutineConversationService._normalize(input);
    final minutes = RegExp(r'(\d+)\s*minutes?').firstMatch(text);
    if (minutes != null) return int.parse(minutes.group(1)!);
    final hours = RegExp(r'(\d+)\s*heures?').firstMatch(text);
    if (hours != null) return int.parse(hours.group(1)!) * 60;
    return null;
  }

  static int? _rangeDuration(String input) {
    final text = RoutineTimeExpressionNormalizer.normalizeForAnalysis(input);
    final range = RegExp(r'\bde\s*(\d{2}):(\d{2})\s*a\s*(\d{2}):(\d{2})\b')
        .firstMatch(text);
    if (range == null) return null;
    final from = int.parse(range.group(1)!) * 60 + int.parse(range.group(2)!);
    final to = int.parse(range.group(3)!) * 60 + int.parse(range.group(4)!);
    return to > from ? to - from : null;
  }

  static String? _date(String input) {
    final iso = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b').firstMatch(input);
    if (iso != null && DateTime.tryParse(iso.group(1)!) != null) {
      return iso.group(1);
    }
    final french = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b').firstMatch(input);
    if (french == null) return null;
    final value = '${french.group(3)}-${french.group(2)!.padLeft(2, '0')}-'
        '${french.group(1)!.padLeft(2, '0')}';
    return DateTime.tryParse(value) == null ? null : value;
  }
}
