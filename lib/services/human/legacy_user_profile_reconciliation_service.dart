import 'dart:convert';

import '../../core/identity/entity_id_generator.dart';
import '../../models/human/human_model.dart';
import '../../models/user_profile.dart';

enum LegacyHumanReconciliationStatus {
  unchanged,
  additiveUpdate,
  needsConfirmation,
}

final class LegacyHumanReconciliationResult {
  const LegacyHumanReconciliationResult({
    required this.status,
    required this.proposed,
    required this.ambiguousFields,
  });

  final LegacyHumanReconciliationStatus status;
  final HumanModel proposed;
  final List<String> ambiguousFields;
}

final class LegacyUserProfileReconciliationService {
  const LegacyUserProfileReconciliationService();

  LegacyHumanReconciliationResult reconcile({
    required HumanModel current,
    required UserProfile legacyProfile,
    Map<String, Object?>? rawLegacyProfile,
    EntityIdGenerator? idGenerator,
  }) {
    current.validate();
    final previous = current.legacyProfile;
    final incoming = Map<String, Object?>.from(
      rawLegacyProfile ?? legacyProfile.toJson(),
    );
    final next = <String, Object?>{...previous, ...incoming};
    final ambiguities = <String>[];
    final primary = current.personById(current.primaryPersonId)!;
    final nextPersons = [...current.persons];
    final nextRelationships = [...current.relationships];

    next['humanPersonId'] = current.primaryPersonId;
    final nextFirstName = legacyProfile.firstName.trim();
    if (nextFirstName.isNotEmpty &&
        nextFirstName != primary.displayName &&
        primary.evidence.source == HumanInformationSource.legacyProfile &&
        primary.evidence.confirmation != HumanConfirmationStatus.confirmed) {
      final index = nextPersons.indexWhere((person) => person.id == primary.id);
      nextPersons[index] = primary.copyWith(displayName: nextFirstName);
    }

    final previousPartnerId = _string(previous['partnerHumanPersonId']);
    final suppliedPartnerId = legacyProfile.partnerHumanPersonId.trim();
    if (previousPartnerId != null) {
      next['partnerHumanPersonId'] = previousPartnerId;
    }
    if (suppliedPartnerId.isNotEmpty &&
        previousPartnerId != null &&
        suppliedPartnerId != previousPartnerId) {
      ambiguities.add('partner');
    } else if (previousPartnerId == null &&
        suppliedPartnerId.isNotEmpty &&
        legacyProfile.partnerName.trim().isNotEmpty &&
        current.personById(suppliedPartnerId) == null &&
        idGenerator != null) {
      next['partnerHumanPersonId'] = suppliedPartnerId;
      nextPersons.add(
        HumanPerson(
          id: suppliedPartnerId,
          accountScopeId: current.accountScopeId,
          displayName: legacyProfile.partnerName.trim(),
          evidence: const HumanEvidence(
            source: HumanInformationSource.legacyProfile,
            confirmation: HumanConfirmationStatus.needsConfirmation,
          ),
        ),
      );
      nextRelationships.add(
        HumanRelationship(
          id: idGenerator.generate(),
          accountScopeId: current.accountScopeId,
          sourcePersonId: current.primaryPersonId,
          targetPersonId: suppliedPartnerId,
          type: HumanRelationshipTypes.partner,
          evidence: const HumanEvidence(
            source: HumanInformationSource.legacyProfile,
            confirmation: HumanConfirmationStatus.needsConfirmation,
          ),
        ),
      );
    } else if (_string(previous['partnerName']) !=
            _optional(legacyProfile.partnerName) &&
        previousPartnerId != null) {
      ambiguities.add('partner');
    }

    final previousChildren = _childMaps(previous['children']);
    final nextChildren = _childMaps(next['children']);
    final enrichedChildren = <Map<String, Object?>>[];
    for (final child in nextChildren) {
      final suppliedId = _string(child['humanPersonId']);
      final matched = suppliedId == null
          ? _matchExactLegacyChild(child, previousChildren)
          : previousChildren
              .where((candidate) =>
                  _string(candidate['humanPersonId']) == suppliedId)
              .firstOrNull;
      if (matched == null) {
        if (suppliedId != null &&
            current.personById(suppliedId) == null &&
            idGenerator != null) {
          nextPersons.add(
            HumanPerson(
              id: suppliedId,
              accountScopeId: current.accountScopeId,
              displayName: _string(child['firstName']),
              evidence: const HumanEvidence(
                source: HumanInformationSource.legacyProfile,
                confirmation: HumanConfirmationStatus.needsConfirmation,
              ),
            ),
          );
          nextRelationships.add(
            HumanRelationship(
              id: idGenerator.generate(),
              accountScopeId: current.accountScopeId,
              sourcePersonId: current.primaryPersonId,
              targetPersonId: suppliedId,
              type: HumanRelationshipTypes.child,
              evidence: const HumanEvidence(
                source: HumanInformationSource.legacyProfile,
                confirmation: HumanConfirmationStatus.needsConfirmation,
              ),
            ),
          );
          enrichedChildren.add(child);
          continue;
        }
        ambiguities.add('children');
        enrichedChildren.add(child);
        continue;
      }
      final id = _string(matched['humanPersonId']);
      if (id == null || current.personById(id) == null) {
        ambiguities.add('children');
        enrichedChildren.add(child);
        continue;
      }
      enrichedChildren.add({...matched, ...child, 'humanPersonId': id});
    }
    if (previousChildren.length > enrichedChildren.length) {
      ambiguities.add('children');
    }
    next['children'] = enrichedChildren;

    final proposed = current.copyWith(
      persons: nextPersons,
      relationships: nextRelationships,
      legacyProfile: next,
    );
    final changed =
        jsonEncode(proposed.toJson()) != jsonEncode(current.toJson());
    return LegacyHumanReconciliationResult(
      status: ambiguities.isNotEmpty
          ? LegacyHumanReconciliationStatus.needsConfirmation
          : (changed
              ? LegacyHumanReconciliationStatus.additiveUpdate
              : LegacyHumanReconciliationStatus.unchanged),
      proposed: proposed,
      ambiguousFields: List.unmodifiable(ambiguities.toSet()),
    );
  }

  Map<String, Object?>? _matchExactLegacyChild(
    Map<String, Object?> child,
    List<Map<String, Object?>> previous,
  ) {
    final normalized = Map<String, Object?>.from(child)
      ..remove('humanPersonId');
    final matches = previous.where((candidate) {
      final comparable = Map<String, Object?>.from(candidate)
        ..remove('humanPersonId');
      return jsonEncode(comparable) == jsonEncode(normalized);
    }).toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  List<Map<String, Object?>> _childMaps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
}
