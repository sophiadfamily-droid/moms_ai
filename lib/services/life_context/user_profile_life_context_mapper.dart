import '../../models/life_context/identity_context.dart';
import '../../models/life_context/intent_context.dart';
import '../../models/life_context/life_context_provenance.dart';
import '../../models/life_context/life_context_snapshot.dart';
import '../../models/life_context/notes_context.dart';
import '../../models/life_context/schedule_context.dart';
import '../../models/user_profile.dart';

final class UserProfileLifeContextMapper {
  const UserProfileLifeContextMapper();

  LifeContextSnapshot map({
    required UserProfile profile,
    required DateTime generatedAt,
  }) {
    return LifeContextSnapshot(
      generatedAt: generatedAt,
      identity: IdentityContext(
        firstName: _explicit(profile.firstName, 'firstName'),
        birthDate: _explicit(profile.birthDate, 'birthDate'),
        age: _derived(profile.age, 'age'),
        spokenLanguage: _explicit(profile.spokenLanguage, 'spokenLanguage'),
        country: _explicit(profile.country, 'country'),
        timeZone: _explicit(profile.timeZone, 'timeZone'),
        profilePhotoPath:
            _explicit(profile.profilePhotoPath, 'profilePhotoPath'),
      ),
      household: HouseholdContext(
        familyStatus: _explicit(profile.familyStatus, 'familyStatus'),
        relationshipStatus:
            _explicit(profile.relationshipStatus, 'relationshipStatus'),
        partnerName: _explicit(profile.partnerName, 'partnerName'),
        partnerBirthDate:
            _explicit(profile.partnerBirthDate, 'partnerBirthDate'),
        partnerPhotoPath:
            _explicit(profile.partnerPhotoPath, 'partnerPhotoPath'),
        marriageDate: _explicit(profile.marriageDate, 'marriageDate'),
        engagementDate: _explicit(profile.engagementDate, 'engagementDate'),
        childcareInfo: _explicit(profile.childcareInfo, 'childcareInfo'),
        petsInfo: _explicit(profile.petsInfo, 'petsInfo'),
        children: profile.children.map(_mapChild).toList(),
      ),
      places: PlaceContext(
        importantPlaces: _explicit(profile.importantPlaces, 'importantPlaces'),
      ),
      mobility: MobilityContext(
        vehicleInfo: _explicit(profile.vehicleInfo, 'vehicleInfo'),
        transportInfo: _explicit(profile.transportInfo, 'transportInfo'),
      ),
      work: WorkContext(
        status: _explicit(profile.workStatus, 'workStatus'),
        scheduleType: _explicit(profile.workScheduleType, 'workScheduleType'),
        workDays: _explicitList(profile.workDays, 'workDays'),
        timeRanges: profile.workTimeRanges
            .map((range) => _mapTimeRange(range, 'workTimeRanges'))
            .toList(),
        variableWorkDetails:
            _explicit(profile.variableWorkDetails, 'variableWorkDetails'),
        legacyWorkHours: _historical(profile.workHours, 'workHours'),
        legacyMorningStart: _historical(profile.morningStart, 'morningStart'),
        legacyMorningEnd: _historical(profile.morningEnd, 'morningEnd'),
        legacyAfternoonStart:
            _historical(profile.afternoonStart, 'afternoonStart'),
        legacyAfternoonEnd: _historical(profile.afternoonEnd, 'afternoonEnd'),
      ),
      agenda: AgendaContext(),
      routines: RoutineContext(
        legacyHabits: _historical(profile.habits, 'habits'),
        personalActivities: profile.personalActivities
            .map((activity) => _mapActivity(activity, 'personalActivities'))
            .toList(),
        childRoutines: profile.children.map(_mapChildRoutine).toList(),
      ),
      goals: GoalContext(goals: _mapGoals(profile)),
      preferences: PreferenceContext(
        aiTone: _explicit(profile.aiTone, 'aiTone'),
        planningStyle: _explicit(profile.planningStyle, 'planningStyle'),
        notificationLevel:
            _explicit(profile.notificationLevel, 'notificationLevel'),
        wantsNotifications: LifeContextFact(
          value: profile.wantsNotifications,
          provenance: _profileProvenance('wantsNotifications'),
        ),
        foodPreferences: _explicit(profile.foodPreferences, 'foodPreferences'),
        mainLifePriority:
            _explicit(profile.mainLifePriority, 'mainLifePriority'),
        legacyPreferences: _historical(profile.preferences, 'preferences'),
      ),
      constraints: ConstraintContext(
        allergies: _explicit(profile.allergies, 'allergies'),
        medicalNotes: _explicit(profile.medicalNotes, 'medicalNotes'),
        bloodType: _explicit(profile.bloodType, 'bloodType'),
        doctorName: _explicit(profile.doctorName, 'doctorName'),
        emergencyContactName:
            _explicit(profile.emergencyContactName, 'emergencyContactName'),
        emergencyContactPhone:
            _explicit(profile.emergencyContactPhone, 'emergencyContactPhone'),
      ),
      notes: NotesContext(
        personalNotes:
            _historicalSensitive(profile.personalNotes, 'personalNotes'),
        adminNotes: _historicalSensitive(profile.adminNotes, 'adminNotes'),
        budgetNotes: _historicalSensitive(profile.budgetNotes, 'budgetNotes'),
      ),
    );
  }

  HouseholdMemberContext _mapChild(ChildProfile child) {
    return HouseholdMemberContext(
      firstName: _explicit(child.firstName, 'children.firstName'),
      birthDate: _explicit(child.birthDate, 'children.birthDate'),
      age: _explicit(child.age, 'children.age'),
      gender: _explicit(child.gender, 'children.gender'),
      school: _explicit(child.school, 'children.school'),
      className: _explicit(child.className, 'children.className'),
      notes: _explicit(child.notes, 'children.notes'),
      photoPath: _explicit(child.photoPath, 'children.photoPath'),
      allergies: _explicit(child.allergies, 'children.allergies'),
      doctor: _explicit(child.doctor, 'children.doctor'),
      medicalNotes: _explicit(child.medicalNotes, 'children.medicalNotes'),
    );
  }

  ChildRoutineContext _mapChildRoutine(ChildProfile child) {
    return ChildRoutineContext(
      childName: _explicit(child.firstName, 'children.firstName'),
      schoolTimeRanges: child.schoolTimeRanges
          .map((range) => _mapTimeRange(range, 'children.schoolTimeRanges'))
          .toList(),
      activities: child.activities
          .map((activity) => _mapActivity(activity, 'children.activities'))
          .toList(),
    );
  }

  LifeContextTimeRange _mapTimeRange(
    TimeRangeModel range,
    String sourceId,
  ) {
    return LifeContextTimeRange(
      label: _explicit(range.label, '$sourceId.label'),
      startTime: _explicit(range.startTime, '$sourceId.startTime'),
      endTime: _explicit(range.endTime, '$sourceId.endTime'),
      travelMinutes: _explicit(range.travelMinutes, '$sourceId.travelMinutes'),
      notes: _explicit(range.notes, '$sourceId.notes'),
    );
  }

  LifeContextActivity _mapActivity(ActivityModel activity, String sourceId) {
    return LifeContextActivity(
      title: _explicit(activity.title, '$sourceId.title'),
      location: _explicit(activity.location, '$sourceId.location'),
      days: _explicitList(activity.days, '$sourceId.days'),
      timeRanges: activity.timeRanges
          .map((range) => _mapTimeRange(range, '$sourceId.timeRanges'))
          .toList(),
      travelMinutes:
          _explicit(activity.travelMinutes, '$sourceId.travelMinutes'),
      notes: _explicit(activity.notes, '$sourceId.notes'),
    );
  }

  List<LifeGoal> _mapGoals(UserProfile profile) {
    final goals = <LifeGoal>[];
    _addGoal(
        goals, GoalDomain.personal, profile.personalGoals, 'personalGoals');
    _addGoal(
      goals,
      GoalDomain.professional,
      profile.businessGoals,
      'businessGoals',
    );
    _addGoal(goals, GoalDomain.family, profile.familyGoals, 'familyGoals');

    final historicalGoal = _historical(profile.goals, 'goals');
    if (historicalGoal != null) {
      goals.add(
        LifeGoal(domain: GoalDomain.historical, description: historicalGoal),
      );
    }
    return goals;
  }

  void _addGoal(
    List<LifeGoal> goals,
    GoalDomain domain,
    String value,
    String sourceId,
  ) {
    final fact = _explicit(value, sourceId);
    if (fact != null) goals.add(LifeGoal(domain: domain, description: fact));
  }

  LifeContextFact<String>? _explicit(String value, String sourceId) {
    return _stringFact(
      value,
      LifeContextSourceType.profile,
      LifeContextEvidenceType.explicit,
      sourceId,
    );
  }

  LifeContextFact<String>? _historical(String value, String sourceId) {
    return _stringFact(
      value,
      LifeContextSourceType.profile,
      LifeContextEvidenceType.historical,
      sourceId,
    );
  }

  LifeContextFact<String>? _historicalSensitive(
    String value,
    String sourceId,
  ) {
    if (value.trim().isEmpty) return null;
    return LifeContextFact(
      value: value,
      sensitivity: LifeContextSensitivity.sensitive,
      provenance: LifeContextProvenance(
        sourceType: LifeContextSourceType.profile,
        evidenceType: LifeContextEvidenceType.historical,
        sourceId: 'UserProfile.$sourceId',
      ),
    );
  }

  LifeContextFact<String>? _derived(String value, String sourceId) {
    return _stringFact(
      value,
      LifeContextSourceType.derived,
      LifeContextEvidenceType.derived,
      sourceId,
    );
  }

  LifeContextFact<String>? _stringFact(
    String value,
    LifeContextSourceType sourceType,
    LifeContextEvidenceType evidenceType,
    String sourceId,
  ) {
    if (value.trim().isEmpty) return null;
    return LifeContextFact(
      value: value,
      provenance: LifeContextProvenance(
        sourceType: sourceType,
        evidenceType: evidenceType,
        sourceId: 'UserProfile.$sourceId',
      ),
    );
  }

  LifeContextStringListFact? _explicitList(
    List<String> values,
    String sourceId,
  ) {
    if (values.isEmpty) return null;
    return LifeContextStringListFact(
      value: values,
      provenance: _profileProvenance(sourceId),
    );
  }

  LifeContextProvenance _profileProvenance(String sourceId) {
    return LifeContextProvenance(
      sourceType: LifeContextSourceType.profile,
      evidenceType: LifeContextEvidenceType.explicit,
      sourceId: 'UserProfile.$sourceId',
    );
  }
}
