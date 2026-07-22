import '../models/event_model.dart';

enum EventMutationStatus {
  success,
  notFound,
  revisionConflict,
  alreadyExists,
  scopeMismatch,
  invalidMutation,
  persistenceFailure,
}

final class EventMutationResult {
  final EventMutationStatus status;
  final String diagnosticCode;
  final EventModel? event;

  const EventMutationResult._(this.status, this.diagnosticCode, this.event);

  const EventMutationResult.success(EventModel event)
      : this._(EventMutationStatus.success, 'event_mutation_updated', event);

  const EventMutationResult.notFound()
      : this._(
          EventMutationStatus.notFound,
          'event_mutation_target_disappeared',
          null,
        );

  const EventMutationResult.revisionConflict()
      : this._(
          EventMutationStatus.revisionConflict,
          'event_mutation_revision_conflict',
          null,
        );

  const EventMutationResult.alreadyExists()
      : this._(
          EventMutationStatus.alreadyExists,
          'event_sync_already_exists',
          null,
        );

  const EventMutationResult.scopeMismatch()
      : this._(
          EventMutationStatus.scopeMismatch,
          'event_sync_scope_mismatch',
          null,
        );

  const EventMutationResult.invalid()
      : this._(
          EventMutationStatus.invalidMutation,
          'event_mutation_invalid',
          null,
        );

  const EventMutationResult.persistenceFailure()
      : this._(
          EventMutationStatus.persistenceFailure,
          'event_mutation_persistence_failure',
          null,
        );
}

final class EventBatchMutationResult {
  final int successCount;
  final int conflictCount;
  final int failureCount;
  final List<EventMutationResult> results;

  EventBatchMutationResult(List<EventMutationResult> results)
      : results = List.unmodifiable(results),
        successCount = results
            .where((result) => result.status == EventMutationStatus.success)
            .length,
        conflictCount = results
            .where(
              (result) =>
                  result.status == EventMutationStatus.revisionConflict ||
                  result.status == EventMutationStatus.alreadyExists ||
                  result.status == EventMutationStatus.scopeMismatch ||
                  result.status == EventMutationStatus.notFound,
            )
            .length,
        failureCount = results
            .where(
              (result) =>
                  result.status == EventMutationStatus.persistenceFailure ||
                  result.status == EventMutationStatus.invalidMutation,
            )
            .length;

  bool get isComplete => results.isNotEmpty && successCount == results.length;
}
