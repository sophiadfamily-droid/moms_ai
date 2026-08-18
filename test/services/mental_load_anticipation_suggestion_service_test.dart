import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/mental_load_anticipation.dart';
import 'package:moms_ai/models/priority/proactive_priority_models.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/services/mental_load_anticipation_suggestion_service.dart';
import 'package:moms_ai/services/priority/proactive_suggestion_history_repository.dart';

void main() {
  final now = DateTime(2026, 8, 17, 10);

  test('builds short human copy from canonical labels', () {
    final suggestion = _suggestion(now);

    expect(suggestion.presentation.title, 'À prévoir bientôt');
    expect(
      suggestion.presentation.message,
      'Avant « Inscription à l’école », pense à « Préparer les documents ».',
    );
    expect(suggestion.presentation.callToActionLabel, 'Voir la préparation');
  });

  test('shows at most one anticipation in a session', () async {
    final history = _History();
    final suggestion = _suggestion(now);
    final service = MentalLoadAnticipationSuggestionService(
      accountScopeId: 'account-a',
      loadSuggestions: () async => [suggestion],
      history: history,
      clock: () => now,
    );

    expect(
      await service.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ),
      same(suggestion),
    );
    expect(await service.confirmShown(suggestion), isTrue);
    expect(
      await service.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ),
      same(suggestion),
    );
    expect(history.values, hasLength(1));
  });

  test('dismissal is remembered and a material change becomes eligible',
      () async {
    final history = _History();
    var suggestion = _suggestion(now);
    var service = MentalLoadAnticipationSuggestionService(
      accountScopeId: 'account-a',
      loadSuggestions: () async => [suggestion],
      history: history,
      clock: () => now,
    );
    final shown = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    await service.confirmShown(shown!);
    await service.dismiss(shown);

    service = MentalLoadAnticipationSuggestionService(
      accountScopeId: 'account-a',
      loadSuggestions: () async => [suggestion],
      history: history,
      clock: () => now,
    );
    expect(
      await service.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ),
      isNull,
    );

    suggestion = _suggestion(now, eventStart: now.add(const Duration(days: 1)));
    service = MentalLoadAnticipationSuggestionService(
      accountScopeId: 'account-a',
      loadSuggestions: () async => [suggestion],
      history: history,
      clock: () => now,
    );
    expect(
      await service.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ),
      same(suggestion),
    );
  });

  test('fails closed during an active interaction', () async {
    final service = MentalLoadAnticipationSuggestionService(
      accountScopeId: 'account-a',
      loadSuggestions: () async => [_suggestion(now)],
      history: _History(),
      clock: () => now,
    );

    expect(
      await service.evaluate(
        dashboardReady: true,
        interactionActive: true,
      ),
      isNull,
    );
  });
}

MentalLoadAnticipationSuggestion _suggestion(
  DateTime now, {
  DateTime? eventStart,
}) {
  final event = eventStart ?? now.add(const Duration(hours: 20));
  return MentalLoadAnticipationSuggestion(
    anticipation: MentalLoadAnticipation(
      id: 'anticipation-a',
      accountScopeId: 'account-a',
      reason: MentalLoadAnticipationReason.explicitPreparationBeforeEvent,
      priority: MentalLoadAnticipationPriority.urgent,
      preparationSourceId: 'prepare-documents',
      eventSourceId: 'school-registration',
      preparationDeadline: now.add(const Duration(hours: 8)),
      eventStart: event,
      evidence: [
        DetectionEvidence(
          sourceType: DetectionEvidenceSource.explicitDeadline,
          domain: LifeContextDomain.task,
          sourceId: 'prepare-documents',
          revision: 1,
          freshness: LifeContextFreshness.current,
          availability: LifeContextAvailability.available,
          certainty: DetectionEvidenceLevel.explicit,
          instant: now.add(const Duration(hours: 8)),
          confirmed: true,
        ),
      ],
    ),
    preparationLabel: 'Préparer les documents',
    eventLabel: 'Inscription à l’école',
  );
}

final class _History implements ProactiveSuggestionHistoryRepository {
  List<ProactiveSuggestionReceipt> values = [];

  @override
  Future<List<ProactiveSuggestionReceipt>> load(String accountScopeId) async =>
      List.of(values);

  @override
  Future<void> save(
    String accountScopeId,
    List<ProactiveSuggestionReceipt> receipts,
  ) async {
    values = List.of(receipts);
  }
}
