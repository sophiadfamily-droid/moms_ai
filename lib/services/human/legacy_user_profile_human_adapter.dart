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
    final primaryPersonId = idGenerator.generate();
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
      final partnerId = idGenerator.generate();
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
        ),
      );
    }

    for (final child in profile.children) {
      final childId = idGenerator.generate();
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
      legacyProfile: legacyProfile,
    );
  }

  String? _optional(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
