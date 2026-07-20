import 'life_context_provenance.dart';

final class IdentityContext {
  final LifeContextFact<String>? firstName;
  final LifeContextFact<String>? birthDate;
  final LifeContextFact<String>? age;
  final LifeContextFact<String>? spokenLanguage;
  final LifeContextFact<String>? country;
  final LifeContextFact<String>? timeZone;
  final LifeContextFact<String>? profilePhotoPath;

  const IdentityContext({
    this.firstName,
    this.birthDate,
    this.age,
    this.spokenLanguage,
    this.country,
    this.timeZone,
    this.profilePhotoPath,
  });

  Map<String, dynamic> toJson() => {
        'firstName': firstName?.toJson(),
        'birthDate': birthDate?.toJson(),
        'age': age?.toJson(),
        'spokenLanguage': spokenLanguage?.toJson(),
        'country': country?.toJson(),
        'timeZone': timeZone?.toJson(),
        'profilePhotoPath': profilePhotoPath?.toJson(),
      };
}

final class HouseholdMemberContext {
  final LifeContextFact<String>? firstName;
  final LifeContextFact<String>? birthDate;
  final LifeContextFact<String>? age;
  final LifeContextFact<String>? gender;
  final LifeContextFact<String>? school;
  final LifeContextFact<String>? className;
  final LifeContextFact<String>? notes;
  final LifeContextFact<String>? photoPath;
  final LifeContextFact<String>? allergies;
  final LifeContextFact<String>? doctor;
  final LifeContextFact<String>? medicalNotes;
  const HouseholdMemberContext({
    this.firstName,
    this.birthDate,
    this.age,
    this.gender,
    this.school,
    this.className,
    this.notes,
    this.photoPath,
    this.allergies,
    this.doctor,
    this.medicalNotes,
  });

  Map<String, dynamic> toJson() => {
        'firstName': firstName?.toJson(),
        'birthDate': birthDate?.toJson(),
        'age': age?.toJson(),
        'gender': gender?.toJson(),
        'school': school?.toJson(),
        'className': className?.toJson(),
        'notes': notes?.toJson(),
        'photoPath': photoPath?.toJson(),
        'allergies': allergies?.toJson(),
        'doctor': doctor?.toJson(),
        'medicalNotes': medicalNotes?.toJson(),
      };
}

final class HouseholdContext {
  final LifeContextFact<String>? familyStatus;
  final LifeContextFact<String>? relationshipStatus;
  final LifeContextFact<String>? partnerName;
  final LifeContextFact<String>? partnerBirthDate;
  final LifeContextFact<String>? partnerPhotoPath;
  final LifeContextFact<String>? marriageDate;
  final LifeContextFact<String>? engagementDate;
  final LifeContextFact<String>? childcareInfo;
  final LifeContextFact<String>? petsInfo;
  final List<HouseholdMemberContext> children;

  HouseholdContext({
    this.familyStatus,
    this.relationshipStatus,
    this.partnerName,
    this.partnerBirthDate,
    this.partnerPhotoPath,
    this.marriageDate,
    this.engagementDate,
    this.childcareInfo,
    this.petsInfo,
    List<HouseholdMemberContext> children = const [],
  }) : children = List.unmodifiable(children);

  Map<String, dynamic> toJson() => {
        'familyStatus': familyStatus?.toJson(),
        'relationshipStatus': relationshipStatus?.toJson(),
        'partnerName': partnerName?.toJson(),
        'partnerBirthDate': partnerBirthDate?.toJson(),
        'partnerPhotoPath': partnerPhotoPath?.toJson(),
        'marriageDate': marriageDate?.toJson(),
        'engagementDate': engagementDate?.toJson(),
        'childcareInfo': childcareInfo?.toJson(),
        'petsInfo': petsInfo?.toJson(),
        'children': children.map((child) => child.toJson()).toList(),
      };
}
