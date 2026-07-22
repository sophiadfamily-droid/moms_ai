import '../models/event_model.dart';
import '../models/event_mutation_models.dart';

enum EventTargetSelectionStatus { selected, ambiguous, notFound, invalid }

final class EventTargetSelectionResult {
  final EventTargetSelectionStatus status;
  final EventModel? selected;
  final List<EventModel> candidates;
  final String diagnosticCode;

  EventTargetSelectionResult({
    required this.status,
    this.selected,
    List<EventModel> candidates = const [],
    required this.diagnosticCode,
  }) : candidates = List.unmodifiable(candidates) {
    if ((status == EventTargetSelectionStatus.selected) != (selected != null) ||
        (status == EventTargetSelectionStatus.ambiguous) !=
            this.candidates.isNotEmpty) {
      throw const FormatException('incoherent_event_selection_result');
    }
  }
}

abstract final class EventTargetSelector {
  static const int maxCandidates = 10;

  static EventTargetSelectionResult select({
    required List<EventModel> events,
    required EventMutationTarget target,
  }) {
    final stableEvents = events
        .where((event) => _hasStableId(event))
        .where((event) => _matches(event, target))
        .toList()
      ..sort(_compare);
    if (stableEvents.isEmpty) {
      final hasHistoricalMatch = events.any(
        (event) => !_hasStableId(event) && _matches(event, target),
      );
      return EventTargetSelectionResult(
        status: hasHistoricalMatch
            ? EventTargetSelectionStatus.invalid
            : EventTargetSelectionStatus.notFound,
        diagnosticCode: hasHistoricalMatch
            ? 'event_target_missing_stable_id'
            : 'event_target_not_found',
      );
    }
    if (stableEvents.length == 1) {
      return EventTargetSelectionResult(
        status: EventTargetSelectionStatus.selected,
        selected: stableEvents.single,
        diagnosticCode: 'event_target_selected',
      );
    }
    return EventTargetSelectionResult(
      status: EventTargetSelectionStatus.ambiguous,
      candidates: stableEvents.take(maxCandidates).toList(growable: false),
      diagnosticCode: stableEvents.length > maxCandidates
          ? 'event_target_ambiguous_limited'
          : 'event_target_ambiguous',
    );
  }

  static bool _matches(EventModel event, EventMutationTarget target) {
    if (target.date != null && event.date != target.date) {
      return false;
    }
    if (target.time != null && event.time != target.time) {
      return false;
    }
    if (target.category != null &&
        _comparisonKey(event.category) != _comparisonKey(target.category!)) {
      return false;
    }
    final title = target.title;
    if (title != null) {
      final eventKey = _comparisonKey(event.title);
      final targetKey = _comparisonKey(title);
      if (targetKey.length < 3 ||
          !(eventKey == targetKey || eventKey.contains(targetKey))) {
        return false;
      }
    }
    return true;
  }

  static int _compare(EventModel first, EventModel second) {
    for (final comparison in [
      first.date.compareTo(second.date),
      first.time.compareTo(second.time),
      _comparisonKey(first.title).compareTo(_comparisonKey(second.title)),
      first.id!.compareTo(second.id!),
    ]) {
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static bool _hasStableId(EventModel event) =>
      event.id != null && event.id!.trim().isNotEmpty;

  static String _comparisonKey(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll(RegExp(r'[’]'), "'")
      .replaceAll(RegExp(r'\s+'), ' ');
}
