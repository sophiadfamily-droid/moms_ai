class TimeRangeModel {
  final String label;
  final String startTime;
  final String endTime;
  final String travelMinutes;
  final String notes;

  TimeRangeModel({
    this.label = "",
    this.startTime = "",
    this.endTime = "",
    this.travelMinutes = "",
    this.notes = "",
  });

  TimeRangeModel copyWith({
    String? label,
    String? startTime,
    String? endTime,
    String? travelMinutes,
    String? notes,
  }) {
    return TimeRangeModel(
      label: label ?? this.label,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "label": label,
      "startTime": startTime,
      "endTime": endTime,
      "travelMinutes": travelMinutes,
      "notes": notes,
    };
  }

  factory TimeRangeModel.fromJson(Map<String, dynamic> json) {
    return TimeRangeModel(
      label: json["label"] ?? "",
      startTime: json["startTime"] ?? "",
      endTime: json["endTime"] ?? "",
      travelMinutes: json["travelMinutes"] ?? "",
      notes: json["notes"] ?? "",
    );
  }
}

class ActivityModel {
  final String title;
  final String location;
  final List<String> days;
  final List<TimeRangeModel> timeRanges;
  final String travelMinutes;
  final String notes;

  ActivityModel({
    required this.title,
    this.location = "",
    this.days = const [],
    this.timeRanges = const [],
    this.travelMinutes = "",
    this.notes = "",
  });

  ActivityModel copyWith({
    String? title,
    String? location,
    List<String>? days,
    List<TimeRangeModel>? timeRanges,
    String? travelMinutes,
    String? notes,
  }) {
    return ActivityModel(
      title: title ?? this.title,
      location: location ?? this.location,
      days: days ?? this.days,
      timeRanges: timeRanges ?? this.timeRanges,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "location": location,
      "days": days,
      "timeRanges": timeRanges.map((range) => range.toJson()).toList(),
      "travelMinutes": travelMinutes,
      "notes": notes,
    };
  }

  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    return ActivityModel(
      title: json["title"] ?? "",
      location: json["location"] ?? "",
      days: (json["days"] as List? ?? []).map((day) => day.toString()).toList(),
      timeRanges: (json["timeRanges"] as List? ?? [])
          .map((range) =>
              TimeRangeModel.fromJson(Map<String, dynamic>.from(range)))
          .toList(),
      travelMinutes: json["travelMinutes"] ?? "",
      notes: json["notes"] ?? "",
    );
  }
}

class ChildProfile {
  static const _knownJsonKeys = {
    "humanPersonId",
    "firstName",
    "age",
    "birthDate",
    "gender",
    "school",
    "notes",
    "photoPath",
    "className",
    "allergies",
    "doctor",
    "medicalNotes",
    "schoolTimeRanges",
    "activities",
    "activity",
    "activityDays",
    "activityTime",
  };

  final String humanPersonId;
  final Map<String, dynamic> legacyExtensions;
  final String firstName;
  final String age;
  final String birthDate;
  final String gender;
  final String school;
  final String notes;
  final String photoPath;

  final String className;
  final String allergies;
  final String doctor;
  final String medicalNotes;
  final List<TimeRangeModel> schoolTimeRanges;
  final List<ActivityModel> activities;

  ChildProfile({
    this.humanPersonId = "",
    this.legacyExtensions = const {},
    required this.firstName,
    required this.age,
    required this.birthDate,
    required this.gender,
    required this.school,
    required this.notes,
    this.photoPath = "",
    this.className = "",
    this.allergies = "",
    this.doctor = "",
    this.medicalNotes = "",
    this.schoolTimeRanges = const [],
    this.activities = const [],
  });

  ChildProfile copyWith({
    String? humanPersonId,
    Map<String, dynamic>? legacyExtensions,
    String? firstName,
    String? age,
    String? birthDate,
    String? gender,
    String? school,
    String? notes,
    String? photoPath,
    String? className,
    String? allergies,
    String? doctor,
    String? medicalNotes,
    List<TimeRangeModel>? schoolTimeRanges,
    List<ActivityModel>? activities,
  }) {
    return ChildProfile(
      humanPersonId: humanPersonId ?? this.humanPersonId,
      legacyExtensions: legacyExtensions ?? this.legacyExtensions,
      firstName: firstName ?? this.firstName,
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      school: school ?? this.school,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      className: className ?? this.className,
      allergies: allergies ?? this.allergies,
      doctor: doctor ?? this.doctor,
      medicalNotes: medicalNotes ?? this.medicalNotes,
      schoolTimeRanges: schoolTimeRanges ?? this.schoolTimeRanges,
      activities: activities ?? this.activities,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...legacyExtensions,
      "humanPersonId": humanPersonId,
      "firstName": firstName,
      "age": age,
      "birthDate": birthDate,
      "gender": gender,
      "school": school,
      "notes": notes,
      "photoPath": photoPath,
      "className": className,
      "allergies": allergies,
      "doctor": doctor,
      "medicalNotes": medicalNotes,
      "schoolTimeRanges":
          schoolTimeRanges.map((range) => range.toJson()).toList(),
      "activities": activities.map((activity) => activity.toJson()).toList(),
    };
  }

  factory ChildProfile.fromJson(Map<String, dynamic> json) {
    final legacyActivity = json["activity"]?.toString() ?? "";
    final legacyExtensions = Map<String, dynamic>.from(json)
      ..removeWhere((key, _) => _knownJsonKeys.contains(key));

    return ChildProfile(
      humanPersonId: json["humanPersonId"] ?? "",
      legacyExtensions: legacyExtensions,
      firstName: json["firstName"] ?? "",
      age: json["age"] ?? "",
      birthDate: json["birthDate"] ?? "",
      gender: json["gender"] ?? "",
      school: json["school"] ?? "",
      notes: json["notes"] ?? "",
      photoPath: json["photoPath"] ?? "",
      className: json["className"] ?? "",
      allergies: json["allergies"] ?? "",
      doctor: json["doctor"] ?? "",
      medicalNotes: json["medicalNotes"] ?? "",
      schoolTimeRanges: (json["schoolTimeRanges"] as List? ?? [])
          .map((range) =>
              TimeRangeModel.fromJson(Map<String, dynamic>.from(range)))
          .toList(),
      activities: (json["activities"] as List? ?? [])
          .map((activity) =>
              ActivityModel.fromJson(Map<String, dynamic>.from(activity)))
          .toList()
        ..addAll(
          legacyActivity.isEmpty
              ? []
              : [
                  ActivityModel(
                    title: legacyActivity,
                    days: (json["activityDays"] as List? ?? [])
                        .map((day) => day.toString())
                        .toList(),
                    timeRanges: [
                      TimeRangeModel(
                        startTime: json["activityTime"] ?? "",
                        endTime: "",
                      ),
                    ],
                    notes: "",
                  )
                ],
        ),
    );
  }
}

class UserProfile {
  static const _knownJsonKeys = {
    "humanPersonId",
    "partnerHumanPersonId",
    "firstName",
    "familyStatus",
    "workStatus",
    "partnerName",
    "wantsNotifications",
    "children",
    "age",
    "birthDate",
    "profilePhotoPath",
    "partnerBirthDate",
    "partnerPhotoPath",
    "relationshipStatus",
    "marriageDate",
    "engagementDate",
    "workHours",
    "workScheduleType",
    "workDays",
    "morningStart",
    "morningEnd",
    "afternoonStart",
    "afternoonEnd",
    "variableWorkDetails",
    "workTimeRanges",
    "habits",
    "personalNotes",
    "preferences",
    "goals",
    "allergies",
    "medicalNotes",
    "bloodType",
    "doctorName",
    "emergencyContactName",
    "emergencyContactPhone",
    "aiTone",
    "planningStyle",
    "notificationLevel",
    "mainLifePriority",
    "spokenLanguage",
    "country",
    "timeZone",
    "personalGoals",
    "businessGoals",
    "familyGoals",
    "vehicleInfo",
    "petsInfo",
    "transportInfo",
    "childcareInfo",
    "foodPreferences",
    "adminNotes",
    "budgetNotes",
    "importantPlaces",
    "personalActivities",
  };

  final String humanPersonId;
  final String partnerHumanPersonId;
  final Map<String, dynamic> legacyExtensions;
  final String firstName;
  final String familyStatus;
  final String workStatus;
  final String partnerName;
  final bool wantsNotifications;
  final List<ChildProfile> children;

  final String age;
  final String birthDate;
  final String profilePhotoPath;

  final String partnerBirthDate;
  final String partnerPhotoPath;
  final String relationshipStatus;
  final String marriageDate;
  final String engagementDate;

  final String workHours;
  final String workScheduleType;
  final List<String> workDays;
  final String morningStart;
  final String morningEnd;
  final String afternoonStart;
  final String afternoonEnd;
  final String variableWorkDetails;
  final List<TimeRangeModel> workTimeRanges;

  final String habits;
  final String personalNotes;
  final String preferences;
  final String goals;

  final String allergies;
  final String medicalNotes;
  final String bloodType;
  final String doctorName;
  final String emergencyContactName;
  final String emergencyContactPhone;

  final String aiTone;
  final String planningStyle;
  final String notificationLevel;
  final String mainLifePriority;
  final String spokenLanguage;
  final String country;
  final String timeZone;

  final String personalGoals;
  final String businessGoals;
  final String familyGoals;

  final String vehicleInfo;
  final String petsInfo;
  final String transportInfo;
  final String childcareInfo;
  final String foodPreferences;
  final String adminNotes;
  final String budgetNotes;
  final String importantPlaces;

  final List<ActivityModel> personalActivities;

  UserProfile({
    this.humanPersonId = "",
    this.partnerHumanPersonId = "",
    this.legacyExtensions = const {},
    required this.firstName,
    required this.familyStatus,
    required this.workStatus,
    required this.partnerName,
    required this.wantsNotifications,
    required this.children,
    this.age = "",
    this.birthDate = "",
    this.profilePhotoPath = "",
    this.partnerBirthDate = "",
    this.partnerPhotoPath = "",
    this.relationshipStatus = "",
    this.marriageDate = "",
    this.engagementDate = "",
    this.workHours = "",
    this.workScheduleType = "",
    this.workDays = const [],
    this.morningStart = "",
    this.morningEnd = "",
    this.afternoonStart = "",
    this.afternoonEnd = "",
    this.variableWorkDetails = "",
    this.workTimeRanges = const [],
    this.habits = "",
    this.personalNotes = "",
    this.preferences = "",
    this.goals = "",
    this.allergies = "",
    this.medicalNotes = "",
    this.bloodType = "",
    this.doctorName = "",
    this.emergencyContactName = "",
    this.emergencyContactPhone = "",
    this.aiTone = "",
    this.planningStyle = "",
    this.notificationLevel = "",
    this.mainLifePriority = "",
    this.spokenLanguage = "",
    this.country = "",
    this.timeZone = "",
    this.personalGoals = "",
    this.businessGoals = "",
    this.familyGoals = "",
    this.vehicleInfo = "",
    this.petsInfo = "",
    this.transportInfo = "",
    this.childcareInfo = "",
    this.foodPreferences = "",
    this.adminNotes = "",
    this.budgetNotes = "",
    this.importantPlaces = "",
    this.personalActivities = const [],
  });

  UserProfile copyWith({
    String? humanPersonId,
    String? partnerHumanPersonId,
    Map<String, dynamic>? legacyExtensions,
    String? firstName,
    String? familyStatus,
    String? workStatus,
    String? partnerName,
    bool? wantsNotifications,
    List<ChildProfile>? children,
    String? age,
    String? birthDate,
    String? profilePhotoPath,
    String? partnerBirthDate,
    String? partnerPhotoPath,
    String? relationshipStatus,
    String? marriageDate,
    String? engagementDate,
    String? workHours,
    String? workScheduleType,
    List<String>? workDays,
    String? morningStart,
    String? morningEnd,
    String? afternoonStart,
    String? afternoonEnd,
    String? variableWorkDetails,
    List<TimeRangeModel>? workTimeRanges,
    String? habits,
    String? personalNotes,
    String? preferences,
    String? goals,
    String? allergies,
    String? medicalNotes,
    String? bloodType,
    String? doctorName,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? aiTone,
    String? planningStyle,
    String? notificationLevel,
    String? mainLifePriority,
    String? spokenLanguage,
    String? country,
    String? timeZone,
    String? personalGoals,
    String? businessGoals,
    String? familyGoals,
    String? vehicleInfo,
    String? petsInfo,
    String? transportInfo,
    String? childcareInfo,
    String? foodPreferences,
    String? adminNotes,
    String? budgetNotes,
    String? importantPlaces,
    List<ActivityModel>? personalActivities,
  }) {
    return UserProfile(
      humanPersonId: humanPersonId ?? this.humanPersonId,
      partnerHumanPersonId: partnerHumanPersonId ?? this.partnerHumanPersonId,
      legacyExtensions: legacyExtensions ?? this.legacyExtensions,
      firstName: firstName ?? this.firstName,
      familyStatus: familyStatus ?? this.familyStatus,
      workStatus: workStatus ?? this.workStatus,
      partnerName: partnerName ?? this.partnerName,
      wantsNotifications: wantsNotifications ?? this.wantsNotifications,
      children: children ?? this.children,
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      partnerBirthDate: partnerBirthDate ?? this.partnerBirthDate,
      partnerPhotoPath: partnerPhotoPath ?? this.partnerPhotoPath,
      relationshipStatus: relationshipStatus ?? this.relationshipStatus,
      marriageDate: marriageDate ?? this.marriageDate,
      engagementDate: engagementDate ?? this.engagementDate,
      workHours: workHours ?? this.workHours,
      workScheduleType: workScheduleType ?? this.workScheduleType,
      workDays: workDays ?? this.workDays,
      morningStart: morningStart ?? this.morningStart,
      morningEnd: morningEnd ?? this.morningEnd,
      afternoonStart: afternoonStart ?? this.afternoonStart,
      afternoonEnd: afternoonEnd ?? this.afternoonEnd,
      variableWorkDetails: variableWorkDetails ?? this.variableWorkDetails,
      workTimeRanges: workTimeRanges ?? this.workTimeRanges,
      habits: habits ?? this.habits,
      personalNotes: personalNotes ?? this.personalNotes,
      preferences: preferences ?? this.preferences,
      goals: goals ?? this.goals,
      allergies: allergies ?? this.allergies,
      medicalNotes: medicalNotes ?? this.medicalNotes,
      bloodType: bloodType ?? this.bloodType,
      doctorName: doctorName ?? this.doctorName,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      aiTone: aiTone ?? this.aiTone,
      planningStyle: planningStyle ?? this.planningStyle,
      notificationLevel: notificationLevel ?? this.notificationLevel,
      mainLifePriority: mainLifePriority ?? this.mainLifePriority,
      spokenLanguage: spokenLanguage ?? this.spokenLanguage,
      country: country ?? this.country,
      timeZone: timeZone ?? this.timeZone,
      personalGoals: personalGoals ?? this.personalGoals,
      businessGoals: businessGoals ?? this.businessGoals,
      familyGoals: familyGoals ?? this.familyGoals,
      vehicleInfo: vehicleInfo ?? this.vehicleInfo,
      petsInfo: petsInfo ?? this.petsInfo,
      transportInfo: transportInfo ?? this.transportInfo,
      childcareInfo: childcareInfo ?? this.childcareInfo,
      foodPreferences: foodPreferences ?? this.foodPreferences,
      adminNotes: adminNotes ?? this.adminNotes,
      budgetNotes: budgetNotes ?? this.budgetNotes,
      importantPlaces: importantPlaces ?? this.importantPlaces,
      personalActivities: personalActivities ?? this.personalActivities,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...legacyExtensions,
      "humanPersonId": humanPersonId,
      "partnerHumanPersonId": partnerHumanPersonId,
      "firstName": firstName,
      "familyStatus": familyStatus,
      "workStatus": workStatus,
      "partnerName": partnerName,
      "wantsNotifications": wantsNotifications,
      "children": children.map((child) => child.toJson()).toList(),
      "age": age,
      "birthDate": birthDate,
      "profilePhotoPath": profilePhotoPath,
      "partnerBirthDate": partnerBirthDate,
      "partnerPhotoPath": partnerPhotoPath,
      "relationshipStatus": relationshipStatus,
      "marriageDate": marriageDate,
      "engagementDate": engagementDate,
      "workHours": workHours,
      "workScheduleType": workScheduleType,
      "workDays": workDays,
      "morningStart": morningStart,
      "morningEnd": morningEnd,
      "afternoonStart": afternoonStart,
      "afternoonEnd": afternoonEnd,
      "variableWorkDetails": variableWorkDetails,
      "workTimeRanges": workTimeRanges.map((range) => range.toJson()).toList(),
      "habits": habits,
      "personalNotes": personalNotes,
      "preferences": preferences,
      "goals": goals,
      "allergies": allergies,
      "medicalNotes": medicalNotes,
      "bloodType": bloodType,
      "doctorName": doctorName,
      "emergencyContactName": emergencyContactName,
      "emergencyContactPhone": emergencyContactPhone,
      "aiTone": aiTone,
      "planningStyle": planningStyle,
      "notificationLevel": notificationLevel,
      "mainLifePriority": mainLifePriority,
      "spokenLanguage": spokenLanguage,
      "country": country,
      "timeZone": timeZone,
      "personalGoals": personalGoals,
      "businessGoals": businessGoals,
      "familyGoals": familyGoals,
      "vehicleInfo": vehicleInfo,
      "petsInfo": petsInfo,
      "transportInfo": transportInfo,
      "childcareInfo": childcareInfo,
      "foodPreferences": foodPreferences,
      "adminNotes": adminNotes,
      "budgetNotes": budgetNotes,
      "importantPlaces": importantPlaces,
      "personalActivities":
          personalActivities.map((activity) => activity.toJson()).toList(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final legacyExtensions = Map<String, dynamic>.from(json)
      ..removeWhere((key, _) => _knownJsonKeys.contains(key));
    return UserProfile(
      humanPersonId: json["humanPersonId"] ?? "",
      partnerHumanPersonId: json["partnerHumanPersonId"] ?? "",
      legacyExtensions: legacyExtensions,
      firstName: json["firstName"] ?? "",
      familyStatus: json["familyStatus"] ?? "",
      workStatus: json["workStatus"] ?? "",
      partnerName: json["partnerName"] ?? "",
      wantsNotifications: json["wantsNotifications"] ?? true,
      children: (json["children"] as List? ?? [])
          .map((child) =>
              ChildProfile.fromJson(Map<String, dynamic>.from(child)))
          .toList(),
      age: json["age"] ?? "",
      birthDate: json["birthDate"] ?? "",
      profilePhotoPath: json["profilePhotoPath"] ?? "",
      partnerBirthDate: json["partnerBirthDate"] ?? "",
      partnerPhotoPath: json["partnerPhotoPath"] ?? "",
      relationshipStatus: json["relationshipStatus"] ?? "",
      marriageDate: json["marriageDate"] ?? "",
      engagementDate: json["engagementDate"] ?? "",
      workHours: json["workHours"] ?? "",
      workScheduleType: json["workScheduleType"] ?? "",
      workDays: (json["workDays"] as List? ?? [])
          .map((day) => day.toString())
          .toList(),
      morningStart: json["morningStart"] ?? "",
      morningEnd: json["morningEnd"] ?? "",
      afternoonStart: json["afternoonStart"] ?? "",
      afternoonEnd: json["afternoonEnd"] ?? "",
      variableWorkDetails: json["variableWorkDetails"] ?? "",
      workTimeRanges: (json["workTimeRanges"] as List? ?? [])
          .map((range) =>
              TimeRangeModel.fromJson(Map<String, dynamic>.from(range)))
          .toList(),
      habits: json["habits"] ?? "",
      personalNotes: json["personalNotes"] ?? "",
      preferences: json["preferences"] ?? "",
      goals: json["goals"] ?? "",
      allergies: json["allergies"] ?? "",
      medicalNotes: json["medicalNotes"] ?? "",
      bloodType: json["bloodType"] ?? "",
      doctorName: json["doctorName"] ?? "",
      emergencyContactName: json["emergencyContactName"] ?? "",
      emergencyContactPhone: json["emergencyContactPhone"] ?? "",
      aiTone: json["aiTone"] ?? "",
      planningStyle: json["planningStyle"] ?? "",
      notificationLevel: json["notificationLevel"] ?? "",
      mainLifePriority: json["mainLifePriority"] ?? "",
      spokenLanguage: json["spokenLanguage"] ?? "",
      country: json["country"] ?? "",
      timeZone: json["timeZone"] ?? "",
      personalGoals: json["personalGoals"] ?? "",
      businessGoals: json["businessGoals"] ?? "",
      familyGoals: json["familyGoals"] ?? "",
      vehicleInfo: json["vehicleInfo"] ?? "",
      petsInfo: json["petsInfo"] ?? "",
      transportInfo: json["transportInfo"] ?? "",
      childcareInfo: json["childcareInfo"] ?? "",
      foodPreferences: json["foodPreferences"] ?? "",
      adminNotes: json["adminNotes"] ?? "",
      budgetNotes: json["budgetNotes"] ?? "",
      importantPlaces: json["importantPlaces"] ?? "",
      personalActivities: (json["personalActivities"] as List? ?? [])
          .map((activity) =>
              ActivityModel.fromJson(Map<String, dynamic>.from(activity)))
          .toList(),
    );
  }
}
