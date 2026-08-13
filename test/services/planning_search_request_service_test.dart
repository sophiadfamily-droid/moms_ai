import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/planning_search_request_service.dart';

void main() {
  final now = DateTime(2026, 8, 13, 14, 48);

  test('treats next week as a seven-day search range', () {
    final request = PlanningSearchRequestService.parse(
      'Propose-moi un créneau pour le dentiste la semaine prochaine',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Dentiste');
    expect(request.startDate, DateTime(2026, 8, 17));
    expect(request.searchDays, 7);
  });

  test('searches only through Sunday for this week', () {
    final request = PlanningSearchRequestService.parse(
      'Trouve-moi un horaire pour l’administration cette semaine',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Administration');
    expect(request.startDate, DateTime(2026, 8, 13));
    expect(request.searchDays, 4);
  });

  test('supports a bounded number of upcoming days and a free title', () {
    final request = PlanningSearchRequestService.parse(
      'Cherche un moment pour renouveler mon passeport '
      'dans les 5 prochains jours',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Renouveler mon passeport');
    expect(request.startDate, DateTime(2026, 8, 13));
    expect(request.searchDays, 5);
  });

  test('keeps an exact relative day as a one-day search', () {
    final request = PlanningSearchRequestService.parse(
      'Propose-moi un créneau pour le vétérinaire demain',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Vétérinaire');
    expect(request.startDate, DateTime(2026, 8, 14));
    expect(request.searchDays, 1);
  });

  test('does not capture a normal Event request', () {
    expect(
      PlanningSearchRequestService.parse('Dentiste mardi à 15 h', now: now),
      isNull,
    );
  });

  test('does not capture an unrelated proposal', () {
    expect(
      PlanningSearchRequestService.parse(
        'Propose-moi une solution pour les courses',
        now: now,
      ),
      isNull,
    );
  });
}
