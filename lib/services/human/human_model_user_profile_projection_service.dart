import '../../models/human/human_model.dart';
import '../../models/revisioned_domain_models.dart';
import '../../models/user_profile.dart';

final class HumanModelUserProfileProjectionService {
  const HumanModelUserProfileProjectionService();

  UserProfile project({
    required HumanModel model,
    required UserProfile legacy,
  }) {
    final restoredJson = Map<String, dynamic>.from(legacy.toJson());
    for (final key in ProfileFieldOwnership.humanModelFields) {
      if (model.legacyProfile.containsKey(key)) {
        restoredJson[key] = model.legacyProfile[key];
      }
    }
    final restored = UserProfile.fromJson(restoredJson);
    final primary = model.personById(model.primaryPersonId);
    final childrenById = {
      for (final child in restored.children)
        if (child.humanPersonId.trim().isNotEmpty) child.humanPersonId: child,
    };
    final projectedChildren = <ChildProfile>[];
    for (final child in restored.children) {
      final person = model.personById(child.humanPersonId);
      projectedChildren.add(
        person == null || person.status != HumanPersonStatus.active
            ? child
            : child.copyWith(
                firstName: person.displayName ?? child.firstName,
                birthDate: _birthDate(person) ?? child.birthDate,
              ),
      );
    }

    var partnerName = restored.partnerName;
    var partnerBirthDate = restored.partnerBirthDate;
    final partnerId = restored.partnerHumanPersonId.trim();
    if (partnerId.isNotEmpty && childrenById[partnerId] == null) {
      final matchingRelations = model.relationships.where(
        (relation) =>
            relation.status == HumanRecordStatus.active &&
            relation.sourcePersonId == model.primaryPersonId &&
            relation.targetPersonId == partnerId &&
            (relation.type == HumanRelationshipTypes.partner ||
                relation.type == HumanRelationshipTypes.spouse),
      );
      if (matchingRelations.length == 1) {
        final person = model.personById(partnerId);
        if (person?.status == HumanPersonStatus.active &&
            person?.displayName?.trim().isNotEmpty == true) {
          partnerName = person!.displayName!.trim();
          partnerBirthDate = _birthDate(person) ?? partnerBirthDate;
        }
      }
    }

    return restored.copyWith(
      firstName: primary?.displayName?.trim().isNotEmpty == true
          ? primary!.displayName!.trim()
          : restored.firstName,
      birthDate: primary == null
          ? restored.birthDate
          : (_birthDate(primary) ?? restored.birthDate),
      partnerName: partnerName,
      partnerBirthDate: partnerBirthDate,
      children: projectedChildren,
    );
  }

  String? _birthDate(HumanPerson person) {
    final value = person.customFields['birthDate'] ??
        person.customFields['legacyBirthDate'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }
}
