import 'dart:convert';

import '../../core/identity/entity_id_generator.dart';
import '../../models/human/human_model.dart';
import '../../models/user_profile.dart';

enum LegacyHumanReconciliationStatus {
  unchanged,
  additiveUpdate,
  needsConfirmation,
}

abstract final class HumanLegacyReconciliationMarker {
  static const field = 'humanReconciliationRejectedMarker';

  static String forModel(HumanModel model) {
    final legacy = Map<String, Object?>.from(model.legacyProfile)
      ..remove(field);
    final comparable = model.copyWith(legacyProfile: legacy);
    var hash = 0x811c9dc5;
    for (final codeUnit in jsonEncode(comparable.toJson()).codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }
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

  HumanModel applyExplicitProfileEdit({
    required HumanModel current,
    required UserProfile profile,
    required EntityIdGenerator idGenerator,
  }) {
    current.validate();
    final persons = [...current.persons];
    final relationships = [...current.relationships];
    final retainedRelatedIds = <String>{};

    void upsertPerson(
      String id,
      String name,
      String birthDate, {
      String? familyStatus,
      String? workStatus,
    }) {
      if (id.trim().isEmpty) return;
      final index = persons.indexWhere((person) => person.id == id);
      final existing = index < 0 ? null : persons[index];
      final fields = <String, Object?>{
        ...?existing?.customFields,
        if (birthDate.trim().isNotEmpty) 'birthDate': birthDate.trim(),
        if (familyStatus?.trim().isNotEmpty == true)
          'familyStatus': familyStatus!.trim(),
        if (workStatus?.trim().isNotEmpty == true)
          'workStatus': workStatus!.trim(),
      };
      if (birthDate.trim().isEmpty) {
        fields.remove('birthDate');
        fields.remove('legacyBirthDate');
      }
      if (familyStatus != null && familyStatus.trim().isEmpty) {
        fields.remove('familyStatus');
      }
      if (workStatus != null && workStatus.trim().isEmpty) {
        fields.remove('workStatus');
      }
      final person = existing == null
          ? HumanPerson(
              id: id,
              accountScopeId: current.accountScopeId,
              displayName: _optional(name),
              evidence: _explicitEvidence,
              customFields: fields,
            )
          : existing.copyWith(
              displayName: _optional(name),
              clearDisplayName: name.trim().isEmpty,
              status: HumanPersonStatus.active,
              evidence: _explicitEvidence,
              customFields: fields,
            );
      if (index < 0) {
        persons.add(person);
      } else {
        persons[index] = person;
      }
    }

    void ensureRelationship(
      String targetId,
      String type, {
      Map<String, Object?> structuredNotes = const {},
    }) {
      retainedRelatedIds.add(targetId);
      final index = relationships.indexWhere(
        (relation) =>
            relation.sourcePersonId == current.primaryPersonId &&
            relation.targetPersonId == targetId &&
            relation.status == HumanRecordStatus.active,
      );
      if (index >= 0) {
        relationships[index] = relationships[index].copyWith(
          evidence: _explicitEvidence,
          structuredNotes: structuredNotes,
        );
        return;
      }
      relationships.add(
        HumanRelationship(
          id: idGenerator.generate(),
          accountScopeId: current.accountScopeId,
          sourcePersonId: current.primaryPersonId,
          targetPersonId: targetId,
          type: type,
          evidence: _explicitEvidence,
          structuredNotes: structuredNotes,
        ),
      );
    }

    upsertPerson(
      current.primaryPersonId,
      profile.firstName,
      profile.birthDate,
      familyStatus: profile.familyStatus,
      workStatus: profile.workStatus,
    );
    final partnerId = profile.partnerHumanPersonId.trim();
    if (partnerId.isNotEmpty && profile.partnerName.trim().isNotEmpty) {
      upsertPerson(partnerId, profile.partnerName, profile.partnerBirthDate);
      ensureRelationship(
        partnerId,
        HumanRelationshipTypes.partner,
        structuredNotes: _coupleDetails(profile),
      );
    }
    for (final child in profile.children) {
      final childId = child.humanPersonId.trim();
      if (childId.isEmpty) continue;
      upsertPerson(childId, child.firstName, child.birthDate);
      ensureRelationship(childId, HumanRelationshipTypes.child);
    }

    final previousRelatedIds = <String>{
      if (_string(current.legacyProfile['partnerHumanPersonId']) case final id?)
        id,
      for (final child in _childMaps(current.legacyProfile['children']))
        if (_string(child['humanPersonId']) case final id?) id,
    };
    for (var index = 0; index < relationships.length; index++) {
      final relation = relationships[index];
      if (relation.sourcePersonId == current.primaryPersonId &&
          previousRelatedIds.contains(relation.targetPersonId) &&
          !retainedRelatedIds.contains(relation.targetPersonId) &&
          relation.status == HumanRecordStatus.active) {
        relationships[index] = relation.copyWith(
          status: HumanRecordStatus.historical,
          evidence: _explicitEvidence,
        );
      }
    }

    final legacy = Map<String, Object?>.from(profile.toJson())
      ..['humanPersonId'] = current.primaryPersonId;
    return current.copyWith(
      persons: persons,
      relationships: relationships,
      legacyProfile: legacy,
    );
  }

  Map<String, Object?> _coupleDetails(UserProfile profile) => {
        if (profile.relationshipStatus.trim().isNotEmpty)
          'relationshipStatus': profile.relationshipStatus.trim(),
        if (profile.marriageDate.trim().isNotEmpty)
          'marriageDate': profile.marriageDate.trim(),
        if (profile.engagementDate.trim().isNotEmpty)
          'engagementDate': profile.engagementDate.trim(),
      };

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

    void syncProfileFields(
      String personId,
      Map<String, String> managedFields,
    ) {
      final index = nextPersons.indexWhere((person) => person.id == personId);
      if (index < 0) return;
      final person = nextPersons[index];
      final fields = <String, Object?>{...person.customFields};
      for (final entry in managedFields.entries) {
        final value = entry.value.trim();
        if (value.isEmpty) {
          fields.remove(entry.key);
          if (entry.key == 'birthDate') fields.remove('legacyBirthDate');
        } else {
          fields[entry.key] = value;
        }
      }
      nextPersons[index] = person.copyWith(customFields: fields);
    }

    next['humanPersonId'] = current.primaryPersonId;
    syncProfileFields(
      primary.id,
      {
        'birthDate': legacyProfile.birthDate,
        'familyStatus': legacyProfile.familyStatus,
        'workStatus': legacyProfile.workStatus,
      },
    );
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
          customFields: {
            if (legacyProfile.partnerBirthDate.trim().isNotEmpty)
              'birthDate': legacyProfile.partnerBirthDate.trim(),
          },
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

    final effectivePartnerId = previousPartnerId ??
        (suppliedPartnerId.isEmpty ? null : suppliedPartnerId);
    if (effectivePartnerId != null) {
      syncProfileFields(
        effectivePartnerId,
        {'birthDate': legacyProfile.partnerBirthDate},
      );
      final relationshipIndex = nextRelationships.indexWhere(
        (relation) =>
            relation.sourcePersonId == current.primaryPersonId &&
            relation.targetPersonId == effectivePartnerId &&
            relation.status == HumanRecordStatus.active &&
            (relation.type == HumanRelationshipTypes.partner ||
                relation.type == HumanRelationshipTypes.spouse),
      );
      if (relationshipIndex >= 0) {
        nextRelationships[relationshipIndex] =
            nextRelationships[relationshipIndex].copyWith(
          structuredNotes: _coupleDetails(legacyProfile),
        );
      }
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
              customFields: {
                if (_string(child['birthDate']) case final birthDate?)
                  'birthDate': birthDate,
              },
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
      syncProfileFields(
        id,
        {'birthDate': _string(child['birthDate']) ?? ''},
      );
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
    final rejectedMarker =
        _string(current.legacyProfile[HumanLegacyReconciliationMarker.field]);
    if (rejectedMarker != null &&
        rejectedMarker == HumanLegacyReconciliationMarker.forModel(proposed)) {
      return LegacyHumanReconciliationResult(
        status: LegacyHumanReconciliationStatus.unchanged,
        proposed: current,
        ambiguousFields: const [],
      );
    }
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

const _explicitEvidence = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);
