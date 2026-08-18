import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mental_load_anticipation.dart';
import '../models/priority/proactive_priority_models.dart';
import 'mental_load_anticipation_presentation_builder.dart';
import 'priority/proactive_suggestion_history_repository.dart';

final class MentalLoadAnticipationSuggestion {
  MentalLoadAnticipationSuggestion({
    required this.anticipation,
    required this.preparationLabel,
    required this.eventLabel,
  })  : canonicalKey = _hash([
          anticipation.reason.name,
          anticipation.preparationSourceId,
          anticipation.eventSourceId,
        ].join('|')),
        materialFingerprint = _hash([
          anticipation.reason.name,
          anticipation.preparationSourceId,
          anticipation.eventSourceId,
          anticipation.preparationDeadline.toUtc().toIso8601String(),
          anticipation.eventStart.toUtc().toIso8601String(),
          preparationLabel.trim(),
          eventLabel.trim(),
        ].join('|')) {
    if (preparationLabel.trim().isEmpty || eventLabel.trim().isEmpty) {
      throw const FormatException('mental_load_suggestion_label_missing');
    }
  }

  final MentalLoadAnticipation anticipation;
  final String preparationLabel;
  final String eventLabel;
  final String canonicalKey;
  final String materialFingerprint;

  String get suggestionId => 'mental-load-$materialFingerprint';
  String get sourceRevision {
    final revisions = anticipation.evidence
        .map((item) => '${item.domain.name}:${item.sourceId}:${item.revision}')
        .toList()
      ..sort();
    return _hash(revisions.join('|'));
  }

  MentalLoadAnticipationPresentation get presentation =>
      const MentalLoadAnticipationPresentationBuilder().build(
        anticipation: anticipation,
        preparationLabel: preparationLabel,
        eventLabel: eventLabel,
      );

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 24);
}

typedef MentalLoadAnticipationSuggestionLoader
    = Future<List<MentalLoadAnticipationSuggestion>> Function();

/// Quiet, bounded presentation lifecycle for Stage 9 anticipations.
///
/// It reuses the established proactive receipt store, presents at most one
/// item per session and never mutates Tasks, Events or notifications.
final class MentalLoadAnticipationSuggestionService {
  MentalLoadAnticipationSuggestionService({
    required this.accountScopeId,
    required MentalLoadAnticipationSuggestionLoader loadSuggestions,
    required ProactiveSuggestionHistoryRepository history,
    DateTime Function()? clock,
  })  : _loadSuggestions = loadSuggestions,
        _history = history,
        _clock = clock ?? DateTime.now;

  final String accountScopeId;
  final MentalLoadAnticipationSuggestionLoader _loadSuggestions;
  final ProactiveSuggestionHistoryRepository _history;
  final DateTime Function() _clock;
  bool _presentedThisSession = false;
  MentalLoadAnticipationSuggestion? _visibleSuggestion;

  MentalLoadAnticipationSuggestion? get currentVisibleSuggestion =>
      _visibleSuggestion;

  static Future<MentalLoadAnticipationSuggestionService> create({
    required String accountScopeId,
    required MentalLoadAnticipationSuggestionLoader loadSuggestions,
  }) async =>
      MentalLoadAnticipationSuggestionService(
        accountScopeId: accountScopeId,
        loadSuggestions: loadSuggestions,
        history: SharedPreferencesProactiveSuggestionHistoryRepository(
          await SharedPreferences.getInstance(),
        ),
      );

  Future<MentalLoadAnticipationSuggestion?> evaluate({
    required bool dashboardReady,
    required bool interactionActive,
  }) async {
    if (!dashboardReady || interactionActive || _presentedThisSession) {
      return _visibleSuggestion;
    }
    final now = _clock();
    final history = await _history.load(accountScopeId);
    final suggestions = await _loadSuggestions();
    for (final suggestion in suggestions) {
      if (suggestion.anticipation.accountScopeId != accountScopeId ||
          suggestion.anticipation.eventStart.toLocal().isBefore(now)) {
        continue;
      }
      final alreadyHandled = history.any(
        (receipt) =>
            receipt.materialFingerprint == suggestion.materialFingerprint &&
                _sameCivilDay(receipt.lastShownAt.toLocal(), now) ||
            receipt.canonicalSuggestionKey == suggestion.canonicalKey &&
                receipt.materialFingerprint == suggestion.materialFingerprint &&
                {
                  ProactiveSuggestionHistoryState.dismissed,
                  ProactiveSuggestionHistoryState.actedOn,
                  ProactiveSuggestionHistoryState.completed,
                }.contains(receipt.state),
      );
      if (!alreadyHandled) return suggestion;
    }
    return null;
  }

  Future<bool> confirmShown(MentalLoadAnticipationSuggestion suggestion) async {
    if (_presentedThisSession &&
        _visibleSuggestion?.suggestionId == suggestion.suggestionId) {
      return true;
    }
    if (_presentedThisSession ||
        suggestion.anticipation.accountScopeId != accountScopeId) {
      return false;
    }
    final now = _clock();
    final history = await _history.load(accountScopeId);
    final receipts = [
      ...history,
      ProactiveSuggestionReceipt(
        suggestionId: suggestion.suggestionId,
        canonicalSuggestionKey: suggestion.canonicalKey,
        materialFingerprint: suggestion.materialFingerprint,
        firstShownAt: now,
        lastShownAt: now,
        state: ProactiveSuggestionHistoryState.shown,
        sourceRevision: suggestion.sourceRevision,
      ),
    ];
    await _history.save(
      accountScopeId,
      receipts.length <= 128
          ? receipts
          : receipts.sublist(receipts.length - 128),
    );
    _presentedThisSession = true;
    _visibleSuggestion = suggestion;
    return true;
  }

  Future<void> dismiss(MentalLoadAnticipationSuggestion suggestion) =>
      _updateReceipt(suggestion, ProactiveSuggestionHistoryState.dismissed);

  Future<void> markActedOn(MentalLoadAnticipationSuggestion suggestion) =>
      _updateReceipt(suggestion, ProactiveSuggestionHistoryState.actedOn);

  Future<void> _updateReceipt(
    MentalLoadAnticipationSuggestion suggestion,
    ProactiveSuggestionHistoryState state,
  ) async {
    final now = _clock();
    final history = await _history.load(accountScopeId);
    final updated = history.map((receipt) {
      if (receipt.suggestionId != suggestion.suggestionId) return receipt;
      return ProactiveSuggestionReceipt(
        suggestionId: receipt.suggestionId,
        canonicalSuggestionKey: receipt.canonicalSuggestionKey,
        materialFingerprint: receipt.materialFingerprint,
        firstShownAt: receipt.firstShownAt,
        lastShownAt: receipt.lastShownAt,
        dismissedAt:
            state == ProactiveSuggestionHistoryState.dismissed ? now : null,
        actedOnAt:
            state == ProactiveSuggestionHistoryState.actedOn ? now : null,
        state: state,
        sourceRevision: receipt.sourceRevision,
      );
    }).toList(growable: false);
    await _history.save(accountScopeId, updated);
    _visibleSuggestion = null;
  }

  bool _sameCivilDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
