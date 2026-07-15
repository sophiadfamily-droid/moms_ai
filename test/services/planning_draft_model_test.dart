import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/models/planning_draft_model.dart';
import 'package:moms_ai/services/planning_draft_service.dart';

void main() {
  group('PlanningDraftModel separate travel', () {
    test('preserves different outbound and return values', () {
      final draft = PlanningDraftModel.empty().withTravel(
        goMinutes: 15,
        backMinutes: 30,
      );

      expect(draft.travelGoMinutes, 15);
      expect(draft.travelBackMinutes, 30);
      expect(draft.totalTravelMinutes, 45);
      expect(draft.needsTravel, isFalse);
    });

    test('preserves an explicit zero return value', () {
      final draft = PlanningDraftModel.empty().withTravel(
        goMinutes: 15,
        backMinutes: 0,
      );

      expect(draft.travelGoMinutes, 15);
      expect(draft.travelBackMinutes, 0);
      expect(draft.totalTravelMinutes, 15);
      expect(draft.needsTravel, isFalse);
    });

    test('pending conversion requires and preserves both values', () {
      final pending = <String, dynamic>{
        'requestedDateIso': '2026-07-14',
        'outside': true,
      };

      final draft = PlanningDraftService.withTravelFromPending(
        pending: pending,
        travelGoMinutes: 20,
        travelBackMinutes: 5,
      );

      expect(draft.travelGoMinutes, 20);
      expect(draft.travelBackMinutes, 5);
      expect(draft.totalTravelMinutes, 25);
    });
  });
  group('PlanningDraftService human summary', () {
    PlanningDraftModel buildCompleteDraft({
      int travelGoMinutes = 15,
      int travelBackMinutes = 30,
      int marginMinutes = 10,
      bool isOutside = true,
    }) {
      return PlanningDraftModel.empty().copyWith(
        title: 'Médecin',
        dateIso: '2026-07-20',
        time: '14:00',
        durationMinutes: 45,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        marginMinutes: marginMinutes,
        isOutside: isOutside,
        needsDate: false,
        needsTime: false,
        needsDuration: false,
        needsTravel: false,
      );
    }

    test('includes outbound travel, return travel and safety margin', () {
      final summary = PlanningDraftService.humanSummary(
        buildCompleteDraft(),
      );

      expect(summary, contains('« Médecin »'));
      expect(summary, contains('le 2026-07-20'));
      expect(summary, contains('à 14:00'));
      expect(summary, contains('pendant 45 min'));
      expect(summary, contains('trajet aller : 15 min'));
      expect(summary, contains('trajet retour : 30 min'));
      expect(summary, contains('marge de sécurité : 10 min'));
    });

    test('keeps an explicit zero return travel visible', () {
      final summary = PlanningDraftService.humanSummary(
        buildCompleteDraft(
          travelBackMinutes: 0,
          marginMinutes: 0,
        ),
      );

      expect(summary, contains('trajet aller : 15 min'));
      expect(summary, contains('trajet retour : 0 min'));
      expect(summary, isNot(contains('marge de sécurité')));
    });

    test('does not invent travel details for an internal event', () {
      final summary = PlanningDraftService.humanSummary(
        buildCompleteDraft(
          travelGoMinutes: 0,
          travelBackMinutes: 0,
          marginMinutes: 0,
          isOutside: false,
        ),
      );

      expect(summary, isNot(contains('trajet aller')));
      expect(summary, isNot(contains('trajet retour')));
      expect(summary, isNot(contains('marge de sécurité')));
    });

    test('total estimated minutes includes duration, both travels and margin',
        () {
      final draft = buildCompleteDraft();

      expect(draft.totalTravelMinutes, 45);
      expect(draft.totalEstimatedMinutes, 100);
    });
  });
}
