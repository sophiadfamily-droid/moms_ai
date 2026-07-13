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
}
