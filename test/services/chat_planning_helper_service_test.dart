import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/chat_planning_helper_service.dart';

void main() {
  group('ChatPlanningHelperService.parseDurationMinutes', () {
    test('returns zero when no duration is provided', () {
      expect(
        ChatPlanningHelperService.parseDurationMinutes(
          'Prends-moi un rendez-vous chez le médecin',
        ),
        0,
      );
    });

    test('parses a duration expressed in minutes', () {
      expect(
        ChatPlanningHelperService.parseDurationMinutes('pendant 45 minutes'),
        45,
      );
    });

    test('parses a duration expressed with hours and minutes', () {
      expect(
        ChatPlanningHelperService.parseDurationMinutes('1h30'),
        90,
      );
    });

    test('does not interpret an unrelated number as a duration', () {
      expect(
        ChatPlanningHelperService.parseDurationMinutes(
          'Rendez-vous le 20 juillet',
        ),
        0,
      );
    });

    test('does not interpret an appointment time as a duration', () {
      expect(
        ChatPlanningHelperService.parseDurationMinutes(
          'Rendez-vous demain à 14h',
        ),
        0,
      );
    });

    test('does not interpret a calendar year as a duration', () {
      expect(
        ChatPlanningHelperService.parseDurationMinutes(
          'Rendez-vous le 20 juillet 2026',
        ),
        0,
      );
    });
  });
}
