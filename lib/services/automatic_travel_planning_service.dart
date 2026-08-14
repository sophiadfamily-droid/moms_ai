import '../models/event_model.dart';
import 'event_service.dart';
import 'planning_proposal_engine.dart';
import 'route_travel_time_service.dart';
import 'smart_planning_service.dart';

final class AutomaticTravelPlanningService {
  const AutomaticTravelPlanningService({
    required RouteTravelTimeGateway routeGateway,
  }) : _routeGateway = routeGateway;

  static const Duration _adjacentEventHorizon = Duration(hours: 6);
  static const int _maximumRoutedCandidates = 12;

  final RouteTravelTimeGateway _routeGateway;

  /// Returns `null` only when no reliable route could be calculated.
  /// An ordinary result with no options means routes worked but the calendar
  /// contains no realistic availability.
  Future<PlanningProposalEngineResult?> findOptions({
    required DateTime startDate,
    required int actionMinutes,
    required int marginMinutes,
    required int searchDays,
    required String destination,
    required String homeAddress,
    required List<EventModel> events,
    required List<Map<String, dynamic>> reasoning,
    RouteTravelMode mode = RouteTravelMode.automobile,
  }) async {
    final cleanDestination = _cleanPlace(destination);
    if (cleanDestination == null || actionMinutes <= 0) return null;

    final base = PlanningProposalEngine.findBestOptionsFromEvents(
      startDate: startDate,
      totalMinutes: actionMinutes + marginMinutes,
      events: events,
      reasoning: reasoning,
      searchDays: searchDays,
      maxOptions: _maximumRoutedCandidates,
      location: cleanDestination,
    );
    if (!base.hasOptions || base.options.isEmpty) return base;

    final routed = <PlanningProposalOption>[];
    var routeWasResolved = false;
    for (final option in base.options.take(_maximumRoutedCandidates)) {
      final appointmentStart = option.start;
      final appointmentEnd = appointmentStart.add(
        Duration(minutes: actionMinutes),
      );
      final origin = _originFor(
        appointmentStart: appointmentStart,
        events: events,
        homeAddress: homeAddress,
      );
      final arrival = _arrivalFor(
        appointmentEnd: appointmentEnd,
        events: events,
        homeAddress: homeAddress,
      );
      if (origin == null || arrival == null) continue;

      final travelGo = await _routeGateway.estimateMinutes(
        RouteTravelTimeRequest(
          origin: origin.place,
          destination: cleanDestination,
          departureAt: appointmentStart,
          mode: mode,
        ),
      );
      final travelBack = await _routeGateway.estimateMinutes(
        RouteTravelTimeRequest(
          origin: cleanDestination,
          destination: arrival.place,
          departureAt: appointmentEnd,
          mode: mode,
        ),
      );
      if (travelGo == null || travelBack == null) continue;
      routeWasResolved = true;

      final protectedStart = appointmentStart.subtract(
        Duration(minutes: travelGo),
      );
      final protectedEnd = appointmentEnd.add(
        Duration(minutes: travelBack + marginMinutes),
      );
      final candidate = _candidateEvent(
        appointmentStart: appointmentStart,
        appointmentEnd: appointmentEnd,
        destination: cleanDestination,
        travelGoMinutes: travelGo,
        travelBackMinutes: travelBack,
        marginMinutes: marginMinutes,
      );
      final eventConflict = events.any(
        (event) => EventService.eventsProtectedOverlap(event, candidate),
      );
      final reasoningConflict = SmartPlanningService.overlapsBlockedReasoning(
        start: protectedStart,
        end: protectedEnd,
        reasoning: reasoning,
      );
      if (eventConflict || reasoningConflict) continue;

      routed.add(
        PlanningProposalOption(
          start: protectedStart,
          end: protectedEnd,
          score: option.score,
          dateIso: SmartPlanningService.formatIsoDate(appointmentStart),
          startTime: SmartPlanningService.formatIsoTime(appointmentStart),
          endTime: SmartPlanningService.formatIsoTime(appointmentEnd),
          label: '${SmartPlanningService.humanDateLabel(appointmentStart)} de '
              '${SmartPlanningService.formatIsoTime(appointmentStart)} à '
              '${SmartPlanningService.formatIsoTime(appointmentEnd)}',
          reason: 'Ce créneau tient compte des trajets autour du rendez-vous.',
          travelGoMinutes: travelGo,
          travelBackMinutes: travelBack,
          departureContext: origin.context,
          arrivalContext: arrival.context,
        ),
      );
    }

    if (!routeWasResolved) return null;
    final selected = _diversifyByDay(routed, 3);
    return PlanningProposalEngineResult(
      hasOptions: selected.isNotEmpty,
      options: selected,
      explanation: selected.isEmpty
          ? 'Aucun créneau ne garde assez de temps pour les trajets.'
          : 'Les trajets ont été calculés pour chaque créneau.',
    );
  }

  static _PlaceContext? _originFor({
    required DateTime appointmentStart,
    required List<EventModel> events,
    required String homeAddress,
  }) {
    EventModel? nearest;
    DateTime? nearestEnd;
    for (final event in events) {
      final location = _cleanPlace(event.location);
      final end = EventService.parseEnd(event);
      if (location == null || end == null || end.isAfter(appointmentStart)) {
        continue;
      }
      final gap = appointmentStart.difference(end);
      if (gap > _adjacentEventHorizon || !_sameDay(end, appointmentStart)) {
        continue;
      }
      if (nearestEnd == null || end.isAfter(nearestEnd)) {
        nearest = event;
        nearestEnd = end;
      }
    }
    if (nearest != null) {
      return _PlaceContext(nearest.location.trim(), 'previous_event');
    }
    final home = _cleanPlace(homeAddress);
    return home == null ? null : _PlaceContext(home, 'home');
  }

  static _PlaceContext? _arrivalFor({
    required DateTime appointmentEnd,
    required List<EventModel> events,
    required String homeAddress,
  }) {
    EventModel? nearest;
    DateTime? nearestStart;
    for (final event in events) {
      final location = _cleanPlace(event.location);
      final start = EventService.parseStart(event);
      if (location == null || start == null || start.isBefore(appointmentEnd)) {
        continue;
      }
      final gap = start.difference(appointmentEnd);
      if (gap > _adjacentEventHorizon || !_sameDay(start, appointmentEnd)) {
        continue;
      }
      if (nearestStart == null || start.isBefore(nearestStart)) {
        nearest = event;
        nearestStart = start;
      }
    }
    if (nearest != null) {
      return _PlaceContext(nearest.location.trim(), 'next_event');
    }
    final home = _cleanPlace(homeAddress);
    return home == null ? null : _PlaceContext(home, 'home');
  }

  static EventModel _candidateEvent({
    required DateTime appointmentStart,
    required DateTime appointmentEnd,
    required String destination,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required int marginMinutes,
  }) =>
      EventModel(
        title: 'Créneau proposé',
        date: SmartPlanningService.formatIsoDate(appointmentStart),
        time: SmartPlanningService.formatIsoTime(appointmentStart),
        endTime: SmartPlanningService.formatIsoTime(appointmentEnd),
        durationMinutes: appointmentEnd.difference(appointmentStart).inMinutes,
        travelMinutes: travelGoMinutes + travelBackMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        usesSeparateTravelTimes: true,
        marginMinutes: marginMinutes,
        location: destination,
        notes: '',
        category: 'Planning',
        createdAt: appointmentStart,
        startDateTimeIso: appointmentStart.toIso8601String(),
        endDateTimeIso: appointmentEnd.toIso8601String(),
      );

  static List<PlanningProposalOption> _diversifyByDay(
    List<PlanningProposalOption> options,
    int maximum,
  ) {
    final result = <PlanningProposalOption>[];
    final days = <String>{};
    for (final option in options) {
      if (!days.add(option.dateIso)) continue;
      result.add(option);
      if (result.length == maximum) return result;
    }
    for (final option in options) {
      if (result.contains(option)) continue;
      result.add(option);
      if (result.length == maximum) return result;
    }
    return result;
  }

  static bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static String? _cleanPlace(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty || cleaned.length > 240) return null;
    return cleaned;
  }
}

final class _PlaceContext {
  const _PlaceContext(this.place, this.context);

  final String place;
  final String context;
}
