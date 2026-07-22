import '../models/event_model.dart';

enum EventMutationStatus {
  success,
  notFound,
  revisionConflict,
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
