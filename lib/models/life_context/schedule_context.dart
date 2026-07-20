import 'life_context_provenance.dart';

final class LifeContextTimeRange {
  final LifeContextFact<String>? label;
  final LifeContextFact<String>? startTime;
  final LifeContextFact<String>? endTime;
  final LifeContextFact<String>? travelMinutes;
  final LifeContextFact<String>? notes;

  const LifeContextTimeRange({
    this.label,
    this.startTime,
    this.endTime,
    this.travelMinutes,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'label': label?.toJson(),
        'startTime': startTime?.toJson(),
        'endTime': endTime?.toJson(),
        'travelMinutes': travelMinutes?.toJson(),
        'notes': notes?.toJson(),
      };
}

final class LifeContextActivity {
  final LifeContextFact<String>? title;
  final LifeContextFact<String>? location;
  final LifeContextStringListFact? days;
  final List<LifeContextTimeRange> timeRanges;
  final LifeContextFact<String>? travelMinutes;
  final LifeContextFact<String>? notes;

  LifeContextActivity({
    this.title,
    this.location,
    this.days,
    List<LifeContextTimeRange> timeRanges = const [],
    this.travelMinutes,
    this.notes,
  }) : timeRanges = List.unmodifiable(timeRanges);

  Map<String, dynamic> toJson() => {
        'title': title?.toJson(),
        'location': location?.toJson(),
        'days': days?.toJson(),
        'timeRanges': timeRanges.map((range) => range.toJson()).toList(),
        'travelMinutes': travelMinutes?.toJson(),
        'notes': notes?.toJson(),
      };
}

final class PlaceContext {
  final LifeContextFact<String>? importantPlaces;

  const PlaceContext({this.importantPlaces});

  Map<String, dynamic> toJson() => {
        'importantPlaces': importantPlaces?.toJson(),
      };
}

final class MobilityContext {
  final LifeContextFact<String>? vehicleInfo;
  final LifeContextFact<String>? transportInfo;

  const MobilityContext({this.vehicleInfo, this.transportInfo});

  Map<String, dynamic> toJson() => {
        'vehicleInfo': vehicleInfo?.toJson(),
        'transportInfo': transportInfo?.toJson(),
      };
}

final class WorkContext {
  final LifeContextFact<String>? status;
  final LifeContextFact<String>? scheduleType;
  final LifeContextStringListFact? workDays;
  final List<LifeContextTimeRange> timeRanges;
  final LifeContextFact<String>? variableWorkDetails;
  final LifeContextFact<String>? legacyWorkHours;
  final LifeContextFact<String>? legacyMorningStart;
  final LifeContextFact<String>? legacyMorningEnd;
  final LifeContextFact<String>? legacyAfternoonStart;
  final LifeContextFact<String>? legacyAfternoonEnd;

  WorkContext({
    this.status,
    this.scheduleType,
    this.workDays,
    List<LifeContextTimeRange> timeRanges = const [],
    this.variableWorkDetails,
    this.legacyWorkHours,
    this.legacyMorningStart,
    this.legacyMorningEnd,
    this.legacyAfternoonStart,
    this.legacyAfternoonEnd,
  }) : timeRanges = List.unmodifiable(timeRanges);

  Map<String, dynamic> toJson() => {
        'status': status?.toJson(),
        'scheduleType': scheduleType?.toJson(),
        'workDays': workDays?.toJson(),
        'timeRanges': timeRanges.map((range) => range.toJson()).toList(),
        'variableWorkDetails': variableWorkDetails?.toJson(),
        'legacyWorkHours': legacyWorkHours?.toJson(),
        'legacyMorningStart': legacyMorningStart?.toJson(),
        'legacyMorningEnd': legacyMorningEnd?.toJson(),
        'legacyAfternoonStart': legacyAfternoonStart?.toJson(),
        'legacyAfternoonEnd': legacyAfternoonEnd?.toJson(),
      };
}

final class AgendaContext {
  final List<LifeContextTimeRange> declaredProtectedRanges;

  AgendaContext({List<LifeContextTimeRange> declaredProtectedRanges = const []})
      : declaredProtectedRanges = List.unmodifiable(declaredProtectedRanges);

  Map<String, dynamic> toJson() => {
        'declaredProtectedRanges':
            declaredProtectedRanges.map((range) => range.toJson()).toList(),
      };
}

final class RoutineContext {
  final LifeContextFact<String>? legacyHabits;
  final List<LifeContextActivity> personalActivities;
  final List<ChildRoutineContext> childRoutines;

  RoutineContext({
    this.legacyHabits,
    List<LifeContextActivity> personalActivities = const [],
    List<ChildRoutineContext> childRoutines = const [],
  })  : personalActivities = List.unmodifiable(personalActivities),
        childRoutines = List.unmodifiable(childRoutines);

  Map<String, dynamic> toJson() => {
        'legacyHabits': legacyHabits?.toJson(),
        'personalActivities':
            personalActivities.map((activity) => activity.toJson()).toList(),
        'childRoutines':
            childRoutines.map((routine) => routine.toJson()).toList(),
      };
}

final class ChildRoutineContext {
  final LifeContextFact<String>? childName;
  final List<LifeContextTimeRange> schoolTimeRanges;
  final List<LifeContextActivity> activities;

  ChildRoutineContext({
    this.childName,
    List<LifeContextTimeRange> schoolTimeRanges = const [],
    List<LifeContextActivity> activities = const [],
  })  : schoolTimeRanges = List.unmodifiable(schoolTimeRanges),
        activities = List.unmodifiable(activities);

  Map<String, dynamic> toJson() => {
        'childName': childName?.toJson(),
        'schoolTimeRanges':
            schoolTimeRanges.map((range) => range.toJson()).toList(),
        'activities': activities.map((activity) => activity.toJson()).toList(),
      };
}
