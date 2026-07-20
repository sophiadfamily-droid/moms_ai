import 'life_context_provenance.dart';

enum GoalDomain { personal, professional, family, historical }

final class LifeGoal {
  final GoalDomain domain;
  final LifeContextFact<String> description;

  const LifeGoal({required this.domain, required this.description});

  Map<String, dynamic> toJson() => {
        'domain': domain.name,
        'description': description.toJson(),
      };
}

final class GoalContext {
  final List<LifeGoal> goals;

  GoalContext({List<LifeGoal> goals = const []})
      : goals = List.unmodifiable(goals);

  Map<String, dynamic> toJson() => {
        'goals': goals.map((goal) => goal.toJson()).toList(),
      };
}

final class PreferenceContext {
  final LifeContextFact<String>? aiTone;
  final LifeContextFact<String>? planningStyle;
  final LifeContextFact<String>? notificationLevel;
  final LifeContextFact<bool> wantsNotifications;
  final LifeContextFact<String>? foodPreferences;
  final LifeContextFact<String>? mainLifePriority;
  final LifeContextFact<String>? legacyPreferences;

  const PreferenceContext({
    this.aiTone,
    this.planningStyle,
    this.notificationLevel,
    required this.wantsNotifications,
    this.foodPreferences,
    this.mainLifePriority,
    this.legacyPreferences,
  });

  Map<String, dynamic> toJson() => {
        'aiTone': aiTone?.toJson(),
        'planningStyle': planningStyle?.toJson(),
        'notificationLevel': notificationLevel?.toJson(),
        'wantsNotifications': wantsNotifications.toJson(),
        'foodPreferences': foodPreferences?.toJson(),
        'mainLifePriority': mainLifePriority?.toJson(),
        'legacyPreferences': legacyPreferences?.toJson(),
      };
}

final class ConstraintContext {
  final LifeContextFact<String>? allergies;
  final LifeContextFact<String>? medicalNotes;
  final LifeContextFact<String>? bloodType;
  final LifeContextFact<String>? doctorName;
  final LifeContextFact<String>? emergencyContactName;
  final LifeContextFact<String>? emergencyContactPhone;

  const ConstraintContext({
    this.allergies,
    this.medicalNotes,
    this.bloodType,
    this.doctorName,
    this.emergencyContactName,
    this.emergencyContactPhone,
  });

  Map<String, dynamic> toJson() => {
        'allergies': allergies?.toJson(),
        'medicalNotes': medicalNotes?.toJson(),
        'bloodType': bloodType?.toJson(),
        'doctorName': doctorName?.toJson(),
        'emergencyContactName': emergencyContactName?.toJson(),
        'emergencyContactPhone': emergencyContactPhone?.toJson(),
      };
}
