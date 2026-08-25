import '../../models/human/human_model.dart';
import '../../models/revisioned_domain_models.dart';
import '../../models/user_profile.dart';
import 'human_profile_facts_service.dart';
import '../structured_schedule_profile_service.dart';

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
      if (person?.status == HumanPersonStatus.historical) continue;
      projectedChildren.add(
        person == null
            ? child
            : child.copyWith(
                firstName: person.displayName ?? child.firstName,
                birthDate: _birthDate(person) ?? child.birthDate,
                age: _fact(person, 'age') ?? child.age,
                gender: _fact(person, 'gender') ?? child.gender,
                school: _fact(person, 'school') ?? child.school,
                notes: _fact(person, 'notes') ?? child.notes,
                photoPath: _fact(person, 'photoPath') ?? child.photoPath,
                className: _fact(person, 'className') ?? child.className,
                allergies: _fact(person, 'allergies') ?? child.allergies,
                doctor: _fact(person, 'doctor') ?? child.doctor,
                medicalNotes:
                    _fact(person, 'medicalNotes') ?? child.medicalNotes,
              ),
      );
    }

    var partnerName = restored.partnerName;
    var partnerBirthDate = restored.partnerBirthDate;
    final partnerId = restored.partnerHumanPersonId.trim();
    HumanRelationship? partnerRelationship;
    if (partnerId.isNotEmpty && childrenById[partnerId] == null) {
      final matchingRelations = model.relationships
          .where(
            (relation) =>
                relation.status == HumanRecordStatus.active &&
                relation.sourcePersonId == model.primaryPersonId &&
                relation.targetPersonId == partnerId &&
                (relation.type == HumanRelationshipTypes.partner ||
                    relation.type == HumanRelationshipTypes.spouse),
          )
          .toList(growable: false);
      if (matchingRelations.length == 1) {
        partnerRelationship = matchingRelations.single;
        final person = model.personById(partnerId);
        if (person?.status == HumanPersonStatus.active &&
            person?.displayName?.trim().isNotEmpty == true) {
          partnerName = person!.displayName!.trim();
          partnerBirthDate = _birthDate(person) ?? partnerBirthDate;
        }
      }
    }

    final partner = partnerId.isEmpty ? null : model.personById(partnerId);
    final partnerWasRemoved = partnerId.isNotEmpty &&
        partner != null &&
        (partner.status == HumanPersonStatus.historical ||
            partnerRelationship == null);

    final projected = restored.copyWith(
      firstName: primary?.displayName?.trim().isNotEmpty == true
          ? primary!.displayName!.trim()
          : restored.firstName,
      birthDate: primary == null
          ? restored.birthDate
          : (_birthDate(primary) ?? restored.birthDate),
      familyStatus:
          _textField(primary, 'familyStatus') ?? restored.familyStatus,
      workStatus: _textField(primary, 'workStatus') ?? restored.workStatus,
      profilePhotoPath:
          _fact(primary, 'profilePhotoPath') ?? restored.profilePhotoPath,
      city: _fact(primary, 'city') ?? restored.city,
      currentCountry:
          _fact(primary, 'currentCountry') ?? restored.currentCountry,
      homeAddress: _fact(primary, 'homeAddress') ?? restored.homeAddress,
      workAddress: _fact(primary, 'workAddress') ?? restored.workAddress,
      vehicleInfo: _fact(primary, 'vehicleInfo') ?? restored.vehicleInfo,
      petsInfo: _fact(primary, 'petsInfo') ?? restored.petsInfo,
      transportInfo: _fact(primary, 'transportInfo') ?? restored.transportInfo,
      childcareInfo: _fact(primary, 'childcareInfo') ?? restored.childcareInfo,
      importantPlaces:
          _fact(primary, 'importantPlaces') ?? restored.importantPlaces,
      allergies: _fact(primary, 'allergies') ?? restored.allergies,
      medicalNotes: _fact(primary, 'medicalNotes') ?? restored.medicalNotes,
      bloodType: _fact(primary, 'bloodType') ?? restored.bloodType,
      doctorName: _fact(primary, 'doctorName') ?? restored.doctorName,
      emergencyContactName: _fact(primary, 'emergencyContactName') ??
          restored.emergencyContactName,
      emergencyContactPhone: _fact(primary, 'emergencyContactPhone') ??
          restored.emergencyContactPhone,
      partnerHumanPersonId: partnerWasRemoved ? '' : partnerId,
      partnerName: partnerWasRemoved ? '' : partnerName,
      partnerBirthDate: partnerWasRemoved ? '' : partnerBirthDate,
      partnerPhotoPath: partnerWasRemoved
          ? ''
          : (_fact(partner, 'photoPath') ?? restored.partnerPhotoPath),
      partnerNotes: partnerWasRemoved
          ? ''
          : (_fact(partner, 'usefulNotes') ?? restored.partnerNotes),
      partnerWorkSchedule: partnerWasRemoved
          ? ''
          : (_fact(partner, 'workSchedule') ?? restored.partnerWorkSchedule),
      relationshipStatus: partnerWasRemoved
          ? ''
          : (_relationshipFact(partnerRelationship, 'relationshipStatus') ??
              restored.relationshipStatus),
      marriageDate: partnerWasRemoved
          ? ''
          : (_relationshipFact(partnerRelationship, 'marriageDate') ??
              restored.marriageDate),
      engagementDate: partnerWasRemoved
          ? ''
          : (_relationshipFact(partnerRelationship, 'engagementDate') ??
              restored.engagementDate),
      children: projectedChildren,
    );
    return StructuredScheduleProfileService.projectOntoCompatibilityProfile(
      model: model,
      profile: projected,
    );
  }

  String? _birthDate(HumanPerson person) {
    final value = person.customFields['birthDate'] ??
        person.customFields['legacyBirthDate'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  String? _fact(HumanPerson? person, String field) =>
      person == null ? null : HumanProfileFactsV1.text(person, field);

  String? _textField(HumanPerson? person, String field) {
    final value = person?.customFields[field];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  String? _relationshipFact(
    HumanRelationship? relationship,
    String field,
  ) {
    final value = relationship?.structuredNotes[field];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }
}
