import '../models/event_model.dart';
import 'smart_planning_service.dart';

enum EventMutationInvariantStatus {
  valid,
  planningConflict,
  invalidMutation,
  unsupportedRebase,
}

final class EventMutationInvariantResult {
  final EventMutationInvariantStatus status;
  final String diagnosticCode;

  const EventMutationInvariantResult._(this.status, this.diagnosticCode);

  const EventMutationInvariantResult.valid()
      : this._(EventMutationInvariantStatus.valid, 'event_mutation_valid');

  const EventMutationInvariantResult.planningConflict()
      : this._(
          EventMutationInvariantStatus.planningConflict,
          'event_mutation_planning_conflict',
        );

  const EventMutationInvariantResult.invalidMutation()
      : this._(
          EventMutationInvariantStatus.invalidMutation,
          'event_mutation_invalid',
        );

  const EventMutationInvariantResult.unsupportedRebase()
      : this._(
          EventMutationInvariantStatus.unsupportedRebase,
          'event_mutation_rebase_not_supported',
        );
}

/// Canonical, side-effect-free validation shared by normal Event mutations and
/// conflict rebases. Persistence remains responsible for the final revision
/// precondition.
abstract final class EventMutationInvariantService {
  static EventMutationInvariantResult validate({
    required EventModel existing,
    required EventModel proposed,
    required Iterable<EventModel> events,
    List<Map<String, dynamic>> blockedReasoning = const [],
  }) {
    if (existing.id != proposed.id ||
        proposed.durationMinutes < 0 ||
        proposed.resolvedTravelGoMinutes < 0 ||
        proposed.resolvedTravelBackMinutes < 0 ||
        proposed.marginMinutes < 0) {
      return const EventMutationInvariantResult.invalidMutation();
    }

    if (!_affectsPlanning(existing, proposed)) {
      return const EventMutationInvariantResult.valid();
    }

    if (_changesSeriesScope(existing, proposed)) {
      return const EventMutationInvariantResult.unsupportedRebase();
    }

    final protectedStart = _protectedStart(proposed);
    final protectedEnd = _protectedEnd(proposed);
    if (protectedStart == null ||
        protectedEnd == null ||
        !protectedEnd.isAfter(protectedStart)) {
      return const EventMutationInvariantResult.invalidMutation();
    }

    for (final other in events) {
      if (other.id == proposed.id) continue;
      final otherStart = _protectedStart(other);
      final otherEnd = _protectedEnd(other);
      if (otherStart == null || otherEnd == null) continue;
      if (protectedStart.isBefore(otherEnd) &&
          otherStart.isBefore(protectedEnd)) {
        return const EventMutationInvariantResult.planningConflict();
      }
    }

    if (SmartPlanningService.overlapsBlockedReasoning(
      start: protectedStart,
      end: protectedEnd,
      reasoning: blockedReasoning,
    )) {
      return const EventMutationInvariantResult.planningConflict();
    }

    return const EventMutationInvariantResult.valid();
  }

  static bool _affectsPlanning(EventModel first, EventModel second) =>
      first.date != second.date ||
      first.time != second.time ||
      first.startDateTimeIso != second.startDateTimeIso ||
      first.endTime != second.endTime ||
      first.endDateTimeIso != second.endDateTimeIso ||
      first.durationMinutes != second.durationMinutes ||
      first.travelMinutes != second.travelMinutes ||
      first.travelGoMinutes != second.travelGoMinutes ||
      first.travelBackMinutes != second.travelBackMinutes ||
      first.usesSeparateTravelTimes != second.usesSeparateTravelTimes ||
      first.marginMinutes != second.marginMinutes ||
      first.departureContext != second.departureContext ||
      first.arrivalContext != second.arrivalContext ||
      _changesSeriesScope(first, second);

  static bool _changesSeriesScope(EventModel first, EventModel second) =>
      first.isRecurring != second.isRecurring ||
      first.recurringType != second.recurringType ||
      first.recurringWeekday != second.recurringWeekday ||
      first.recurringUntil != second.recurringUntil ||
      first.parentRecurringId != second.parentRecurringId;

  static DateTime? _start(EventModel event) {
    if (event.startDateTimeIso.isNotEmpty) {
      return DateTime.tryParse(event.startDateTimeIso);
    }
    if (event.date.isEmpty || event.time.isEmpty) return null;
    return DateTime.tryParse('${event.date}T${event.time}:00');
  }

  static DateTime? _end(EventModel event) {
    if (event.endDateTimeIso.isNotEmpty) {
      return DateTime.tryParse(event.endDateTimeIso);
    }
    final start = _start(event);
    if (start == null) return null;
    return start.add(Duration(
      minutes: event.durationMinutes > 0 ? event.durationMinutes : 60,
    ));
  }

  static DateTime? _protectedStart(EventModel event) => _start(event)?.subtract(
        Duration(minutes: event.resolvedTravelGoMinutes),
      );

  static DateTime? _protectedEnd(EventModel event) => _end(event)?.add(
        Duration(
          minutes: event.resolvedTravelBackMinutes + event.marginMinutes,
        ),
      );
}
