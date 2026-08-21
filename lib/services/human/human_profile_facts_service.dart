import '../../models/human/human_model.dart';
import '../../models/user_profile.dart';

enum HumanProfileFactContextClass {
  ordinaryPersonal,
  privatePersonal,
  excluded,
}

/// Versioned bridge that moves durable profile facts onto their HumanPerson.
///
/// The direct keys remain intentionally readable by the existing profile
/// screens. Per-field evidence is stored separately so a copied legacy value
/// cannot be mistaken for an explicitly confirmed fact.
abstract final class HumanProfileFactsV1 {
  static const evidenceField = 'profileFactEvidenceV1';

  static const primaryFields = <String>{
    'profilePhotoPath',
    'city',
    'currentCountry',
    'homeAddress',
    'workAddress',
    'vehicleInfo',
    'petsInfo',
    'transportInfo',
    'childcareInfo',
    'importantPlaces',
    'allergies',
    'medicalNotes',
    'bloodType',
    'doctorName',
    'emergencyContactName',
    'emergencyContactPhone',
  };

  static const partnerFields = <String>{
    'photoPath',
    'usefulNotes',
    'workSchedule',
  };

  static const childFields = <String>{
    'age',
    'gender',
    'school',
    'notes',
    'photoPath',
    'className',
    'allergies',
    'doctor',
    'medicalNotes',
  };

  /// Classification is exhaustive for the known UserProfile V1 payload.
  static const settingsFields = <String>{
    'wantsNotifications',
    'automaticTravelCalculationEnabled',
    'agendaSafetyMarginMinutes',
    'showPersonalActivitiesInAgenda',
    'showChildActivitiesInAgenda',
    'showWorkScheduleInAgenda',
    'showSchoolScheduleInAgenda',
    'showRoutinesInAgenda',
    'aiTone',
    'planningStyle',
    'notificationLevel',
    'spokenLanguage',
    'country',
    'timeZone',
  };

  static const memoryFields = <String>{
    'habits',
    'personalNotes',
    'preferences',
    'goals',
    'mainLifePriority',
    'personalGoals',
    'businessGoals',
    'familyGoals',
    'foodPreferences',
    'adminNotes',
    'budgetNotes',
  };

  static const scheduleFields = <String>{
    'workHours',
    'workScheduleType',
    'workDays',
    'morningStart',
    'morningEnd',
    'afternoonStart',
    'afternoonEnd',
    'variableWorkDetails',
    'workTimeRanges',
    'workTravelMinutes',
    'personalActivities',
    'partnerWorkSchedule',
  };

  static const relationshipFields = <String>{
    'partnerName',
    'partnerBirthDate',
    'partnerPhotoPath',
    'partnerNotes',
    'relationshipStatus',
    'marriageDate',
    'engagementDate',
  };

  static const coreHumanFields = <String>{
    'humanPersonId',
    'partnerHumanPersonId',
    'firstName',
    'familyStatus',
    'workStatus',
    'children',
    'age',
    'birthDate',
    ...primaryFields,
  };

  static const obsoleteOrDerivedFields = <String>{'age'};

  /// Closed, privacy-reviewed set of profile facts that may leave HumanModel
  /// for the generic Life Context. Health, emergency and photo fields remain
  /// available to their dedicated profile screens but are fail-closed here.
  static const contextClasses = <String, HumanProfileFactContextClass>{
    'city': HumanProfileFactContextClass.ordinaryPersonal,
    'currentCountry': HumanProfileFactContextClass.ordinaryPersonal,
    'vehicleInfo': HumanProfileFactContextClass.ordinaryPersonal,
    'petsInfo': HumanProfileFactContextClass.ordinaryPersonal,
    'transportInfo': HumanProfileFactContextClass.ordinaryPersonal,
    'age': HumanProfileFactContextClass.ordinaryPersonal,
    'gender': HumanProfileFactContextClass.ordinaryPersonal,
    'className': HumanProfileFactContextClass.ordinaryPersonal,
    'homeAddress': HumanProfileFactContextClass.privatePersonal,
    'workAddress': HumanProfileFactContextClass.privatePersonal,
    'childcareInfo': HumanProfileFactContextClass.privatePersonal,
    'importantPlaces': HumanProfileFactContextClass.privatePersonal,
    'usefulNotes': HumanProfileFactContextClass.privatePersonal,
    'school': HumanProfileFactContextClass.privatePersonal,
    'notes': HumanProfileFactContextClass.privatePersonal,
  };

  static HumanProfileFactContextClass contextClassFor(String field) =>
      contextClasses[field] ?? HumanProfileFactContextClass.excluded;

  static Map<String, Object?> primaryValues(UserProfile profile) => {
        'profilePhotoPath': profile.profilePhotoPath,
        'city': profile.city,
        'currentCountry': profile.currentCountry,
        'homeAddress': profile.homeAddress,
        'workAddress': profile.workAddress,
        'vehicleInfo': profile.vehicleInfo,
        'petsInfo': profile.petsInfo,
        'transportInfo': profile.transportInfo,
        'childcareInfo': profile.childcareInfo,
        'importantPlaces': profile.importantPlaces,
        'allergies': profile.allergies,
        'medicalNotes': profile.medicalNotes,
        'bloodType': profile.bloodType,
        'doctorName': profile.doctorName,
        'emergencyContactName': profile.emergencyContactName,
        'emergencyContactPhone': profile.emergencyContactPhone,
      };

  static Map<String, Object?> partnerValues(UserProfile profile) => {
        'photoPath': profile.partnerPhotoPath,
        'usefulNotes': profile.partnerNotes,
        'workSchedule': profile.partnerWorkSchedule,
      };

  static Map<String, Object?> childValues(ChildProfile child) => {
        'age': child.age,
        'gender': child.gender,
        'school': child.school,
        'notes': child.notes,
        'photoPath': child.photoPath,
        'className': child.className,
        'allergies': child.allergies,
        'doctor': child.doctor,
        'medicalNotes': child.medicalNotes,
      };

  static Map<String, Object?> merge({
    required Map<String, Object?> current,
    required Map<String, Object?> incoming,
    required Set<String> managedFields,
    required HumanEvidence evidence,
    bool clearEmpty = true,
    bool preserveConfirmed = false,
  }) {
    final next = <String, Object?>{...current};
    final evidenceByField = _evidenceMap(current[evidenceField]);
    for (final key in managedFields) {
      final currentEvidence = _readEvidence(evidenceByField[key]);
      if (preserveConfirmed &&
          currentEvidence?.source == HumanInformationSource.explicitUserInput &&
          currentEvidence?.confirmation == HumanConfirmationStatus.confirmed) {
        continue;
      }
      final value = _normalized(incoming[key]);
      if (value == null) {
        if (clearEmpty) {
          next.remove(key);
          evidenceByField.remove(key);
        }
      } else {
        next[key] = value;
        evidenceByField[key] = evidence.toJson();
      }
    }
    if (evidenceByField.isEmpty) {
      next.remove(evidenceField);
    } else {
      next[evidenceField] = evidenceByField;
    }
    return next;
  }

  static HumanEvidence? evidenceFor(HumanPerson person, String field) {
    final raw = _evidenceMap(person.customFields[evidenceField])[field];
    return _readEvidence(raw);
  }

  static String? text(HumanPerson person, String field) {
    final value = person.customFields[field];
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Map<String, Object?> _evidenceMap(Object? value) {
    if (value is! Map) return <String, Object?>{};
    return Map<String, Object?>.from(value);
  }

  static HumanEvidence? _readEvidence(Object? value) {
    if (value == null) return null;
    try {
      return HumanEvidence.fromJson(value);
    } on Object {
      return null;
    }
  }

  static Object? _normalized(Object? value) {
    if (value is String) {
      final normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    }
    return value;
  }
}
