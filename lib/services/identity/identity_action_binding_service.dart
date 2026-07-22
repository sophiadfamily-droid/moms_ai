import '../../core/identity/entity_id_generator.dart';
import '../../models/conversation_models.dart';
import 'identity_application_models.dart';

final class IdentityActionBindingService {
  final EntityIdGenerator _idGenerator;

  const IdentityActionBindingService({
    required EntityIdGenerator idGenerator,
  }) : _idGenerator = idGenerator;

  PendingIdentityActionBinding create({
    required String accountScopeId,
    required IdentityActionContinuation continuation,
  }) {
    return PendingIdentityActionBinding(
      bindingId: _idGenerator.generate(),
      accountScopeId: accountScopeId,
      continuation: continuation,
    );
  }

  IdentityActionBindingResult fromApplicationResult({
    required PendingIdentityActionBinding binding,
    required IdentityApplicationResult applicationResult,
  }) {
    if (binding.isApplied) return _alreadyApplied(binding);
    return switch (applicationResult.status) {
      IdentityApplicationStatus.resolved => _attach(
          binding,
          applicationResult.resolvedEntity!.id,
          'identity_attached_directly',
        ),
      IdentityApplicationStatus.ambiguous ||
      IdentityApplicationStatus.needsConfirmation =>
        _result(
          binding,
          IdentityActionBindingStatus.pendingClarification,
          'identity_clarification_required',
        ),
      IdentityApplicationStatus.notFound => _result(
          binding,
          IdentityActionBindingStatus.invalid,
          'identity_not_found',
        ),
      IdentityApplicationStatus.invalid => _result(
          binding,
          IdentityActionBindingStatus.invalid,
          'identity_resolution_invalid',
        ),
      IdentityApplicationStatus.repositoryFailure => _result(
          binding,
          IdentityActionBindingStatus.invalid,
          'identity_repository_failure',
        ),
    };
  }

  IdentityActionBindingResult invalid({
    required PendingIdentityActionBinding binding,
    required String diagnosticCode,
  }) {
    return _result(
      binding,
      IdentityActionBindingStatus.invalid,
      diagnosticCode,
    );
  }

  IdentityActionBindingResult pendingCreation(
    PendingIdentityActionBinding binding,
  ) {
    return _result(
      binding,
      IdentityActionBindingStatus.pendingCreation,
      'identity_creation_required',
    );
  }

  IdentityActionBindingResult alreadyApplied(
    PendingIdentityActionBinding binding,
  ) {
    return _alreadyApplied(binding);
  }

  PendingIdentityActionBinding linkClarification({
    required PendingIdentityActionBinding binding,
    required String clarificationId,
  }) {
    if (binding.isApplied || binding.clarificationId != null) {
      throw const ConversationIdentityException('binding_already_consumed');
    }
    return binding.copyWith(clarificationId: clarificationId);
  }

  IdentityActionBindingResult applyClarification({
    required PendingIdentityActionBinding binding,
    required IdentityClarificationResult clarificationResult,
    required String bindingId,
    required String clarificationId,
  }) {
    if (binding.bindingId != bindingId) {
      return _result(
        binding,
        IdentityActionBindingStatus.invalid,
        'binding_id_mismatch',
      );
    }
    if (binding.clarificationId != clarificationId ||
        clarificationResult.clarificationId != clarificationId) {
      return _result(
        binding,
        IdentityActionBindingStatus.invalid,
        'clarification_id_mismatch',
      );
    }
    if (binding.isApplied) return _alreadyApplied(binding);
    return switch (clarificationResult.status) {
      IdentityClarificationStatus.resolved => _attach(
          binding,
          clarificationResult.resolvedEntityId!,
          'identity_attached_after_clarification',
        ),
      IdentityClarificationStatus.stillAmbiguous => _result(
          binding,
          IdentityActionBindingStatus.pendingClarification,
          'identity_clarification_pending',
        ),
      IdentityClarificationStatus.cancelled => _result(
          binding,
          IdentityActionBindingStatus.cancelled,
          'identity_clarification_cancelled',
        ),
      IdentityClarificationStatus.expired => _result(
          binding,
          IdentityActionBindingStatus.expired,
          'identity_clarification_expired',
        ),
      IdentityClarificationStatus.invalid => _result(
          binding,
          IdentityActionBindingStatus.invalid,
          'identity_clarification_invalid',
        ),
    };
  }

  IdentityActionBindingResult applyCreation({
    required PendingIdentityActionBinding binding,
    required IdentityCreationResult creationResult,
  }) {
    if (binding.isApplied) return _alreadyApplied(binding);
    return switch (creationResult.status) {
      IdentityCreationStatus.created => _attach(
          binding,
          creationResult.createdEntityId!,
          'identity_attached_after_creation',
        ),
      IdentityCreationStatus.stillPending ||
      IdentityCreationStatus.repositoryFailure =>
        _result(
          binding,
          IdentityActionBindingStatus.pendingCreation,
          'identity_creation_pending',
        ),
      IdentityCreationStatus.cancelled => _result(
          binding,
          IdentityActionBindingStatus.cancelled,
          'identity_creation_cancelled',
        ),
      IdentityCreationStatus.expired => _result(
          binding,
          IdentityActionBindingStatus.expired,
          'identity_creation_expired',
        ),
      IdentityCreationStatus.alreadyExists ||
      IdentityCreationStatus.invalid =>
        _result(
          binding,
          IdentityActionBindingStatus.invalid,
          'identity_creation_not_attached',
        ),
    };
  }

  IdentityActionBindingResult _attach(
    PendingIdentityActionBinding binding,
    String entityId,
    String diagnosticCode,
  ) {
    final attached = binding.copyWith(resolvedEntityId: entityId);
    return _result(
      attached,
      IdentityActionBindingStatus.attached,
      diagnosticCode,
      resolvedEntityId: entityId,
    );
  }

  IdentityActionBindingResult _alreadyApplied(
    PendingIdentityActionBinding binding,
  ) {
    return _result(
      binding,
      IdentityActionBindingStatus.alreadyApplied,
      'identity_binding_already_applied',
    );
  }

  IdentityActionBindingResult _result(
    PendingIdentityActionBinding binding,
    IdentityActionBindingStatus status,
    String diagnosticCode, {
    String? resolvedEntityId,
  }) {
    return IdentityActionBindingResult(
      status: status,
      bindingId: binding.bindingId,
      actionDraftId: binding.continuation.actionDraftId,
      target: binding.continuation.target,
      resolvedEntityId: resolvedEntityId,
      diagnosticCode: diagnosticCode,
      binding: binding,
    );
  }
}
