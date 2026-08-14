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
    expect(request.durationMinutes, 0);
  });

  test('keeps the duration already stated in the slot-search request', () {
    final request = PlanningSearchRequestService.parse(
      'Propose-moi un créneau d’une heure pour le dentiste '
      'la semaine prochaine',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Dentiste');
    expect(request.startDate, DateTime(2026, 8, 17));
    expect(request.searchDays, 7);
    expect(request.durationMinutes, 60);
  });

  test('separates an explicit appointment place from its title', () {
    final request = PlanningSearchRequestService.parse(
      'Propose-moi un créneau d’une heure pour le dentiste '
      'à la clinique Saint-Jean la semaine prochaine',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Dentiste');
    expect(request.location, 'la clinique Saint-Jean');
  });

  test('keeps an address stated after the requested search period', () {
    final request = PlanningSearchRequestService.parse(
      'Propose-moi un créneau d’une heure pour le dentiste '
      'la semaine prochaine au 45, avenue Pasteur Tremblay-en-France',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Dentiste');
    expect(request.durationMinutes, 60);
    expect(request.startDate, DateTime(2026, 8, 17));
    expect(
      request.location,
      '45, avenue Pasteur Tremblay-en-France',
    );
  });

  test('keeps an address stated before the requested search period', () {
    final request = PlanningSearchRequestService.parse(
      'Trouve-moi un créneau pour le médecin au 12 rue de la Paix '
      'la semaine prochaine',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Médecin');
    expect(request.location, '12 rue de la Paix');
  });

  test('does not invent a physical place from chez le dentiste', () {
    final request = PlanningSearchRequestService.parse(
      'Trouve-moi un créneau chez le dentiste demain',
      now: now,
    );

    expect(request, isNotNull);
    expect(request!.title, 'Dentiste');
    expect(request.location, isEmpty);
  });

  test('supports minute and mixed-hour durations in a slot search', () {
    for (final entry in const {
      'Trouve-moi un créneau de 45 minutes pour le médecin': 45,
      'Cherche un horaire de 1 h 30 pour le garage': 90,
      'Trouve un moment pour le vétérinaire qui dure deux heures': 120,
    }.entries) {
      final request = PlanningSearchRequestService.parse(entry.key, now: now);

      expect(request, isNotNull, reason: entry.key);
      expect(request!.durationMinutes, entry.value, reason: entry.key);
    }
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
