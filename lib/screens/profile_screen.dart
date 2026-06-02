import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/storage_service.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  final void Function(UserProfile)? onSave;

  const ProfileScreen({
    super.key,
    required this.profile,
    this.onSave,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker imagePicker = ImagePicker();

  late UserProfile profile;

  late TextEditingController firstNameController;
  late TextEditingController birthDateController;
  late TextEditingController partnerNameController;
  late TextEditingController partnerBirthDateController;
  late TextEditingController marriageDateController;
  late TextEditingController engagementDateController;

  late TextEditingController variableWorkDetailsController;
  late TextEditingController personalNotesController;
  late TextEditingController allergiesController;
  late TextEditingController medicalNotesController;
  late TextEditingController bloodTypeController;
  late TextEditingController doctorNameController;
  late TextEditingController emergencyContactNameController;
  late TextEditingController emergencyContactPhoneController;

  late TextEditingController personalGoalsController;
  late TextEditingController businessGoalsController;
  late TextEditingController familyGoalsController;

  late TextEditingController vehicleInfoController;
  late TextEditingController petsInfoController;
  late TextEditingController transportInfoController;
  late TextEditingController childcareInfoController;
  late TextEditingController foodPreferencesController;
  late TextEditingController adminNotesController;
  late TextEditingController budgetNotesController;
  late TextEditingController importantPlacesController;

  late String selectedFamilyStatus;
  late String selectedWorkStatus;
  late bool wantsNotifications;
  late List<ChildProfile> children;
  late List<TimeRangeModel> workTimeRanges;
  late List<ActivityModel> personalActivities;

  String relationshipStatus = "";
  String workScheduleType = "";
  List<String> selectedWorkDays = [];

  String aiTone = "";
  String planningStyle = "";
  String notificationLevel = "";
  String mainLifePriority = "";
  String spokenLanguage = "";
  String country = "";
  String timeZone = "";

  final Color bg = const Color(0xFFF8EFEA);
  final Color accent = const Color(0xFFE95D5D);
  final Color textDark = const Color(0xFF11181C);
  final Color textSoft = const Color(0xFF8B6F67);

  final List<String> familyStatuses = [
    "Je vis seule ",
    "Je vis avec mon partenaire ",
    "Nous sommes une famille avec enfants ",
    "Famille monoparentale ",
    "C'est un peu compliqué ",
  ];

  final List<String> workStatuses = [
    "Je suis maman au foyer ",
    "Je suis salariée ",
    "Je suis entrepreneuse ",
    "Je suis étudiante ",
    "Autre / recherche ",
  ];

  final List<String> relationshipStatuses = [
    "En couple",
    "Fiancée",
    "Mariée",
  ];

  final List<String> workScheduleTypes = [
    "Horaires réguliers",
    "Planning flexible",
  ];

  final List<String> weekDays = [
    "Lundi",
    "Mardi",
    "Mercredi",
    "Jeudi",
    "Vendredi",
    "Samedi",
    "Dimanche",
  ];

  final List<String> aiTones = [
    "Doux",
    "Motivant",
    "Direct",
    "Très détaillé",
  ];

  final List<String> planningStyles = [
    "Flexible",
    "Très structuré",
    "Équilibré",
  ];

  final List<String> notificationLevels = [
    "Minimal",
    "Normal",
    "Détaillé",
  ];

  final List<String> priorities = [
    "Famille",
    "Travail",
    "Santé",
    "Business",
    "Maison",
  ];

  @override
  void initState() {
    super.initState();

    profile = widget.profile;

    firstNameController = TextEditingController(text: profile.firstName);
    birthDateController =
        TextEditingController(text: normalizeFrenchDate(profile.birthDate));
    partnerNameController = TextEditingController(text: profile.partnerName);
    partnerBirthDateController = TextEditingController(
        text: normalizeFrenchDate(profile.partnerBirthDate));
    marriageDateController =
        TextEditingController(text: normalizeFrenchDate(profile.marriageDate));
    engagementDateController = TextEditingController(
        text: normalizeFrenchDate(profile.engagementDate));

    variableWorkDetailsController =
        TextEditingController(text: profile.variableWorkDetails);
    personalNotesController = TextEditingController(
      text: profile.personalNotes.isNotEmpty
          ? profile.personalNotes
          : profile.habits,
    );

    allergiesController = TextEditingController(text: profile.allergies);
    medicalNotesController = TextEditingController(text: profile.medicalNotes);
    bloodTypeController = TextEditingController(text: profile.bloodType);
    doctorNameController = TextEditingController(text: profile.doctorName);
    emergencyContactNameController =
        TextEditingController(text: profile.emergencyContactName);
    emergencyContactPhoneController =
        TextEditingController(text: profile.emergencyContactPhone);

    personalGoalsController =
        TextEditingController(text: profile.personalGoals);
    businessGoalsController =
        TextEditingController(text: profile.businessGoals);
    familyGoalsController = TextEditingController(text: profile.familyGoals);

    vehicleInfoController = TextEditingController(text: profile.vehicleInfo);
    petsInfoController = TextEditingController(text: profile.petsInfo);
    transportInfoController =
        TextEditingController(text: profile.transportInfo);
    childcareInfoController =
        TextEditingController(text: profile.childcareInfo);
    foodPreferencesController =
        TextEditingController(text: profile.foodPreferences);
    adminNotesController = TextEditingController(text: profile.adminNotes);
    budgetNotesController = TextEditingController(text: profile.budgetNotes);
    importantPlacesController =
        TextEditingController(text: profile.importantPlaces);

    selectedFamilyStatus = inferFamilyStatus(profile);
    selectedWorkStatus = inferWorkStatus(profile);
    wantsNotifications = profile.wantsNotifications;
    children = List.from(profile.children);
    workTimeRanges = List.from(profile.workTimeRanges);
    personalActivities = List.from(profile.personalActivities);

    relationshipStatus = profile.relationshipStatus.isNotEmpty
        ? profile.relationshipStatus
        : relationshipStatuses.first;

    workScheduleType = profile.workScheduleType.isNotEmpty
        ? profile.workScheduleType
        : workScheduleTypes.first;

    selectedWorkDays = List.from(profile.workDays);

    aiTone = profile.aiTone.isNotEmpty ? profile.aiTone : aiTones.first;
    planningStyle = profile.planningStyle.isNotEmpty
        ? profile.planningStyle
        : planningStyles.last;
    notificationLevel = profile.notificationLevel.isNotEmpty
        ? profile.notificationLevel
        : notificationLevels[1];
    mainLifePriority = profile.mainLifePriority.isNotEmpty
        ? profile.mainLifePriority
        : priorities.first;
    spokenLanguage =
        profile.spokenLanguage.isNotEmpty ? profile.spokenLanguage : "Français";
    country = profile.country.isNotEmpty ? profile.country : "France";
    timeZone = profile.timeZone.isNotEmpty ? profile.timeZone : "Europe/Paris";
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profile != widget.profile) {
      setState(() {
        syncProfile(widget.profile);
      });
    }
  }

  void syncProfile(UserProfile newProfile) {
    profile = newProfile;

    firstNameController.text = newProfile.firstName;
    birthDateController.text = normalizeFrenchDate(newProfile.birthDate);
    partnerNameController.text = newProfile.partnerName;
    partnerBirthDateController.text =
        normalizeFrenchDate(newProfile.partnerBirthDate);
    marriageDateController.text = normalizeFrenchDate(newProfile.marriageDate);
    engagementDateController.text =
        normalizeFrenchDate(newProfile.engagementDate);
    variableWorkDetailsController.text = newProfile.variableWorkDetails;
    personalNotesController.text = newProfile.personalNotes.isNotEmpty
        ? newProfile.personalNotes
        : newProfile.habits;
    allergiesController.text = newProfile.allergies;
    medicalNotesController.text = newProfile.medicalNotes;
    bloodTypeController.text = newProfile.bloodType;
    doctorNameController.text = newProfile.doctorName;
    emergencyContactNameController.text = newProfile.emergencyContactName;
    emergencyContactPhoneController.text = newProfile.emergencyContactPhone;
    personalGoalsController.text = newProfile.personalGoals;
    businessGoalsController.text = newProfile.businessGoals;
    familyGoalsController.text = newProfile.familyGoals;
    vehicleInfoController.text = newProfile.vehicleInfo;
    petsInfoController.text = newProfile.petsInfo;
    transportInfoController.text = newProfile.transportInfo;
    childcareInfoController.text = newProfile.childcareInfo;
    foodPreferencesController.text = newProfile.foodPreferences;
    adminNotesController.text = newProfile.adminNotes;
    budgetNotesController.text = newProfile.budgetNotes;
    importantPlacesController.text = newProfile.importantPlaces;

    selectedFamilyStatus = inferFamilyStatus(newProfile);
    selectedWorkStatus = inferWorkStatus(newProfile);
    wantsNotifications = newProfile.wantsNotifications;
    children = List.from(newProfile.children);
    workTimeRanges = List.from(newProfile.workTimeRanges);
    personalActivities = List.from(newProfile.personalActivities);
    relationshipStatus = newProfile.relationshipStatus.isNotEmpty
        ? newProfile.relationshipStatus
        : relationshipStatuses.first;
    workScheduleType = newProfile.workScheduleType.isNotEmpty
        ? newProfile.workScheduleType
        : workScheduleTypes.first;
    selectedWorkDays = List.from(newProfile.workDays);
    aiTone = newProfile.aiTone.isNotEmpty ? newProfile.aiTone : aiTones.first;
    planningStyle = newProfile.planningStyle.isNotEmpty
        ? newProfile.planningStyle
        : planningStyles.last;
    notificationLevel = newProfile.notificationLevel.isNotEmpty
        ? newProfile.notificationLevel
        : notificationLevels[1];
    mainLifePriority = newProfile.mainLifePriority.isNotEmpty
        ? newProfile.mainLifePriority
        : priorities.first;
    spokenLanguage = newProfile.spokenLanguage.isNotEmpty
        ? newProfile.spokenLanguage
        : "Français";
    country = newProfile.country.isNotEmpty ? newProfile.country : "France";
    timeZone =
        newProfile.timeZone.isNotEmpty ? newProfile.timeZone : "Europe/Paris";
  }

  @override
  void dispose() {
    firstNameController.dispose();
    birthDateController.dispose();
    partnerNameController.dispose();
    partnerBirthDateController.dispose();
    marriageDateController.dispose();
    engagementDateController.dispose();
    variableWorkDetailsController.dispose();
    personalNotesController.dispose();
    allergiesController.dispose();
    medicalNotesController.dispose();
    bloodTypeController.dispose();
    doctorNameController.dispose();
    emergencyContactNameController.dispose();
    emergencyContactPhoneController.dispose();
    personalGoalsController.dispose();
    businessGoalsController.dispose();
    familyGoalsController.dispose();
    vehicleInfoController.dispose();
    petsInfoController.dispose();
    transportInfoController.dispose();
    childcareInfoController.dispose();
    foodPreferencesController.dispose();
    adminNotesController.dispose();
    budgetNotesController.dispose();
    importantPlacesController.dispose();
    super.dispose();
  }

  String mapFamilyStatus(String status) {
    final s = status.toLowerCase();

    if (s.contains("couple") || s.contains("partenaire")) {
      return familyStatuses[1];
    }

    if (s.contains("enfant") || s.contains("famille")) {
      return familyStatuses[2];
    }

    if (s.contains("maman") || s.contains("monoparent")) {
      return familyStatuses[3];
    }

    if (s.contains("compli")) {
      return familyStatuses[4];
    }

    return familyStatuses[0];
  }

  bool showPartnerField() {
    final s = selectedFamilyStatus.toLowerCase();

    if (s.contains("monoparent")) {
      return false;
    }

    return s.contains("couple") ||
        s.contains("partenaire") ||
        s.contains("famille avec enfants");
  }

  bool showChildrenSection() {
    final s = selectedFamilyStatus.toLowerCase();

    return s.contains("enfant") ||
        s.contains("monoparent") ||
        s.contains("maman") ||
        s.contains("famille");
  }

  bool hasProfessionalActivity() {
    final s = selectedWorkStatus.toLowerCase();

    if (s.contains("foyer") ||
        s.contains("étudiante") ||
        s.contains("etudiante") ||
        s.contains("recherche")) {
      return false;
    }

    return true;
  }

  bool isStudentStatus() {
    final s = selectedWorkStatus.toLowerCase();

    return s.contains("étudiante") || s.contains("etudiante");
  }

  bool hasStructuredSchedule() {
    return hasProfessionalActivity() || isStudentStatus();
  }

  String scheduleTitle() {
    return isStudentStatus() ? "Horaires d'école" : "Horaires de travail";
  }

  String cleanLabel(String value) {
    return value
        .replaceAll("", "")
        .replaceAll("", "")
        .replaceAll("", "")
        .replaceAll("", "")
        .replaceAll("", "")
        .replaceAll("", "")
        .replaceAll("", "")
        .replaceAll("", "")
        .trim();
  }

  String inferFamilyStatus(UserProfile current) {
    if (current.familyStatus.trim().isNotEmpty) {
      return mapFamilyStatus(current.familyStatus);
    }

    if (current.children.isNotEmpty) {
      return familyStatuses[2];
    }

    if (current.partnerName.trim().isNotEmpty) {
      return familyStatuses[1];
    }

    return familyStatuses[0];
  }

  String inferWorkStatus(UserProfile current) {
    if (workStatuses.contains(current.workStatus)) {
      return current.workStatus;
    }

    final cleaned = cleanLabel(current.workStatus).toLowerCase();

    for (final status in workStatuses) {
      final statusClean = cleanLabel(status).toLowerCase();

      if (cleaned.isNotEmpty &&
          (cleaned.contains(statusClean) || statusClean.contains(cleaned))) {
        return status;
      }
    }

    return current.workStatus.trim().isEmpty
        ? workStatuses.first
        : current.workStatus;
  }

  String normalizeFrenchDate(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return "";
    }

    final onlyDigits = clean.replaceAll(RegExp(r'[^0-9]'), '');

    if (onlyDigits.length == 8) {
      final day = int.tryParse(onlyDigits.substring(0, 2));
      final month = int.tryParse(onlyDigits.substring(2, 4));
      final year = int.tryParse(onlyDigits.substring(4, 8));

      if (day != null && month != null && year != null) {
        final date = DateTime(year, month, day);

        if (date.day == day && date.month == month && date.year == year) {
          return formatFrenchDate(date);
        }
      }
    }

    final parts = clean
        .replaceAll('-', '/')
        .replaceAll('.', '/')
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList();

    if (parts.length == 3) {
      final day = int.tryParse(parts[0].trim());
      final month = int.tryParse(parts[1].trim());
      final year = int.tryParse(parts[2].trim());

      if (day != null && month != null && year != null) {
        final date = DateTime(year, month, day);

        if (date.day == day && date.month == month && date.year == year) {
          return formatFrenchDate(date);
        }
      }
    }

    return clean;
  }

  DateTime? parseFrenchDate(String value) {
    try {
      final normalized = normalizeFrenchDate(value);
      final parts = normalized.split("/");

      if (parts.length != 3) {
        return null;
      }

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String formatFrenchDate(DateTime date) {
    final d = date.day.toString().padLeft(2, "0");
    final m = date.month.toString().padLeft(2, "0");
    final y = date.year.toString();

    return "$d/$m/$y";
  }

  String calculateAgeFromBirthDate(String birthDateText) {
    final birthDate = parseFrenchDate(birthDateText);

    if (birthDate == null) {
      return "";
    }

    final today = DateTime.now();

    var age = today.year - birthDate.year;

    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }

    return age.toString();
  }

  String displayAge() {
    final age = calculateAgeFromBirthDate(birthDateController.text.trim());

    if (age.isEmpty) {
      return "À compléter";
    }

    return "$age ans";
  }

  String childrenNames() {
    if (children.isEmpty) {
      return "À compléter";
    }

    final names = children
        .map((child) => child.firstName)
        .where((name) => name.trim().isNotEmpty)
        .join(", ");

    return names.isEmpty ? "À compléter" : names;
  }

  String initials(String value) {
    final name = value.trim();

    if (name.isEmpty) {
      return "Z";
    }

    return name.characters.first.toUpperCase();
  }

  String timeRangeLabel(TimeRangeModel range) {
    final label = range.label.trim();

    final time = range.startTime.isEmpty && range.endTime.isEmpty
        ? ""
        : "${range.startTime} - ${range.endTime}";

    final travel = range.travelMinutes.trim().isEmpty
        ? ""
        : " • trajet ${range.travelMinutes} min";

    if (label.isNotEmpty && time.isNotEmpty) {
      return "$label • $time$travel";
    }

    if (time.isNotEmpty) {
      return "$time$travel";
    }

    return label.isEmpty ? "Plage horaire" : label;
  }

  String activitySummary(ActivityModel activity) {
    final days = activity.days.isEmpty ? "" : activity.days.join(", ");
    final firstRange = activity.timeRanges.isEmpty
        ? ""
        : timeRangeLabel(activity.timeRanges.first);

    if (days.isEmpty && firstRange.isEmpty) {
      return "Aucun détail";
    }

    if (days.isNotEmpty && firstRange.isNotEmpty) {
      return "$days • $firstRange";
    }

    return days.isNotEmpty ? days : firstRange;
  }

  static const String schoolDaysMarker = "__DAYS__:";

  List<String> schoolDaysFromRange(TimeRangeModel range) {
    final notes = range.notes.trim();

    if (!notes.contains(schoolDaysMarker)) {
      return [];
    }

    final markerIndex = notes.indexOf(schoolDaysMarker);
    final afterMarker = notes.substring(markerIndex + schoolDaysMarker.length);
    final endIndex = afterMarker.indexOf("__");
    final encoded =
        endIndex == -1 ? afterMarker : afterMarker.substring(0, endIndex);

    return encoded
        .split('|')
        .where((day) => day.trim().isNotEmpty)
        .map((day) => day.trim())
        .toList();
  }

  String cleanSchoolRangeNotes(TimeRangeModel range) {
    var notes = range.notes;

    if (!notes.contains(schoolDaysMarker)) {
      return notes.trim();
    }

    final markerIndex = notes.indexOf(schoolDaysMarker);
    final before = notes.substring(0, markerIndex).trim();
    final afterMarker = notes.substring(markerIndex + schoolDaysMarker.length);
    final endIndex = afterMarker.indexOf("__");

    if (endIndex == -1) {
      return before;
    }

    final after = afterMarker.substring(endIndex + 2).trim();

    return [before, after].where((part) => part.isNotEmpty).join(" ").trim();
  }

  String encodeSchoolRangeNotes({
    required List<String> days,
    required String notes,
  }) {
    final cleanNotes = notes.trim();

    if (days.isEmpty) {
      return cleanNotes;
    }

    final marker = "$schoolDaysMarker${days.join('|')}__";

    return cleanNotes.isEmpty ? marker : "$marker $cleanNotes";
  }

  String schoolTimeRangeLabel(TimeRangeModel range) {
    final days = schoolDaysFromRange(range);
    final base =
        timeRangeLabel(range.copyWith(notes: cleanSchoolRangeNotes(range)));

    if (days.isEmpty) {
      return base;
    }

    final daysLabel = days.map((day) => day.substring(0, 3)).join(", ");

    return "$daysLabel • $base";
  }

  String workScheduleSummary() {
    if (!hasStructuredSchedule()) {
      return "Pas d'horaire";
    }

    if (workScheduleType == "Planning flexible") {
      return variableWorkDetailsController.text.trim().isEmpty
          ? "À compléter"
          : "Planning flexible";
    }

    if (selectedWorkDays.isEmpty && workTimeRanges.isEmpty) {
      return "À compléter";
    }

    if (workTimeRanges.isEmpty) {
      return "${selectedWorkDays.length} jour(s)";
    }

    return "${selectedWorkDays.length} jour(s) • ${workTimeRanges.length} plage(s)";
  }

  Future<void> pickDate(
    TextEditingController controller,
  ) async {
    final initialDate =
        parseFrenchDate(controller.text.trim()) ?? DateTime(1993);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1920),
      lastDate: DateTime(2050),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: accent,
              onPrimary: Colors.white,
              surface: bg,
              onSurface: textDark,
            ),
            dialogBackgroundColor: bg,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: accent,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      controller.text = formatFrenchDate(picked);
    });
  }

  Future<void> pickTime(
    TextEditingController controller,
  ) async {
    final parts = controller.text.split(":");

    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;

    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: hour,
        minute: minute,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: accent,
              onPrimary: Colors.white,
              surface: bg,
              onSurface: textDark,
            ),
            dialogBackgroundColor: bg,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: accent,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      controller.text = "${picked.hour.toString().padLeft(2, "0")}:"
          "${picked.minute.toString().padLeft(2, "0")}";
    });
  }

  Future<String> pickImagePath() async {
    final pickedImage = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );

    if (pickedImage == null) {
      return "";
    }

    return pickedImage.path;
  }

  Future<void> updateUserPhoto() async {
    final path = await pickImagePath();

    if (path.isEmpty) {
      return;
    }

    setState(() {
      profile = profile.copyWith(
        profilePhotoPath: path,
      );
    });

    await saveProfile(showSnack: false);
  }

  Future<void> updatePartnerPhoto() async {
    final path = await pickImagePath();

    if (path.isEmpty) {
      return;
    }

    setState(() {
      profile = profile.copyWith(
        partnerPhotoPath: path,
      );
    });

    await saveProfile(showSnack: false);
  }

  Future<void> updateChildPhoto(int index) async {
    final path = await pickImagePath();

    if (path.isEmpty) {
      return;
    }

    setState(() {
      children[index] = children[index].copyWith(
        photoPath: path,
      );
    });

    await saveProfile(showSnack: false);
  }

  Future<void> saveProfile({
    bool showSnack = true,
  }) async {
    birthDateController.text = normalizeFrenchDate(birthDateController.text);
    partnerBirthDateController.text =
        normalizeFrenchDate(partnerBirthDateController.text);
    marriageDateController.text =
        normalizeFrenchDate(marriageDateController.text);
    engagementDateController.text =
        normalizeFrenchDate(engagementDateController.text);

    final updatedProfile = UserProfile(
      firstName: firstNameController.text.trim(),
      familyStatus: selectedFamilyStatus,
      workStatus: selectedWorkStatus,
      partnerName: showPartnerField() ? partnerNameController.text.trim() : "",
      wantsNotifications: wantsNotifications,
      children: showChildrenSection() ? children : [],
      age: calculateAgeFromBirthDate(
        birthDateController.text.trim(),
      ),
      birthDate: birthDateController.text.trim(),
      profilePhotoPath: profile.profilePhotoPath,
      partnerBirthDate: partnerBirthDateController.text.trim(),
      partnerPhotoPath: profile.partnerPhotoPath,
      relationshipStatus: showPartnerField() ? relationshipStatus : "",
      marriageDate:
          showPartnerField() ? marriageDateController.text.trim() : "",
      engagementDate:
          showPartnerField() ? engagementDateController.text.trim() : "",
      workScheduleType: hasStructuredSchedule() ? workScheduleType : "",
      workDays: hasStructuredSchedule() ? selectedWorkDays : [],
      variableWorkDetails: hasStructuredSchedule()
          ? variableWorkDetailsController.text.trim()
          : "",
      workTimeRanges: hasStructuredSchedule() ? workTimeRanges : [],
      habits: personalNotesController.text.trim(),
      personalNotes: personalNotesController.text.trim(),
      allergies: allergiesController.text.trim(),
      medicalNotes: medicalNotesController.text.trim(),
      bloodType: bloodTypeController.text.trim(),
      doctorName: doctorNameController.text.trim(),
      emergencyContactName: emergencyContactNameController.text.trim(),
      emergencyContactPhone: emergencyContactPhoneController.text.trim(),
      aiTone: aiTone,
      planningStyle: planningStyle,
      notificationLevel: notificationLevel,
      mainLifePriority: mainLifePriority,
      spokenLanguage: spokenLanguage,
      country: country,
      timeZone: timeZone,
      personalGoals: personalGoalsController.text.trim(),
      businessGoals: businessGoalsController.text.trim(),
      familyGoals: familyGoalsController.text.trim(),
      vehicleInfo: vehicleInfoController.text.trim(),
      petsInfo: petsInfoController.text.trim(),
      transportInfo: transportInfoController.text.trim(),
      childcareInfo: childcareInfoController.text.trim(),
      foodPreferences: foodPreferencesController.text.trim(),
      adminNotes: adminNotesController.text.trim(),
      budgetNotes: budgetNotesController.text.trim(),
      importantPlaces: importantPlacesController.text.trim(),
      personalActivities: personalActivities,
      preferences: profile.preferences,
      goals: profile.goals,
    );

    await StorageService.saveUserProfile(updatedProfile);

    if (!mounted) {
      return;
    }

    setState(() {
      profile = updatedProfile;
    });

    if (widget.onSave != null) {
      widget.onSave!(updatedProfile);
    }

    if (showSnack) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profil sauvegardé "),
        ),
      );
    }
  }

  Future<TimeRangeModel?> showTimeRangeEditor({
    TimeRangeModel? range,
  }) async {
    final labelController = TextEditingController(text: range?.label ?? "");
    final startController = TextEditingController(text: range?.startTime ?? "");
    final endController = TextEditingController(text: range?.endTime ?? "");
    final travelController =
        TextEditingController(text: range?.travelMinutes ?? "");
    final notesController = TextEditingController(text: range?.notes ?? "");

    TimeRangeModel? result;

    await showPremiumSheet(
      title: range == null ? "Ajouter une plage" : "Modifier la plage",
      icon: Icons.schedule_outlined,
      saveLabel: "Valider",
      onSave: () async {
        result = TimeRangeModel(
          label: labelController.text.trim(),
          startTime: startController.text.trim(),
          endTime: endController.text.trim(),
          travelMinutes: travelController.text.trim(),
          notes: notesController.text.trim(),
        );

        Navigator.pop(context);
      },
      children: [
        buildTextField(
          controller: labelController,
          label: "Nom de la plage",
          hint: "Ex : matin, école, entraînement...",
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: buildTimeField(
                controller: startController,
                label: "Début",
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: buildTimeField(
                controller: endController,
                label: "Fin",
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: travelController,
          label: "Temps de trajet",
          hint: "Ex : 20",
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: notesController,
          label: "Détails",
          hint: "Optionnel",
          maxLines: 3,
        ),
      ],
    );

    return result;
  }

  Future<TimeRangeModel?> showSchoolTimeRangeEditor({
    TimeRangeModel? range,
  }) async {
    final labelController = TextEditingController(text: range?.label ?? "");
    final startController = TextEditingController(text: range?.startTime ?? "");
    final endController = TextEditingController(text: range?.endTime ?? "");
    final travelController =
        TextEditingController(text: range?.travelMinutes ?? "");
    final notesController = TextEditingController(
      text: range == null ? "" : cleanSchoolRangeNotes(range),
    );

    var selectedDays = List<String>.from(
      range == null ? <String>[] : schoolDaysFromRange(range),
    );

    TimeRangeModel? result;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title: range == null
                          ? "Ajouter un horaire école / crèche"
                          : "Modifier l'horaire école / crèche",
                      icon: Icons.school_outlined,
                    ),
                    const SizedBox(height: 18),
                    buildTextField(
                      controller: labelController,
                      label: "Nom de la plage",
                      hint: "Ex : école matin, crèche, cantine...",
                    ),
                    const SizedBox(height: 12),
                    Text("Jours", style: sectionLabelStyle()),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: weekDays.map((day) {
                        final selected = selectedDays.contains(day);

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              if (selected) {
                                selectedDays.remove(day);
                              } else {
                                selectedDays.add(day);
                              }
                            });
                          },
                          child: buildChoiceChip(
                            label: day.substring(0, 3),
                            selected: selected,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: buildTimeField(
                            controller: startController,
                            label: "Début",
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: buildTimeField(
                            controller: endController,
                            label: "Fin",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: travelController,
                      label: "Temps de trajet",
                      hint: "Ex : 20",
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: notesController,
                      label: "Détails",
                      hint: "Optionnel",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      saveLabel: "Valider",
                      onSave: () async {
                        result = TimeRangeModel(
                          label: labelController.text.trim(),
                          startTime: startController.text.trim(),
                          endTime: endController.text.trim(),
                          travelMinutes: travelController.text.trim(),
                          notes: encodeSchoolRangeNotes(
                            days: selectedDays,
                            notes: notesController.text.trim(),
                          ),
                        );

                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  Future<ActivityModel?> showActivityEditor({
    ActivityModel? activity,
  }) async {
    final titleController = TextEditingController(text: activity?.title ?? "");
    final locationController =
        TextEditingController(text: activity?.location ?? "");
    final travelController =
        TextEditingController(text: activity?.travelMinutes ?? "");
    final notesController = TextEditingController(text: activity?.notes ?? "");

    var selectedDays = List<String>.from(activity?.days ?? []);
    var ranges = List<TimeRangeModel>.from(activity?.timeRanges ?? []);

    ActivityModel? result;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title: activity == null
                          ? "Ajouter une activité"
                          : "Modifier l'activité",
                      icon: Icons.sports_soccer_outlined,
                    ),
                    const SizedBox(height: 18),
                    buildTextField(
                      controller: titleController,
                      label: "Nom de l'activité",
                      hint: "Ex : foot, sport, anglais...",
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: locationController,
                      label: "Lieu",
                      hint: "Optionnel",
                    ),
                    const SizedBox(height: 12),
                    Text("Jours", style: sectionLabelStyle()),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: weekDays.map((day) {
                        final selected = selectedDays.contains(day);

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              if (selected) {
                                selectedDays.remove(day);
                              } else {
                                selectedDays.add(day);
                              }
                            });
                          },
                          child: buildChoiceChip(
                            label: day.substring(0, 3),
                            selected: selected,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Horaires",
                            style: sectionLabelStyle(),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final added = await showTimeRangeEditor();

                            if (added == null) {
                              return;
                            }

                            setModalState(() {
                              ranges.add(added);
                            });
                          },
                          icon: Icon(
                            Icons.add,
                            color: accent,
                          ),
                          label: Text(
                            "Ajouter",
                            style: TextStyle(color: accent),
                          ),
                        ),
                      ],
                    ),
                    ...ranges.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;

                      return buildMiniCard(
                        title: timeRangeLabel(item),
                        subtitle: item.notes,
                        icon: Icons.schedule_outlined,
                        onTap: () async {
                          final updated =
                              await showTimeRangeEditor(range: item);

                          if (updated == null) {
                            return;
                          }

                          setModalState(() {
                            ranges[index] = updated;
                          });
                        },
                        onDelete: () {
                          setModalState(() {
                            ranges.removeAt(index);
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: travelController,
                      label: "Temps de trajet global",
                      hint: "Ex : 20",
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: notesController,
                      label: "Détails de l'activité",
                      hint: "Informations utiles",
                      maxLines: 4,
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        if (titleController.text.trim().isEmpty) {
                          return;
                        }

                        result = ActivityModel(
                          title: titleController.text.trim(),
                          location: locationController.text.trim(),
                          days: selectedDays,
                          timeRanges: ranges,
                          travelMinutes: travelController.text.trim(),
                          notes: notesController.text.trim(),
                        );

                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> showFirstNameSheet() async {
    await showPremiumSheet(
      title: "Prénom",
      icon: Icons.person_outline,
      children: [
        buildTextField(
          controller: firstNameController,
          label: "Prénom",
          hint: "Ex : Sophia",
        ),
      ],
    );
  }

  Future<void> showBirthDateSheet() async {
    await showPremiumSheet(
      title: "Date de naissance",
      icon: Icons.cake_outlined,
      children: [
        buildDateField(
          controller: birthDateController,
          label: "Date de naissance",
          hint: "JJ/MM/AAAA",
        ),
      ],
    );
  }

  Future<void> showFamilyStatusSheet() async {
    var tempStatus = selectedFamilyStatus;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title: "Situation familiale",
                      icon: Icons.favorite_border,
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: familyStatuses.map((status) {
                        final selected = tempStatus == status;

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              tempStatus = status;
                            });
                          },
                          child: buildChoiceChip(
                            label: cleanLabel(status),
                            selected: selected,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        setState(() {
                          selectedFamilyStatus = tempStatus;
                        });

                        await saveProfile();

                        if (mounted && Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> showWorkStatusSheet() async {
    var tempStatus = selectedWorkStatus;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title: "Statut professionnel",
                      icon: Icons.work_outline,
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: workStatuses.map((status) {
                        final selected = tempStatus == status;

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              tempStatus = status;
                            });
                          },
                          child: buildChoiceChip(
                            label: cleanLabel(status),
                            selected: selected,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        setState(() {
                          selectedWorkStatus = tempStatus;
                        });

                        await saveProfile();

                        if (mounted && Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> showMainInfoSheet() async {
    await showPremiumSheet(
      title: "Informations principales",
      icon: Icons.person_outline,
      children: [
        buildTextField(
          controller: firstNameController,
          label: "Prénom",
          hint: "Ex : Sophia",
        ),
        const SizedBox(height: 14),
        buildDateField(
          controller: birthDateController,
          label: "Date de naissance",
          hint: "JJ/MM/AAAA",
        ),
        const SizedBox(height: 14),
        buildDropdown(
          label: "Situation familiale",
          value: selectedFamilyStatus,
          items: familyStatuses,
          onChanged: (value) {
            setState(() {
              selectedFamilyStatus = value;
            });
          },
        ),
        const SizedBox(height: 14),
        buildDropdown(
          label: "Statut professionnel",
          value: selectedWorkStatus,
          items: workStatuses,
          onChanged: (value) {
            setState(() {
              selectedWorkStatus = value;
            });
          },
        ),
      ],
    );
  }

  Future<void> showPartnerSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title: "Conjoint",
                      icon: Icons.groups_2_outlined,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: buildSmallAvatar(
                        name: partnerNameController.text,
                        size: 72,
                        imagePath: profile.partnerPhotoPath,
                        onTap: updatePartnerPhoto,
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildTextField(
                      controller: partnerNameController,
                      label: "Prénom du conjoint",
                      hint: "Ex : Willy",
                    ),
                    const SizedBox(height: 14),
                    buildDateField(
                      controller: partnerBirthDateController,
                      label: "Date de naissance",
                      hint: "JJ/MM/AAAA",
                    ),
                    const SizedBox(height: 14),
                    buildDropdown(
                      label: "Statut du couple",
                      value: relationshipStatus,
                      items: relationshipStatuses,
                      onChanged: (value) {
                        setModalState(() {
                          relationshipStatus = value;
                        });

                        setState(() {
                          relationshipStatus = value;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    if (relationshipStatus == "Mariée")
                      buildDateField(
                        controller: marriageDateController,
                        label: "Date de mariage",
                        hint: "JJ/MM/AAAA",
                      ),
                    if (relationshipStatus == "Fiancée")
                      buildDateField(
                        controller: engagementDateController,
                        label: "Date de fiançailles",
                        hint: "JJ/MM/AAAA",
                      ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        await saveProfile();

                        if (mounted && Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> showWorkScheduleSheet() async {
    var tempDays = List<String>.from(selectedWorkDays);
    var tempRanges = List<TimeRangeModel>.from(workTimeRanges);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title: scheduleTitle(),
                      icon: Icons.access_time,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      "Type de planning",
                      style: sectionLabelStyle(),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: workScheduleTypes.map((type) {
                        final selected = workScheduleType == type;

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              workScheduleType = type;
                            });
                            setState(() {
                              workScheduleType = type;
                            });
                          },
                          child: buildChoiceChip(
                            label: type,
                            selected: selected,
                            icon: type == "Horaires réguliers"
                                ? Icons.event_available_outlined
                                : Icons.auto_awesome_motion_outlined,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    if (workScheduleType == "Horaires réguliers") ...[
                      Text(
                        "Jours travaillés",
                        style: sectionLabelStyle(),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: weekDays.map((day) {
                          final selected = tempDays.contains(day);

                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                if (selected) {
                                  tempDays.remove(day);
                                } else {
                                  tempDays.add(day);
                                }
                              });
                            },
                            child: buildChoiceChip(
                              label: day.substring(0, 3),
                              selected: selected,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Plages horaires",
                              style: sectionLabelStyle(),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final added = await showTimeRangeEditor();

                              if (added == null) {
                                return;
                              }

                              setModalState(() {
                                tempRanges.add(added);
                              });
                            },
                            icon: Icon(
                              Icons.add,
                              color: accent,
                            ),
                            label: Text(
                              "Ajouter",
                              style: TextStyle(color: accent),
                            ),
                          ),
                        ],
                      ),
                      ...tempRanges.asMap().entries.map((entry) {
                        final index = entry.key;
                        final range = entry.value;

                        return buildMiniCard(
                          title: timeRangeLabel(range),
                          subtitle: range.notes,
                          icon: Icons.schedule_outlined,
                          onTap: () async {
                            final updated = await showTimeRangeEditor(
                              range: range,
                            );

                            if (updated == null) {
                              return;
                            }

                            setModalState(() {
                              tempRanges[index] = updated;
                            });
                          },
                          onDelete: () {
                            setModalState(() {
                              tempRanges.removeAt(index);
                            });
                          },
                        );
                      }),
                    ],
                    if (workScheduleType == "Planning flexible") ...[
                      buildTextField(
                        controller: variableWorkDetailsController,
                        label: isStudentStatus()
                            ? "Détails des horaires d'école"
                            : "Détails du planning",
                        hint: isStudentStatus()
                            ? "Ex : planning de cours variable, emploi du temps qui change..."
                            : "Ex : horaires variables, planning envoyé chaque semaine...",
                        maxLines: 5,
                      ),
                    ],
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        setState(() {
                          selectedWorkDays = tempDays;
                          workTimeRanges = tempRanges;
                        });

                        await saveProfile();

                        if (mounted && Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> showPersonalActivitiesSheet() async {
    var tempActivities = List<ActivityModel>.from(personalActivities);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title: "Mes activités",
                      icon: Icons.self_improvement_outlined,
                    ),
                    const SizedBox(height: 18),
                    ...tempActivities.asMap().entries.map((entry) {
                      final index = entry.key;
                      final activity = entry.value;

                      return buildMiniCard(
                        title: activity.title,
                        subtitle: activitySummary(activity),
                        icon: Icons.local_activity_outlined,
                        onTap: () async {
                          final updated = await showActivityEditor(
                            activity: activity,
                          );

                          if (updated == null) {
                            return;
                          }

                          setModalState(() {
                            tempActivities[index] = updated;
                          });
                        },
                        onDelete: () {
                          setModalState(() {
                            tempActivities.removeAt(index);
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: premiumButtonStyle(),
                        onPressed: () async {
                          final activity = await showActivityEditor();

                          if (activity == null) {
                            return;
                          }

                          setModalState(() {
                            tempActivities.add(activity);
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text("Ajouter une activité"),
                      ),
                    ),
                    const SizedBox(height: 18),
                    buildSheetActions(
                      onSave: () async {
                        setState(() {
                          personalActivities = tempActivities;
                        });

                        await saveProfile();

                        if (mounted && Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> showPersonalNotesSheet() async {
    await showPremiumSheet(
      title: "Ce que Zelia devrait savoir",
      icon: Icons.auto_awesome_outlined,
      children: [
        buildTextField(
          controller: personalNotesController,
          label: "Parlez-nous un peu de vous",
          hint:
              "Ex : contraintes, priorités, habitudes, choses importantes à savoir...",
          maxLines: 7,
        ),
      ],
    );
  }

  Future<void> showHealthSheet() async {
    await showPremiumSheet(
      title: "Santé",
      icon: Icons.health_and_safety_outlined,
      children: [
        buildTextField(
          controller: allergiesController,
          label: "Allergies",
          hint: "Ex : pollen, médicaments, aliments...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: bloodTypeController,
          label: "Groupe sanguin",
          hint: "Optionnel",
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: doctorNameController,
          label: "Médecin / praticien",
          hint: "Nom ou contact",
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: medicalNotesController,
          label: "Notes médicales",
          hint: "Traitements, suivi, informations utiles...",
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: emergencyContactNameController,
          label: "Contact urgence",
          hint: "Nom",
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: emergencyContactPhoneController,
          label: "Téléphone urgence",
          hint: "Numéro",
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }

  Future<void> showAiPreferencesSheet() async {
    await showChoicesSheet(
      title: "Préférences IA",
      icon: Icons.psychology_alt_outlined,
      sections: [
        ChoiceSection(
          label: "Ton de Zelia",
          items: aiTones,
          selected: aiTone,
          onSelected: (value) => aiTone = value,
        ),
        ChoiceSection(
          label: "Style de planning",
          items: planningStyles,
          selected: planningStyle,
          onSelected: (value) => planningStyle = value,
        ),
        ChoiceSection(
          label: "Notifications",
          items: notificationLevels,
          selected: notificationLevel,
          onSelected: (value) => notificationLevel = value,
        ),
        ChoiceSection(
          label: "Priorité principale",
          items: priorities,
          selected: mainLifePriority,
          onSelected: (value) => mainLifePriority = value,
        ),
      ],
    );
  }

  Future<void> showChoicesSheet({
    required String title,
    required IconData icon,
    required List<ChoiceSection> sections,
  }) async {
    final tempSelections = <int, String>{};

    for (var i = 0; i < sections.length; i++) {
      tempSelections[i] = sections[i].selected;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(title: title, icon: icon),
                    const SizedBox(height: 18),
                    ...sections.asMap().entries.map((entry) {
                      final index = entry.key;
                      final section = entry.value;

                      return buildSegmentChoices(
                        label: section.label,
                        items: section.items,
                        selected: tempSelections[index] ?? "",
                        onSelected: (value) {
                          setModalState(() {
                            tempSelections[index] = value;
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                    buildSheetActions(
                      onSave: () async {
                        for (var i = 0; i < sections.length; i++) {
                          sections[i].onSelected(
                            tempSelections[i] ?? sections[i].selected,
                          );
                        }

                        setState(() {});

                        await saveProfile();

                        if (mounted && Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> showGoalsSheet() async {
    await showPremiumSheet(
      title: "Objectifs",
      icon: Icons.track_changes_outlined,
      children: [
        buildTextField(
          controller: personalGoalsController,
          label: "Objectifs personnels",
          hint: "Santé, organisation, bien-être...",
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: businessGoalsController,
          label: "Objectifs business / travail",
          hint: "Projet, revenus, carrière...",
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: familyGoalsController,
          label: "Objectifs famille",
          hint: "Vacances, école, rythme, foyer...",
          maxLines: 4,
        ),
      ],
    );
  }

  Future<void> showDailyLifeSheet() async {
    await showPremiumSheet(
      title: "Vie quotidienne",
      icon: Icons.dashboard_customize_outlined,
      children: [
        buildTextField(
          controller: vehicleInfoController,
          label: "Véhicule",
          hint: "Voiture, recharge, entretien...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: transportInfoController,
          label: "Transports",
          hint: "Bus, train, marche, trajets fréquents...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: petsInfoController,
          label: "Animaux",
          hint: "Soins, alimentation, vétérinaire...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: childcareInfoController,
          label: "Garde / aide familiale",
          hint: "Nounou, grands-parents, jours disponibles...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: foodPreferencesController,
          label: "Préférences alimentaires",
          hint: "Halal, allergies, goûts, repas famille...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: importantPlacesController,
          label: "Lieux importants",
          hint: "École, travail, sport, famille...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: adminNotesController,
          label: "Administratif",
          hint: "Documents, démarches, contraintes...",
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: budgetNotesController,
          label: "Budget / paiements",
          hint: "Factures, échéances, habitudes...",
          maxLines: 3,
        ),
      ],
    );
  }

  Future<void> showLocationSheet() async {
    final countryController = TextEditingController(text: country);
    final languageController = TextEditingController(text: spokenLanguage);
    final timeZoneController = TextEditingController(text: timeZone);

    await showPremiumSheet(
      title: "Pays & langue",
      icon: Icons.language_outlined,
      onSave: () async {
        setState(() {
          country = countryController.text.trim();
          spokenLanguage = languageController.text.trim();
          timeZone = timeZoneController.text.trim();
        });

        await saveProfile();

        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      children: [
        buildTextField(
          controller: countryController,
          label: "Pays",
          hint: "France",
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: timeZoneController,
          label: "Fuseau horaire",
          hint: "Europe/Paris",
        ),
        const SizedBox(height: 12),
        buildTextField(
          controller: languageController,
          label: "Langue principale",
          hint: "Français",
        ),
      ],
    );
  }

  Future<void> showNotificationsSettings() async {
    await showPremiumSheet(
      title: "Notifications",
      icon: Icons.notifications_none_rounded,
      children: [
        Text(
          "Les réglages détaillés seront développés dans la page notifications premium.",
          style: TextStyle(
            color: textSoft,
            fontSize: 15,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: accent,
          title: Text(
            "Notifications principales",
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            "Agenda, tâches, courses et rappels.",
            style: TextStyle(color: textSoft),
          ),
          value: wantsNotifications,
          onChanged: (value) {
            setState(() {
              wantsNotifications = value;
            });
          },
        ),
      ],
    );
  }

  Future<void> showChildrenHub() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: buildSheetTitle(
                            title: "Mes enfants",
                            icon: Icons.child_care_outlined,
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            final added = await showChildEditor();

                            if (added == null) {
                              return;
                            }

                            setModalState(() {
                              children.add(added);
                            });

                            setState(() {});

                            await saveProfile(showSnack: false);
                          },
                          icon: Icon(
                            Icons.add_circle,
                            color: accent,
                            size: 34,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (children.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Text(
                          "Aucun enfant ajouté pour le moment.",
                          style: TextStyle(
                            color: textSoft,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ...children.asMap().entries.map((entry) {
                      final index = entry.key;
                      final child = entry.value;
                      final age = calculateAgeFromBirthDate(child.birthDate);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Row(
                          children: [
                            buildSmallAvatar(
                              name: child.firstName,
                              size: 56,
                              imagePath: child.photoPath,
                              onTap: () => updateChildPhoto(index),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final updated = await showChildEditor(
                                    child: child,
                                    index: index,
                                  );

                                  if (updated == null) {
                                    return;
                                  }

                                  setModalState(() {
                                    children[index] = updated;
                                  });

                                  setState(() {});

                                  await saveProfile(showSnack: false);
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      child.firstName,
                                      style: TextStyle(
                                        color: textDark,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      [
                                        child.gender,
                                        if (child.className.isNotEmpty)
                                          child.className,
                                        if (age.isNotEmpty) "$age ans",
                                        if (child.activities.isNotEmpty)
                                          "${child.activities.length} activité(s)",
                                      ].join(" • "),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textSoft,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                setModalState(() {
                                  children.removeAt(index);
                                });

                                setState(() {});

                                await saveProfile(showSnack: false);
                              },
                              icon: Icon(
                                Icons.delete_outline,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    buildSheetActions(
                      onSave: () async {
                        await saveProfile();

                        if (mounted && Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<ChildProfile?> showChildEditor({
    ChildProfile? child,
    int? index,
  }) async {
    final firstNameController =
        TextEditingController(text: child?.firstName ?? "");
    final birthDateController =
        TextEditingController(text: child?.birthDate ?? "");
    final classController = TextEditingController(text: child?.className ?? "");
    final allergiesController =
        TextEditingController(text: child?.allergies ?? "");
    final doctorController = TextEditingController(text: child?.doctor ?? "");
    final medicalController =
        TextEditingController(text: child?.medicalNotes ?? "");
    final notesController = TextEditingController(text: child?.notes ?? "");

    var gender = child?.gender.isNotEmpty == true ? child!.gender : "Fille";

    var schoolRanges = List<TimeRangeModel>.from(child?.schoolTimeRanges ?? []);
    var activities = List<ActivityModel>.from(child?.activities ?? []);

    ChildProfile? result;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      title:
                          child == null ? "Ajouter un enfant" : "Profil enfant",
                      icon: Icons.child_care_outlined,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: buildSmallAvatar(
                        name: firstNameController.text,
                        size: 78,
                        imagePath: child?.photoPath ?? "",
                        onTap: index == null
                            ? null
                            : () => updateChildPhoto(index),
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildTextField(
                      controller: firstNameController,
                      label: "Prénom",
                      hint: "Ex : Kasim",
                    ),
                    const SizedBox(height: 12),
                    buildDateField(
                      controller: birthDateController,
                      label: "Date de naissance",
                      hint: "JJ/MM/AAAA",
                    ),
                    const SizedBox(height: 12),
                    buildDropdown(
                      label: "Genre",
                      value: gender,
                      items: const ["Fille", "Garçon"],
                      onChanged: (value) {
                        setModalState(() {
                          gender = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: classController,
                      label: "Classe",
                      hint: "Ex : moyenne section",
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Horaires école / crèche",
                            style: sectionLabelStyle(),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final added = await showSchoolTimeRangeEditor();

                            if (added == null) {
                              return;
                            }

                            setModalState(() {
                              schoolRanges.add(added);
                            });
                          },
                          icon: Icon(Icons.add, color: accent),
                          label: Text(
                            "Ajouter",
                            style: TextStyle(color: accent),
                          ),
                        ),
                      ],
                    ),
                    ...schoolRanges.asMap().entries.map((entry) {
                      final rangeIndex = entry.key;
                      final range = entry.value;

                      return buildMiniCard(
                        title: schoolTimeRangeLabel(range),
                        subtitle: cleanSchoolRangeNotes(range),
                        icon: Icons.school_outlined,
                        onTap: () async {
                          final updated =
                              await showSchoolTimeRangeEditor(range: range);

                          if (updated == null) {
                            return;
                          }

                          setModalState(() {
                            schoolRanges[rangeIndex] = updated;
                          });
                        },
                        onDelete: () {
                          setModalState(() {
                            schoolRanges.removeAt(rangeIndex);
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Activités",
                            style: sectionLabelStyle(),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final activity = await showActivityEditor();

                            if (activity == null) {
                              return;
                            }

                            setModalState(() {
                              activities.add(activity);
                            });
                          },
                          icon: Icon(Icons.add, color: accent),
                          label: Text(
                            "Ajouter",
                            style: TextStyle(color: accent),
                          ),
                        ),
                      ],
                    ),
                    ...activities.asMap().entries.map((entry) {
                      final activityIndex = entry.key;
                      final activity = entry.value;

                      return buildMiniCard(
                        title: activity.title,
                        subtitle: activitySummary(activity),
                        icon: Icons.local_activity_outlined,
                        onTap: () async {
                          final updated = await showActivityEditor(
                            activity: activity,
                          );

                          if (updated == null) {
                            return;
                          }

                          setModalState(() {
                            activities[activityIndex] = updated;
                          });
                        },
                        onDelete: () {
                          setModalState(() {
                            activities.removeAt(activityIndex);
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 18),
                    Text(
                      "Santé",
                      style: sectionLabelStyle(),
                    ),
                    const SizedBox(height: 10),
                    buildTextField(
                      controller: allergiesController,
                      label: "Allergies",
                      hint: "Optionnel",
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: doctorController,
                      label: "Médecin",
                      hint: "Optionnel",
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: medicalController,
                      label: "Notes médicales",
                      hint: "Optionnel",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    buildTextField(
                      controller: notesController,
                      label: "Ce que Zelia devrait savoir",
                      hint:
                          "Infos générales utiles pour mieux l'accompagner...",
                      maxLines: 4,
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        final name = firstNameController.text.trim();

                        if (name.isEmpty) {
                          return;
                        }

                        final birth = normalizeFrenchDate(
                          birthDateController.text.trim(),
                        );

                        result = ChildProfile(
                          firstName: name,
                          age: calculateAgeFromBirthDate(birth),
                          birthDate: birth,
                          gender: gender,
                          school: "",
                          notes: notesController.text.trim(),
                          photoPath: child?.photoPath ?? "",
                          className: classController.text.trim(),
                          allergies: allergiesController.text.trim(),
                          doctor: doctorController.text.trim(),
                          medicalNotes: medicalController.text.trim(),
                          schoolTimeRanges: schoolRanges,
                          activities: activities,
                        );

                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> showPremiumSheet({
    required String title,
    required IconData icon,
    required List<Widget> children,
    String saveLabel = "Enregistrer",
    Future<void> Function()? onSave,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: buildSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSheetHandle(),
                const SizedBox(height: 18),
                buildSheetTitle(
                  title: title,
                  icon: icon,
                ),
                const SizedBox(height: 18),
                ...children,
                const SizedBox(height: 22),
                buildSheetActions(
                  saveLabel: saveLabel,
                  onSave: onSave,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildSheetContainer({
    required Widget child,
  }) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(
        22,
        18,
        22,
        22,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: child,
      ),
    );
  }

  Widget buildSheetHandle() {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        decoration: BoxDecoration(
          color: textSoft.withOpacity(0.25),
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }

  Widget buildSheetTitle({
    required String title,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            icon,
            color: accent,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: textDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildSheetActions({
    String saveLabel = "Enregistrer",
    Future<void> Function()? onSave,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Annuler",
              style: TextStyle(
                color: textSoft,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            style: premiumButtonStyle(),
            onPressed: () async {
              if (onSave != null) {
                await onSave();
                return;
              }

              await saveProfile();

              if (mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            child: Text(saveLabel),
          ),
        ),
      ],
    );
  }

  ButtonStyle premiumButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        vertical: 16,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w900,
      ),
    );
  }

  TextStyle sectionLabelStyle() {
    return TextStyle(
      color: textDark,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    );
  }

  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withOpacity(0.10),
        ),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: TextStyle(
            color: textSoft,
          ),
          hintText: hint,
        ),
      ),
    );
  }

  Widget buildDateField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withOpacity(0.10),
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9/\-.]')),
        ],
        onChanged: (value) {
          final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

          if (digits.length == 8) {
            final formatted = normalizeFrenchDate(value);

            if (formatted != value) {
              controller.value = TextEditingValue(
                text: formatted,
                selection: TextSelection.collapsed(offset: formatted.length),
              );
            }
          }
        },
        onEditingComplete: () {
          controller.text = normalizeFrenchDate(controller.text);
          FocusScope.of(context).unfocus();
        },
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: TextStyle(
            color: textSoft,
          ),
          hintText: hint,
          suffixIcon: IconButton(
            onPressed: () => pickDate(controller),
            icon: Icon(
              Icons.calendar_month_outlined,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTimeField({
    required TextEditingController controller,
    required String label,
  }) {
    return GestureDetector(
      onTap: () => pickTime(controller),
      child: AbsorbPointer(
        child: buildTextField(
          controller: controller,
          label: label,
          hint: "HH:mm",
          keyboardType: TextInputType.datetime,
        ),
      ),
    );
  }

  Widget buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withOpacity(0.10),
        ),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        value: items.contains(value) ? value : items.first,
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: TextStyle(
            color: textSoft,
          ),
        ),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(item),
          );
        }).toList(),
        onChanged: (newValue) {
          if (newValue == null) {
            return;
          }

          onChanged(newValue);
        },
      ),
    );
  }

  Widget buildChoiceChip({
    required String label,
    required bool selected,
    IconData? icon,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color:
            selected ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? accent : accent.withOpacity(0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: selected ? accent : textSoft,
              size: 17,
            ),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
              color: selected ? accent : textDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSegmentChoices({
    required String label,
    required List<String> items,
    required String selected,
    required Function(String) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: sectionLabelStyle(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            return GestureDetector(
              onTap: () => onSelected(item),
              child: buildChoiceChip(
                label: item,
                selected: selected == item,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget buildMiniCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(22),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: accent),
        title: Text(
          title,
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: subtitle.trim().isEmpty
            ? null
            : Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textSoft),
              ),
        trailing: onDelete == null
            ? Icon(Icons.chevron_right, color: textSoft)
            : IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  color: textSoft,
                ),
              ),
      ),
    );
  }

  Widget buildSmallAvatar({
    required String name,
    required double size,
    String imagePath = "",
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
            ),
            child: ClipOval(
              child: imagePath.isNotEmpty && File(imagePath).existsSync()
                  ? Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: Text(
                        initials(name),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: size * 0.34,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.33,
              height: size * 0.33,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_camera_outlined,
                color: accent,
                size: size * 0.19,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 6),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Center(
              child: Text(
                "Mon profil",
                style: TextStyle(
                  color: textDark,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.82),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: showMainInfoSheet,
              icon: Icon(
                Icons.settings_outlined,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAvatar() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 28),
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 142,
              height: 142,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.78),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipOval(
                child: profile.profilePhotoPath.isNotEmpty &&
                        File(profile.profilePhotoPath).existsSync()
                    ? Image.file(
                        File(profile.profilePhotoPath),
                        fit: BoxFit.cover,
                      )
                    : CircleAvatar(
                        backgroundColor: accent.withOpacity(0.17),
                        child: Text(
                          initials(firstNameController.text),
                          style: TextStyle(
                            color: accent,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              right: -6,
              bottom: 8,
              child: GestureDetector(
                onTap: updateUserPhoto,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.photo_camera_outlined,
                    color: accent,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildInfoCard() {
    return buildPremiumCard(
      children: [
        buildProfileRow(
          icon: Icons.person_outline,
          label: "Prénom",
          value: firstNameController.text.trim().isEmpty
              ? "À compléter"
              : firstNameController.text.trim(),
          onTap: showFirstNameSheet,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.cake_outlined,
          label: "Âge",
          value: displayAge(),
          onTap: showBirthDateSheet,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.favorite_border,
          label: "Situation familiale",
          value: cleanLabel(selectedFamilyStatus),
          onTap: showFamilyStatusSheet,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.work_outline,
          label: "Statut professionnel",
          value: cleanLabel(selectedWorkStatus),
          onTap: showWorkStatusSheet,
        ),
        if (showPartnerField()) ...[
          buildDivider(),
          buildProfileRow(
            icon: Icons.groups_2_outlined,
            label: "Conjoint",
            value: partnerNameController.text.trim().isEmpty
                ? "À compléter"
                : partnerNameController.text.trim(),
            onTap: showPartnerSheet,
            showChevron: true,
            leadingAvatar: buildSmallAvatar(
              name: partnerNameController.text,
              size: 38,
              imagePath: profile.partnerPhotoPath,
              onTap: showPartnerSheet,
            ),
          ),
        ],
        if (showChildrenSection()) ...[
          buildDivider(),
          buildProfileRow(
            icon: Icons.child_care_outlined,
            label: "Enfants",
            value: childrenNames(),
            onTap: showChildrenHub,
            showChevron: true,
            leadingAvatar: children.isEmpty ? null : buildChildrenMiniAvatars(),
          ),
        ],
      ],
    );
  }

  Widget buildPremiumSectionsCard() {
    return buildPremiumCard(
      children: [
        if (hasStructuredSchedule()) ...[
          buildProfileRow(
            icon: Icons.access_time,
            label: scheduleTitle(),
            value: workScheduleSummary(),
            iconColor: textSoft,
            onTap: showWorkScheduleSheet,
            showChevron: true,
          ),
          buildDivider(),
        ],
        buildProfileRow(
          icon: Icons.self_improvement_outlined,
          label: "Mes activités",
          value: personalActivities.isEmpty
              ? "À compléter"
              : "${personalActivities.length} activité(s)",
          iconColor: textSoft,
          onTap: showPersonalActivitiesSheet,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.auto_awesome_outlined,
          label: "Ce que Zelia devrait savoir",
          value: personalNotesController.text.trim().isEmpty
              ? "À compléter"
              : "Voir",
          iconColor: textSoft,
          onTap: showPersonalNotesSheet,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.health_and_safety_outlined,
          label: "Santé",
          value: allergiesController.text.trim().isEmpty &&
                  medicalNotesController.text.trim().isEmpty
              ? "À compléter"
              : "Voir",
          iconColor: textSoft,
          onTap: showHealthSheet,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.psychology_alt_outlined,
          label: "Préférences IA",
          value: aiTone,
          iconColor: textSoft,
          onTap: showAiPreferencesSheet,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.dashboard_customize_outlined,
          label: "Vie quotidienne",
          value: vehicleInfoController.text.trim().isEmpty &&
                  petsInfoController.text.trim().isEmpty &&
                  transportInfoController.text.trim().isEmpty
              ? "À compléter"
              : "Voir",
          iconColor: textSoft,
          onTap: showDailyLifeSheet,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.language_outlined,
          label: "Pays & langue",
          value: "$country • $spokenLanguage",
          iconColor: textSoft,
          onTap: showLocationSheet,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.notifications_none_rounded,
          label: "Notifications",
          value: wantsNotifications ? "Actives" : "Désactivées",
          iconColor: textSoft,
          onTap: showNotificationsSettings,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.auto_awesome,
          label: "Mémoire Zelia",
          value: "Active",
          iconColor: textSoft,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Mémoire IA déjà reliée au chat ",
                ),
              ),
            );
          },
          showChevron: true,
        ),
      ],
    );
  }

  Widget buildChildrenMiniAvatars() {
    final visibleChildren = children.take(3).toList();

    return SizedBox(
      width: 76,
      height: 38,
      child: Stack(
        children: visibleChildren.asMap().entries.map((entry) {
          final index = entry.key;
          final child = entry.value;

          return Positioned(
            left: index * 24,
            child: buildSmallAvatar(
              name: child.firstName,
              size: 38,
              imagePath: child.photoPath,
              onTap: showChildrenHub,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget buildPremiumCard({
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 26),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: accent.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget buildProfileRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    Color? iconColor,
    bool showChevron = false,
    Widget? leadingAvatar,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? accent,
              size: 24,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (leadingAvatar != null) ...[
              leadingAvatar,
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: value == "À compléter"
                      ? textSoft.withOpacity(0.75)
                      : textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right,
                color: textSoft,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildDivider() {
    return Divider(
      height: 1,
      color: accent.withOpacity(0.08),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              buildHeader(),
              buildAvatar(),
              buildInfoCard(),
              buildPremiumSectionsCard(),
              const SizedBox(height: 110),
            ],
          ),
        ),
      ),
    );
  }
}

class ChoiceSection {
  final String label;
  final List<String> items;
  final String selected;
  final Function(String) onSelected;

  ChoiceSection({
    required this.label,
    required this.items,
    required this.selected,
    required this.onSelected,
  });
}
