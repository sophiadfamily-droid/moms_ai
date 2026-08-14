import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/automatic_travel_planning_service.dart';
import 'package:moms_ai/services/route_travel_time_service.dart';

void main() {
  test('calcule les trajets domicile rendez-vous domicile', () async {
    final routes = _FakeRouteGateway();
    final service = AutomaticTravelPlanningService(routeGateway: routes);

    final result = await service.findOptions(
      startDate: DateTime(2026, 8, 17),
      actionMinutes: 60,
      marginMinutes: 10,
      searchDays: 1,
      destination: 'Dentiste',
      homeAddress: 'Maison',
      events: const [],
      reasoning: const [],
    );

    expect(result, isNotNull);
    expect(result!.hasOptions, isTrue);
    expect(result.options.first.travelGoMinutes, 15);
    expect(result.options.first.travelBackMinutes, 15);
    expect(result.options.first.departureContext, 'home');
    expect(result.options.first.arrivalContext, 'home');
    expect(routes.requests.first.origin, 'Maison');
    expect(routes.requests.first.destination, 'Dentiste');
  });

  test('part du rendez-vous précédent et va vers le rendez-vous suivant',
      () async {
    final routes = _FakeRouteGateway();
    final service = AutomaticTravelPlanningService(routeGateway: routes);
    final events = [
      _event(
        title: 'École',
        date: '2026-08-17',
        start: '08:00',
        end: '08:30',
        location: 'École du centre',
      ),
      _event(
        title: 'Réunion',
        date: '2026-08-17',
        start: '11:00',
        end: '12:00',
        location: 'Bureau',
      ),
    ];

    final result = await service.findOptions(
      startDate: DateTime(2026, 8, 17),
      actionMinutes: 60,
      marginMinutes: 0,
      searchDays: 1,
      destination: 'Dentiste',
      homeAddress: 'Maison',
      events: events,
      reasoning: const [],
    );

    expect(result, isNotNull);
    expect(result!.options, isNotEmpty);
    expect(
      routes.requests.any(
        (request) =>
            request.origin == 'École du centre' &&
            request.destination == 'Dentiste',
      ),
      isTrue,
    );
    expect(
      routes.requests.any(
        (request) =>
            request.origin == 'Dentiste' && request.destination == 'Bureau',
      ),
      isTrue,
    );
  });
}

EventModel _event({
  required String title,
  required String date,
  required String start,
  required String end,
  required String location,
}) =>
    EventModel(
      title: title,
      date: date,
      time: start,
      endTime: end,
      durationMinutes: 30,
      location: location,
      notes: '',
      category: 'Agenda',
      createdAt: DateTime(2026, 8, 1),
      startDateTimeIso: '${date}T$start:00',
      endDateTimeIso: '${date}T$end:00',
    );

final class _FakeRouteGateway implements RouteTravelTimeGateway {
  final List<RouteTravelTimeRequest> requests = [];

  @override
  Future<int?> estimateMinutes(RouteTravelTimeRequest request) async {
    requests.add(request);
    return 15;
  }
}
