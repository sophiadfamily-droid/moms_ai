import '../../core/identity/entity_id_generator.dart';
import '../../models/human/human_model.dart';
import '../../models/user_profile.dart';

final class LegacyUserProfileHumanAdapter {
  const LegacyUserProfileHumanAdapter();

  HumanModel migrate({
    required UserProfile profile,
    required Map<String, Object?> legacyProfile,
    required String accountScopeId,
    required EntityIdGenerator idGenerator,
  }) {
    if (accountScopeId.trim().isEmpty) {
      throw const HumanModelException('invalid_account_scope_id');
    }

    const evidence = HumanEvidence(
      source: HumanInformationSource.legacyProfile,
      confirmation: HumanConfirmationStatus.needsConfirmation,
    );
    final primaryPersonId = _idOrGenerate(
      profile.humanPersonId,
      idGenerator,
    );
    final persons = <HumanPerson>[
      HumanPerson(
        id: primaryPersonId,
        accountScopeId: accountScopeId,
        displayName: _optional(profile.firstName),
        evidence: evidence,
      ),
    ];
    final relationships = <HumanRelationship>[];

    final partnerName = profile.partnerName.trim();
    if (partnerName.isNotEmpty) {
      final partnerId = _idOrGenerate(
        profile.partnerHumanPersonId,
        idGenerator,
      );
      persons.add(
        HumanPerson(
          id: partnerId,
          accountScopeId: accountScopeId,
          displayName: partnerName,
          evidence: evidence,
        ),
      );
      relationships.add(
        HumanRelationship(
          id: idGenerator.generate(),
          accountScopeId: accountScopeId,
          sourcePersonId: primaryPersonId,
          targetPersonId: partnerId,
          type: HumanRelationshipTypes.partner,
          evidence: evidence,
          structuredNotes: _coupleDetails(profile),
        ),
      );
    }

    for (final child in profile.children) {
      final childId = _idOrGenerate(child.humanPersonId, idGenerator);
      persons.add(
        HumanPerson(
          id: childId,
          accountScopeId: accountScopeId,
          displayName: _optional(child.firstName),
          evidence: evidence,
          customFields: {
            if (child.birthDate.trim().isNotEmpty)
              'legacyBirthDate': child.birthDate,
          },
        ),
      );
      relationships.add(
        HumanRelationship(
          id: idGenerator.generate(),
          accountScopeId: accountScopeId,
          sourcePersonId: primaryPersonId,
          targetPersonId: childId,
          type: HumanRelationshipTypes.child,
          evidence: evidence,
        ),
      );
    }

    return HumanModel(
      accountScopeId: accountScopeId,
      primaryPersonId: primaryPersonId,
      persons: persons,
      relationships: relationships,
      legacyProfile: _withStableIds(
        legacyProfile: legacyProfile,
        profile: profile,
        primaryPersonId: primaryPersonId,
        partnerPersonId:
            persons.length > profile.children.length + 1 ? persons[1].id : null,
        childPersonIds: persons
            .skip(partnerName.isNotEmpty ? 2 : 1)
            .map((person) => person.id)
            .toList(growable: false),
      ),
    );
  }

  String? _optional(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Map<String, Object?> _coupleDetails(UserProfile profile) => {
        if (profile.relationshipStatus.trim().isNotEmpty)
          'relationshipStatus': profile.relationshipStatus.trim(),
        if (profile.marriageDate.trim().isNotEmpty)
          'marriageDate': profile.marriageDate.trim(),
        if (profile.engagementDate.trim().isNotEmpty)
          'engagementDate': profile.engagementDate.trim(),
      };

  String _idOrGenerate(
    String existing,
    EntityIdGenerator idGenerator,
  ) {
    final normalized = existing.trim();
    return normalized.isEmpty ? idGenerator.generate() : normalized;
  }

  Map<String, Object?> _withStableIds({
    required Map<String, Object?> legacyProfile,
    required UserProfile profile,
    required String primaryPersonId,
    required String? partnerPersonId,
    required List<String> childPersonIds,
  }) {
    final result = Map<String, Object?>.from(legacyProfile)
      ..['humanPersonId'] = primaryPersonId;
    if (partnerPersonId != null) {
      result['partnerHumanPersonId'] = partnerPersonId;
    }
    final rawChildren = legacyProfile['children'];
    final enrichedChildren = <Object?>[];
    for (var index = 0; index < profile.children.length; index++) {
      final original = rawChildren is List && index < rawChildren.length
          ? rawChildren[index]
          : null;
      final childMap = original is Map
          ? Map<String, Object?>.from(original)
          : Map<String, Object?>.from(profile.children[index].toJson());
      childMap['humanPersonId'] = childPersonIds[index];
      enrichedChildren.add(childMap);
    }
    result['children'] = enrichedChildren;
    return result;
  }
}
