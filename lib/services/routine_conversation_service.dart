import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/routine_model.dart';
import '../models/routine/routine_occurrence_override.dart';
import '../models/routine/routine_schedule_definition.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'cloud_profile_service.dart';
import 'conversation_answer_classifier.dart';
import 'natural_date_service.dart';
import 'natural_time_service.dart';
import 'routine/routine_date_applicability_engine.dart';
import 'routine/routine_occurrence_override_repository.dart';
import 'routine/routine_schedule_catalog_service.dart';
import 'routine_repository.dart';
import 'zelia_response_builder.dart';

enum RoutineConversationResultType {
  notRoutine,
  clarification,
  confirmation,
  created,
  cancelled,
  ambiguous,
  unavailable,
}

typedef RoutineConversationScheduleLoader
    = Future<List<RoutineScheduleDefinition>> Function(
  String accountScopeId,
);

final class RoutineConversationResult {
  const RoutineConversationResult(this.type, this.message);
  final RoutineConversationResultType type;
  final String message;
}

final class RoutineConversationService {
  factory RoutineConversationService.production({
    UserProfile Function()? currentProfile,
  }) {
    final routineRepository = FirestoreRoutineRepository();
    final service = RoutineConversationService(
      repository: routineRepository,
      occurrenceOverrideRepository:
          FirestoreRoutineOccurrenceOverrideRepository(),
      currentAccountScopeId: () => AuthService.currentUserId,
      loadProfile: currentProfile == null
          ? CloudProfileService.getProfile
          : () async => currentProfile(),
    );
    unawaited(service.restoreActive());
    return service;
  }

  RoutineConversationService({
    required RoutineRepository repository,
    required String? Function() currentAccountScopeId,
    RoutineOccurrenceOverrideRepository? occurrenceOverrideRepository,
    RoutineScheduleProfileLoader? loadProfile,
    RoutineConversationScheduleLoader? loadScheduleCatalog,
    DateTime Function()? clock,
  })  : _repository = repository,
        _occurrenceOverrideRepository = occurrenceOverrideRepository,
        _loadScheduleCatalog = loadScheduleCatalog ??
            RoutineScheduleCatalogService(
              loadRoutines: repository.listForAccount,
              loadProfile: loadProfile,
            ).forAccount,
        _currentAccountScopeId = currentAccountScopeId,
        _clock = clock ?? DateTime.now;

  final RoutineRepository _repository;
  final RoutineOccurrenceOverrideRepository? _occurrenceOverrideRepository;
  final RoutineConversationScheduleLoader _loadScheduleCatalog;
  final String? Function() _currentAccountScopeId;
  final DateTime Function() _clock;
  final ConversationAnswerClassifier _answers =
      const ConversationAnswerClassifier();
  RoutineProposal? _pending;
  _PendingRoutineOccurrenceChange? _pendingOccurrenceChange;
  _PendingRoutineOccurrenceChangeDraft? _pendingOccurrenceDraft;

  bool get hasPending =>
      _pending != null ||
      _pendingOccurrenceChange != null ||
      _pendingOccurrenceDraft != null;

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
    final occurrenceChange = await _processOccurrenceChange(
      message,
      logicalRequestId: logicalRequestId,
    );
    if (occurrenceChange != null) return occurrenceChange;
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
    if (_containsRoutineChangeVerb(text)) return false;
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

  static bool _containsRoutineChangeVerb(String text) =>
      RegExp(
        r'\b(?:an{1,2}ul(?:e|er|ee)?|supprim(?:e|er)?|'
        r'deplac(?:e|er|ee)?|decal(?:e|er|ee)?|report(?:e|er|ee)?|'
        r'boug(?:e|er|ee)?|remplac(?:e|er|ee)?)\b',
      ).hasMatch(text) ||
      RegExp(r'\bpas de\b').hasMatch(text);

  Future<RoutineConversationResult?> _processOccurrenceChange(
    String message, {
    required String logicalRequestId,
  }) async {
    final repository = _occurrenceOverrideRepository;
    if (repository == null) return null;
    final pending = _pendingOccurrenceChange;
    if (pending != null) {
      final answer = _answers.classify(message);
      if (answer == ConversationAnswer.negative) {
        _pendingOccurrenceChange = null;
        return const RoutineConversationResult(
          RoutineConversationResultType.cancelled,
          'D’accord, je ne change rien.',
        );
      }
      if (answer != ConversationAnswer.positive) {
        return const RoutineConversationResult(
          RoutineConversationResultType.ambiguous,
          'Dis-moi simplement oui ou non pour confirmer ce changement.',
        );
      }
      final current = await repository.listForAccount(pending.accountScopeId);
      final previous = current
          .where((item) => item.occurrenceKey == pending.occurrenceKey)
          .firstOrNull;
      final reference = _clock().toUtc();
      final updatedAt = previous == null
          ? reference
          : (reference.isAfter(previous.updatedAt)
              ? reference
              : previous.updatedAt.add(const Duration(microseconds: 1)));
      final override = RoutineOccurrenceOverride(
        overrideId: _occurrenceOverrideId(
          pending.accountScopeId,
          pending.routine.id,
          pending.sourceDateIso,
        ),
        accountScopeId: pending.accountScopeId,
        routineId: pending.routine.id,
        sourceDateIso: pending.sourceDateIso,
        type: pending.type,
        replacementDateIso: pending.replacementDateIso,
        replacementStartTime: pending.replacementStartTime,
        replacementLabel: pending.replacementLabel,
        overrideRevision: (previous?.overrideRevision ?? 0) + 1,
        lastMutationId: pending.mutationId,
        createdAt: previous?.createdAt ?? updatedAt,
        updatedAt: updatedAt,
      );
      final persisted = await repository.put(override);
      if (persisted == null) {
        return const RoutineConversationResult(
          RoutineConversationResultType.unavailable,
          'Je n’ai pas pu faire ce changement pour le moment. '
          'Tu peux réessayer dans un instant.',
        );
      }
      _pendingOccurrenceChange = null;
      return RoutineConversationResult(
        RoutineConversationResultType.created,
        pending.successMessage,
      );
    }

    final pendingDraft = _pendingOccurrenceDraft;
    final answer = _answers.classify(message);
    if (pendingDraft != null && answer == ConversationAnswer.negative) {
      _pendingOccurrenceDraft = null;
      return const RoutineConversationResult(
        RoutineConversationResultType.cancelled,
        'D’accord, je laisse cette séance comme elle est.',
      );
    }
    final request = pendingDraft == null
        ? _RoutineOccurrenceChangeRequest.parse(message, now: _clock())
        : pendingDraft.request.completeFrom(message, now: _clock());
    if (request == null) return null;
    final effectiveLogicalRequestId =
        pendingDraft?.logicalRequestId ?? logicalRequestId;
    final accountScopeId = _currentAccountScopeId();
    if (accountScopeId == null || accountScopeId.isEmpty) {
      return const RoutineConversationResult(
        RoutineConversationResultType.unavailable,
        'Je ne peux pas préparer ce changement pour le moment.',
      );
    }
    final catalog = await _loadScheduleCatalog(accountScopeId);
    final routines = catalog.map((entry) => entry.routine).toList();
    final namedMatches = routines
        .where((routine) =>
            routine.status == RoutineStatus.active &&
            _matchesRoutine(request.sourceText, routine.title))
        .toList(growable: false);
    if (request.sourceDateIso == null) {
      if (namedMatches.isEmpty) return null;
      _pendingOccurrenceDraft = _PendingRoutineOccurrenceChangeDraft(
        request: request,
        logicalRequestId: effectiveLogicalRequestId,
      );
      return const RoutineConversationResult(
        RoutineConversationResultType.clarification,
        'Pour quelle séance veux-tu faire ce changement ?',
      );
    }
    if (request.type == RoutineOccurrenceOverrideType.moved &&
        request.replacementStartTime == null) {
      _pendingOccurrenceDraft = _PendingRoutineOccurrenceChangeDraft(
        request: request,
        logicalRequestId: effectiveLogicalRequestId,
      );
      return const RoutineConversationResult(
        RoutineConversationResultType.clarification,
        'À quelle heure veux-tu déplacer cette séance ?',
      );
    }
    if (request.type == RoutineOccurrenceOverrideType.replaced &&
        request.replacementLabel == null) {
      _pendingOccurrenceDraft = _PendingRoutineOccurrenceChangeDraft(
        request: request,
        logicalRequestId: effectiveLogicalRequestId,
      );
      return const RoutineConversationResult(
        RoutineConversationResultType.clarification,
        'Par quoi veux-tu remplacer cette séance ?',
      );
    }
    final sourceDate = DateTime.parse(request.sourceDateIso!);
    final applicable = routines
        .where((routine) =>
            routine.status == RoutineStatus.active &&
            const RoutineDateApplicabilityEngine().applies(
              recurrenceType: routine.recurrenceType.name,
              weekdays: routine.days,
              date: sourceDate,
              anchorDateIso: routine.anchorDateIso,
              weekOfMonth: routine.weekOfMonth,
            ))
        .toList(growable: false);
    final matches = applicable
        .where((routine) => _matchesRoutine(request.sourceText, routine.title))
        .toList(growable: false);
    final candidates = matches.isNotEmpty
        ? matches
        : (request.hasGenericTarget && applicable.length == 1
            ? applicable
            : const <RoutineModel>[]);
    if (candidates.isEmpty) {
      _pendingOccurrenceDraft = null;
      if (namedMatches.isNotEmpty) {
        return RoutineConversationResult(
          RoutineConversationResultType.clarification,
          '« ${namedMatches.first.title} » n’est pas prévu le '
          '${ZeliaResponseBuilder.formatDateForUser(request.sourceDateIso!)}. '
          'Tu peux me donner la date de la séance à modifier.',
        );
      }
      return null;
    }
    if (candidates.length > 1) {
      _pendingOccurrenceDraft = _PendingRoutineOccurrenceChangeDraft(
        request: request,
        logicalRequestId: effectiveLogicalRequestId,
      );
      final titles = candidates.map((item) => '« ${item.title} »').join(' ou ');
      return RoutineConversationResult(
        RoutineConversationResultType.clarification,
        'Tu parles de $titles ?',
      );
    }
    final routine = candidates.single;
    final mutationId = sha256
        .convert(utf8.encode(
          'routine-occurrence-change-v1|$accountScopeId|'
          '$effectiveLogicalRequestId',
        ))
        .toString();
    final prepared = _PendingRoutineOccurrenceChange(
      accountScopeId: accountScopeId,
      routine: routine,
      sourceDateIso: request.sourceDateIso!,
      type: request.type,
      replacementDateIso: request.type == RoutineOccurrenceOverrideType.moved
          ? request.replacementDateIso ?? request.sourceDateIso
          : null,
      replacementStartTime: request.replacementStartTime,
      replacementLabel: request.replacementLabel,
      mutationId: mutationId,
    );
    _pendingOccurrenceDraft = null;
    _pendingOccurrenceChange = prepared;
    return RoutineConversationResult(
      RoutineConversationResultType.confirmation,
      prepared.confirmationMessage,
    );
  }

  static bool _matchesRoutine(String sourceText, String title) {
    final source = _matchText(sourceText);
    final candidate = _matchText(title);
    if (source.contains(candidate) || candidate.contains(source)) return true;
    final sourceTokens = source.split(' ').where((item) => item.length > 2);
    final titleTokens = candidate.split(' ').where((item) => item.length > 2);
    return titleTokens.isNotEmpty &&
        titleTokens.every((titleToken) => sourceTokens.any(
              (sourceToken) =>
                  sourceToken == titleToken ||
                  _singular(sourceToken) == _singular(titleToken) ||
                  _oneEditApart(sourceToken, titleToken),
            ));
  }

  static String _matchText(String value) => _normalize(value)
      .replaceAll("'", ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _singular(String value) =>
      value.length > 3 && value.endsWith('s')
          ? value.substring(0, value.length - 1)
          : value;

  static bool _oneEditApart(String left, String right) {
    if (left.length < 4 ||
        right.length < 4 ||
        (left.length - right.length).abs() > 1) {
      return false;
    }
    var row = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i++) {
      final next = <int>[i];
      for (var j = 1; j <= right.length; j++) {
        next.add([
          next[j - 1] + 1,
          row[j] + 1,
          row[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1),
        ].reduce((a, b) => a < b ? a : b));
      }
      row = next;
    }
    return row.last <= 1;
  }

  static String _occurrenceOverrideId(
    String accountScopeId,
    String routineId,
    String sourceDateIso,
  ) =>
      sha256
          .convert(utf8.encode(
            'routine-occurrence-override-v1|$accountScopeId|$routineId|'
            '$sourceDateIso',
          ))
          .toString();
}

final class _PendingRoutineOccurrenceChangeDraft {
  const _PendingRoutineOccurrenceChangeDraft({
    required this.request,
    required this.logicalRequestId,
  });

  final _RoutineOccurrenceChangeRequest request;
  final String logicalRequestId;
}

final class _PendingRoutineOccurrenceChange {
  const _PendingRoutineOccurrenceChange({
    required this.accountScopeId,
    required this.routine,
    required this.sourceDateIso,
    required this.type,
    required this.mutationId,
    this.replacementDateIso,
    this.replacementStartTime,
    this.replacementLabel,
  });

  final String accountScopeId;
  final RoutineModel routine;
  final String sourceDateIso;
  final RoutineOccurrenceOverrideType type;
  final String mutationId;
  final String? replacementDateIso;
  final String? replacementStartTime;
  final String? replacementLabel;

  String get occurrenceKey => '${routine.id}:$sourceDateIso';
  String get _sourceDate =>
      ZeliaResponseBuilder.formatDateForUser(sourceDateIso);
  String get _replacementDate =>
      ZeliaResponseBuilder.formatDateForUser(replacementDateIso ?? '');
  String get _timeLabel => replacementStartTime == null
      ? ''
      : replacementStartTime!.endsWith(':00')
          ? '${replacementStartTime!.substring(0, 2)} h'
          : replacementStartTime!.replaceFirst(':', ' h ');

  String get confirmationMessage => switch (type) {
        RoutineOccurrenceOverrideType.cancelled =>
          'Tu veux que j’annule seulement « ${routine.title} » du '
              '$_sourceDate ? Les autres séances resteront inchangées.',
        RoutineOccurrenceOverrideType.moved =>
          'Tu veux que je déplace seulement « ${routine.title} » du '
              '$_sourceDate au $_replacementDate à $_timeLabel ? '
              'Les autres séances resteront inchangées.',
        RoutineOccurrenceOverrideType.replaced =>
          'Tu veux que je remplace seulement « ${routine.title} » du '
              '$_sourceDate par « $replacementLabel » ? '
              'Les autres séances resteront inchangées.',
      };

  String get successMessage => switch (type) {
        RoutineOccurrenceOverrideType.cancelled =>
          'C’est noté, « ${routine.title} » est annulé seulement le '
              '$_sourceDate. Les autres séances ne changent pas.',
        RoutineOccurrenceOverrideType.moved =>
          'C’est noté, « ${routine.title} » est déplacé au '
              '$_replacementDate à $_timeLabel. Les autres séances ne '
              'changent pas.',
        RoutineOccurrenceOverrideType.replaced =>
          'C’est noté, « ${routine.title} » est remplacé par '
              '« $replacementLabel » seulement le $_sourceDate. Les autres '
              'séances ne changent pas.',
      };
}

final class _RoutineOccurrenceChangeRequest {
  const _RoutineOccurrenceChangeRequest({
    required this.type,
    required this.sourceText,
    required this.hasGenericTarget,
    this.sourceDateIso,
    this.replacementDateIso,
    this.replacementStartTime,
    this.replacementLabel,
  });

  final RoutineOccurrenceOverrideType type;
  final String sourceText;
  final bool hasGenericTarget;
  final String? sourceDateIso;
  final String? replacementDateIso;
  final String? replacementStartTime;
  final String? replacementLabel;

  _RoutineOccurrenceChangeRequest completeFrom(
    String input, {
    required DateTime now,
  }) {
    if (sourceDateIso == null) {
      return _RoutineOccurrenceChangeRequest(
        type: type,
        sourceText: '$sourceText $input',
        hasGenericTarget: hasGenericTarget,
        sourceDateIso: _date(input, now),
        replacementDateIso: replacementDateIso,
        replacementStartTime: replacementStartTime,
        replacementLabel: replacementLabel,
      );
    }
    if (type == RoutineOccurrenceOverrideType.moved &&
        replacementStartTime == null) {
      final parsedDate = _date(input, now);
      final parsedTime = NaturalTimeService.parseTime(input);
      return _RoutineOccurrenceChangeRequest(
        type: type,
        sourceText: sourceText,
        hasGenericTarget: hasGenericTarget,
        sourceDateIso: sourceDateIso,
        replacementDateIso: parsedDate ?? replacementDateIso ?? sourceDateIso,
        replacementStartTime: parsedTime.isEmpty ? null : parsedTime,
        replacementLabel: replacementLabel,
      );
    }
    if (type == RoutineOccurrenceOverrideType.replaced &&
        replacementLabel == null) {
      return _RoutineOccurrenceChangeRequest(
        type: type,
        sourceText: sourceText,
        hasGenericTarget: hasGenericTarget,
        sourceDateIso: sourceDateIso,
        replacementDateIso: replacementDateIso,
        replacementStartTime: replacementStartTime,
        replacementLabel: _cleanReplacement(input),
      );
    }
    return _RoutineOccurrenceChangeRequest(
      type: type,
      sourceText: '$sourceText $input',
      hasGenericTarget: hasGenericTarget,
      sourceDateIso: sourceDateIso,
      replacementDateIso: replacementDateIso,
      replacementStartTime: replacementStartTime,
      replacementLabel: replacementLabel,
    );
  }

  static _RoutineOccurrenceChangeRequest? parse(
    String input, {
    required DateTime now,
  }) {
    final text = RoutineConversationService._normalize(input)
        .replaceAll("'", ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (RegExp(
      r'\b(?:tous les|toutes les|chaque|definitivement|pour toujours)\b',
    ).hasMatch(text)) {
      return null;
    }
    final replaced = RegExp(r'\bremplac(?:e|er|ee)?\b').hasMatch(text);
    final moved = RegExp(
      r'\b(?:deplac(?:e|er|ee)?|decal(?:e|er|ee)?|report(?:e|er|ee)?|'
      r'boug(?:e|er|ee)?)\b',
    ).hasMatch(text);
    final cancelled = RegExp(
      r'\b(?:an{1,2}ul(?:e|er|ee)?|supprim(?:e|er)?|pas de)\b',
    ).hasMatch(text);
    if (!replaced && !moved && !cancelled) return null;
    if (RegExp(
      r'\b(?:ne|n)\s+(?:veux\s+)?(?:anul|annul|supprim|deplac|decal|report|'
      r'boug|remplac)\w*\s+pas\b|\b(?:anul|annul|supprim|deplac|decal|'
      r'report|boug|remplac)\w*\s+pas\b',
    ).hasMatch(text)) {
      return null;
    }

    if (replaced) {
      final split = RegExp(r'^(.*?)\s+par\s+(.+)$').firstMatch(text);
      final label = split == null ? null : _cleanReplacement(split.group(2)!);
      final source = split?.group(1) ?? text;
      return _RoutineOccurrenceChangeRequest(
        type: RoutineOccurrenceOverrideType.replaced,
        sourceText: source,
        hasGenericTarget: _hasGenericTarget(source),
        sourceDateIso: _date(source, now),
        replacementLabel: label,
      );
    }
    if (moved) {
      final split = RegExp(r'^(.*?)\s+(?:a|au|pour)\s+(.+)$').firstMatch(text);
      final source = split?.group(1) ?? text;
      final destination = split?.group(2) ?? '';
      final sourceDate = _date(source, now);
      return _RoutineOccurrenceChangeRequest(
        type: RoutineOccurrenceOverrideType.moved,
        sourceText: source,
        hasGenericTarget: _hasGenericTarget(source),
        sourceDateIso: sourceDate,
        replacementDateIso: _date(destination, now) ?? sourceDate,
        replacementStartTime:
            NaturalTimeService.parseTime(destination).trim().isEmpty
                ? null
                : NaturalTimeService.parseTime(destination),
      );
    }
    return _RoutineOccurrenceChangeRequest(
      type: RoutineOccurrenceOverrideType.cancelled,
      sourceText: text,
      hasGenericTarget: _hasGenericTarget(text),
      sourceDateIso: _date(text, now),
    );
  }

  static String? _date(String text, DateTime now) {
    final value = NaturalDateService.resolveDateFromText(text, now: now);
    return value.isEmpty ? null : value;
  }

  static bool _hasGenericTarget(String text) => RegExp(
        r'\b(?:seance|cours|activite|routine|habitude)\b',
      ).hasMatch(text);

  static String? _cleanReplacement(String value) {
    var result = value
        .replaceFirst(RegExp(r'^(?:le|la|les|un|une|du|de la)\s+'), '')
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .trim();
    return result.isEmpty ? null : result;
  }
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
