import '../../models/human/human_model.dart';
import '../../models/user_profile.dart';

final class HumanModelUserProfileProjectionService {
  const HumanModelUserProfileProjectionService();

  UserProfile project({
    required HumanModel model,
    required UserProfile legacy,
  }) {
    final primary = model.personById(model.primaryPersonId);
    final childrenById = {
      for (final child in legacy.children)
        if (child.humanPersonId.trim().isNotEmpty) child.humanPersonId: child,
    };
    final projectedChildren = <ChildProfile>[];
    for (final child in legacy.children) {
      final person = model.personById(child.humanPersonId);
      projectedChildren.add(
        person == null || person.status != HumanPersonStatus.active
            ? child
            : child.copyWith(firstName: person.displayName ?? child.firstName),
      );
    }

    var partnerName = legacy.partnerName;
    final partnerId = legacy.partnerHumanPersonId.trim();
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
        }
      }
    }

    return legacy.copyWith(
      firstName: primary?.displayName?.trim().isNotEmpty == true
          ? primary!.displayName!.trim()
          : legacy.firstName,
      partnerName: partnerName,
      children: projectedChildren,
    );
  }
}
