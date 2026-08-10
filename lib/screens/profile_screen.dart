import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:country_picker/country_picker.dart';

import '../models/user_profile.dart';
import '../models/human/human_model.dart';
import '../services/school_schedule_metadata_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../services/app_diagnostics.dart';
import '../services/app_error_classifier.dart';
import '../services/notification_service.dart';
import '../services/human/human_model_edit_service.dart';
import 'auth/auth_screen.dart';
import 'human_profile_screen.dart';
import 'memory_library_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_data_screen.dart';
import 'help_information_screen.dart';

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
  late TextEditingController partnerNotesController;
  late TextEditingController partnerWorkScheduleController;
  late TextEditingController marriageDateController;
  late TextEditingController engagementDateController;

  late TextEditingController variableWorkDetailsController;
  late TextEditingController workTravelMinutesController;
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
  late TextEditingController homeAddressController;
  late TextEditingController workAddressController;

  late String selectedFamilyStatus;
  late String selectedWorkStatus;
  late bool wantsNotifications;
  late List<ChildProfile> children;
  late List<TimeRangeModel> workTimeRanges;
  late List<ActivityModel> personalActivities;
  List<_AdditionalProfile> additionalProfiles = const [];

  String relationshipStatus = "";
  String workScheduleType = "";
  List<String> selectedWorkDays = [];

  String aiTone = "";
  String planningStyle = "";
  String notificationLevel = "";
  String mainLifePriority = "";
  String spokenLanguage = "";
  String country = "";
  String city = "";
  String currentCountry = "";
  String timeZone = "";

  final Color bg = const Color(0xFFF8EFEA);
  final Color accent = const Color(0xFFE95D5D);
  final Color textDark = const Color(0xFF11181C);
  final Color textSoft = const Color(0xFF8B6F67);

  final List<String> familyStatuses = [
    "Je vis seule",
    "Je vis en couple",
    "Nous sommes une famille avec enfants ",
    "Nous sommes une famille monoparentale",
    "Autre situation",
  ];

  final List<String> workStatuses = [
    "Je ne travaille pas actuellement",
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
    partnerNotesController = TextEditingController(text: profile.partnerNotes);
    partnerWorkScheduleController =
        TextEditingController(text: profile.partnerWorkSchedule);
    marriageDateController =
        TextEditingController(text: normalizeFrenchDate(profile.marriageDate));
    engagementDateController = TextEditingController(
        text: normalizeFrenchDate(profile.engagementDate));

    variableWorkDetailsController =
        TextEditingController(text: profile.variableWorkDetails);
    workTravelMinutesController =
        TextEditingController(text: profile.workTravelMinutes);
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
    homeAddressController = TextEditingController(text: profile.homeAddress);
    workAddressController = TextEditingController(text: profile.workAddress);

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
    city = profile.city;
    currentCountry = profile.currentCountry;
    timeZone = profile.timeZone.isNotEmpty ? profile.timeZone : "Europe/Paris";
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAdditionalProfiles();
      _refreshTimeZoneFromPhone();
    });
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profile != widget.profile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          syncProfile(widget.profile);
        });
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
    partnerNotesController.text = newProfile.partnerNotes;
    partnerWorkScheduleController.text = newProfile.partnerWorkSchedule;
    marriageDateController.text = normalizeFrenchDate(newProfile.marriageDate);
    engagementDateController.text =
        normalizeFrenchDate(newProfile.engagementDate);
    variableWorkDetailsController.text = newProfile.variableWorkDetails;
    workTravelMinutesController.text = newProfile.workTravelMinutes;
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
    homeAddressController.text = newProfile.homeAddress;
    workAddressController.text = newProfile.workAddress;

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
    city = newProfile.city;
    currentCountry = newProfile.currentCountry;
    timeZone =
        newProfile.timeZone.isNotEmpty ? newProfile.timeZone : "Europe/Paris";
  }

  @override
  void dispose() {
    firstNameController.dispose();
    birthDateController.dispose();
    partnerNameController.dispose();
    partnerBirthDateController.dispose();
    partnerNotesController.dispose();
    partnerWorkScheduleController.dispose();
    marriageDateController.dispose();
    engagementDateController.dispose();
    variableWorkDetailsController.dispose();
    workTravelMinutesController.dispose();
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
    homeAddressController.dispose();
    workAddressController.dispose();
    super.dispose();
  }

  String mapFamilyStatus(String status) {
    final s = status.toLowerCase();

    if (s.contains("monoparent") || s.contains("maman")) {
      return familyStatuses[3];
    }

    if (s.contains("couple") || s.contains("partenaire")) {
      return familyStatuses[1];
    }

    if (s.contains("enfant") || s.contains("famille")) {
      return familyStatuses[2];
    }

    if (s.contains("compli") || s.contains("autre")) {
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

  bool isLivingAlone() =>
      selectedFamilyStatus.toLowerCase().contains('vis seule');

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
        s.contains("ne travaille pas") ||
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

    if (cleaned.contains('maman au foyer') ||
        cleaned.contains('père au foyer') ||
        cleaned.contains('pere au foyer')) {
      return workStatuses.first;
    }

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
    final days = schoolDaysFromRange(range);
    final daysLabel =
        days.isEmpty ? '' : days.map((day) => day.substring(0, 3)).join(', ');
    final label = range.label.trim();

    final time = range.startTime.isEmpty && range.endTime.isEmpty
        ? ""
        : "${range.startTime} - ${range.endTime}";

    final travel = range.travelMinutes.trim().isEmpty
        ? ""
        : " • trajet ${range.travelMinutes} min";

    final base = label.isNotEmpty && time.isNotEmpty
        ? "$label • $time$travel"
        : time.isNotEmpty
            ? "$time$travel"
            : label.isEmpty
                ? "Plage horaire"
                : label;
    return daysLabel.isEmpty ? base : '$daysLabel • $base';
  }

  String activitySummary(ActivityModel activity) {
    final firstRange = activity.timeRanges.isEmpty
        ? ""
        : timeRangeLabel(activity.timeRanges.first);
    if (firstRange.isNotEmpty) return firstRange;
    return activity.days.isEmpty ? 'Aucun horaire' : activity.days.join(', ');
  }

  List<String> schoolDaysFromRange(TimeRangeModel range) {
    return SchoolScheduleMetadataService.daysFromRange(range);
  }

  String cleanSchoolRangeNotes(TimeRangeModel range) {
    return SchoolScheduleMetadataService.cleanNotes(range);
  }

  String encodeSchoolRangeNotes({
    required List<String> days,
    required String notes,
  }) {
    return SchoolScheduleMetadataService.encodeNotes(
      days: days,
      notes: notes,
    );
  }

  String schoolTimeRangeLabel(TimeRangeModel range) {
    return timeRangeLabel(range);
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
            dialogTheme: DialogThemeData(backgroundColor: bg),
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
            dialogTheme: DialogThemeData(backgroundColor: bg),
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
      humanPersonId: profile.humanPersonId,
      partnerHumanPersonId: profile.partnerHumanPersonId,
      legacyExtensions: profile.legacyExtensions,
      firstName: firstNameController.text.trim(),
      familyStatus: selectedFamilyStatus,
      workStatus: selectedWorkStatus,
      partnerName: partnerNameController.text.trim(),
      wantsNotifications: wantsNotifications,
      children: children,
      age: calculateAgeFromBirthDate(
        birthDateController.text.trim(),
      ),
      birthDate: birthDateController.text.trim(),
      profilePhotoPath: profile.profilePhotoPath,
      partnerBirthDate: partnerBirthDateController.text.trim(),
      partnerPhotoPath: profile.partnerPhotoPath,
      partnerNotes: partnerNotesController.text.trim(),
      partnerWorkSchedule: partnerWorkScheduleController.text.trim(),
      relationshipStatus: relationshipStatus,
      marriageDate: marriageDateController.text.trim(),
      engagementDate: engagementDateController.text.trim(),
      workScheduleType: hasStructuredSchedule() ? workScheduleType : "",
      workDays: hasStructuredSchedule() ? selectedWorkDays : [],
      variableWorkDetails: hasStructuredSchedule()
          ? variableWorkDetailsController.text.trim()
          : "",
      workTimeRanges: hasStructuredSchedule() ? workTimeRanges : [],
      workTravelMinutes: workTravelMinutesController.text.trim(),
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
      city: city,
      currentCountry: currentCountry,
      homeAddress: homeAddressController.text.trim(),
      workAddress: workAddressController.text.trim(),
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

    final persistedProfile =
        await StorageService.saveUserProfile(updatedProfile);
    final accountScopeId = AuthService.currentUserId;
    HumanModelEditResult? humanResult;
    if (accountScopeId != null && accountScopeId.trim().isNotEmpty) {
      try {
        final editor = await HumanModelEditService.createProduction();
        humanResult = await editor.commitLegacyProfile(
          accountScopeId: accountScopeId,
          profile: persistedProfile,
        );
      } on Object catch (error) {
        final descriptor = AppErrorClassifier.classify(
          error,
          boundary: AppErrorBoundaryKind.localStorage,
        );
        AppDiagnostics.record(
          component: 'human_model_storage',
          domain: 'human',
          operation: 'save',
          step: 'profile_edit',
          code: descriptor.code,
          severity: descriptor.severity,
          retryStrategy: descriptor.retryStrategy,
          sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
        );
        humanResult = const HumanModelEditResult(
          status: HumanModelEditStatus.storageFailure,
        );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      profile = persistedProfile;
    });

    if (widget.onSave != null) {
      widget.onSave!(persistedProfile);
    }

    if (showSnack) {
      final message = switch (humanResult?.status) {
        null || HumanModelEditStatus.success => 'Profil sauvegardé',
        HumanModelEditStatus.pendingSync ||
        HumanModelEditStatus.networkUnavailable =>
          'Profil sauvegardé sur cet appareil. La synchronisation reprendra dès que possible.',
        HumanModelEditStatus.revisionConflict =>
          'Le profil a changé ailleurs. Recharge-le avant de réessayer.',
        _ => 'La sauvegarde du profil n’a pas pu être terminée.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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
    var selectedDays = List<String>.from(
      range == null ? const <String>[] : schoolDaysFromRange(range),
    );

    TimeRangeModel? result;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: buildSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSheetHandle(),
                const SizedBox(height: 18),
                buildSheetTitle(
                  title: range == null
                      ? 'Ajouter un jour et un horaire'
                      : 'Modifier le jour et l’horaire',
                  icon: Icons.schedule_outlined,
                ),
                const SizedBox(height: 18),
                buildTextField(
                  controller: labelController,
                  label: 'Nom',
                  hint: 'Ex : matin, école, entraînement...',
                ),
                const SizedBox(height: 14),
                Text('Jour(s)', style: sectionLabelStyle()),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: weekDays.map((day) {
                    final selected = selectedDays.contains(day);
                    return GestureDetector(
                      onTap: () => setModalState(() {
                        if (selected) {
                          selectedDays.remove(day);
                        } else {
                          selectedDays.add(day);
                        }
                      }),
                      child: buildChoiceChip(
                        label: day.substring(0, 3),
                        selected: selected,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: buildTimeField(
                        controller: startController,
                        label: 'Début',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: buildTimeField(
                        controller: endController,
                        label: 'Fin',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                buildSheetActions(
                  saveLabel: 'Valider',
                  onSave: () async {
                    if (selectedDays.isEmpty ||
                        startController.text.trim().isEmpty ||
                        endController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Choisis au moins un jour, une heure de début et une heure de fin.',
                          ),
                        ),
                      );
                      return;
                    }
                    result = TimeRangeModel(
                      label: labelController.text.trim(),
                      startTime: startController.text.trim(),
                      endTime: endController.text.trim(),
                      travelMinutes: range?.travelMinutes ?? '',
                      notes: encodeSchoolRangeNotes(
                        days: selectedDays,
                        notes:
                            range == null ? '' : cleanSchoolRangeNotes(range),
                      ),
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return result;
  }

  Future<TimeRangeModel?> showSchoolTimeRangeEditor({
    TimeRangeModel? range,
  }) async {
    final labelController = TextEditingController(text: range?.label ?? "");
    final startController = TextEditingController(text: range?.startTime ?? "");
    final endController = TextEditingController(text: range?.endTime ?? "");
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
                    const SizedBox(height: 22),
                    buildSheetActions(
                      saveLabel: "Valider",
                      onSave: () async {
                        if (selectedDays.isEmpty ||
                            startController.text.trim().isEmpty ||
                            endController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Choisis au moins un jour, une heure de début et une heure de fin.',
                              ),
                            ),
                          );
                          return;
                        }
                        result = TimeRangeModel(
                          label: labelController.text.trim(),
                          startTime: startController.text.trim(),
                          endTime: endController.text.trim(),
                          travelMinutes: range?.travelMinutes ?? '',
                          notes: encodeSchoolRangeNotes(
                            days: selectedDays,
                            notes: range == null
                                ? ''
                                : cleanSchoolRangeNotes(range),
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

  Future<void> _deleteChildProfile(int index, ChildProfile child) async {
    final personId = child.humanPersonId.trim();
    if (personId.isNotEmpty) {
      final scope = AuthService.currentUserId;
      if (scope != null && scope.trim().isNotEmpty) {
        final service = await HumanModelEditService.createProduction();
        await service.commit(
          accountScopeId: scope,
          transform: (model) => model.copyWith(
            persons: model.persons
                .map(
                  (person) => person.id == personId
                      ? person.copyWith(status: HumanPersonStatus.historical)
                      : person,
                )
                .toList(),
            relationships: model.relationships
                .map(
                  (relation) => relation.targetPersonId == personId
                      ? relation.copyWith(status: HumanRecordStatus.historical)
                      : relation,
                )
                .toList(),
          ),
        );
      }
    }
    if (!mounted || index < 0 || index >= children.length) return;
    setState(() => children.removeAt(index));
    await saveProfile(showSnack: false);
  }

  Future<ActivityModel?> showActivityEditor({
    ActivityModel? activity,
  }) async {
    final titleController = TextEditingController(text: activity?.title ?? "");
    final locationController =
        TextEditingController(text: activity?.location ?? "");
    final travelController =
        TextEditingController(text: activity?.travelMinutes ?? "");

    var ranges = List<TimeRangeModel>.from(activity?.timeRanges ?? []).map(
      (range) {
        if (schoolDaysFromRange(range).isNotEmpty ||
            (activity?.days.isEmpty ?? true)) {
          return range;
        }
        return range.copyWith(
          notes: encodeSchoolRangeNotes(
            days: activity!.days,
            notes: cleanSchoolRangeNotes(range),
          ),
        );
      },
    ).toList();

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
                      label: "Lieu ou adresse",
                      hint: "Ex : nom du club, rue et ville",
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
                        subtitle: cleanSchoolRangeNotes(item),
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
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        if (titleController.text.trim().isEmpty) {
                          return;
                        }

                        result = ActivityModel(
                          title: titleController.text.trim(),
                          location: locationController.text.trim(),
                          days: {
                            for (final range in ranges)
                              ...schoolDaysFromRange(range),
                          }.toList(),
                          timeRanges: ranges,
                          travelMinutes: travelController.text.trim(),
                          notes: activity?.notes ?? "",
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
          hint: "Ex : Prénom",
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

                        if (!context.mounted) return;

                        if (Navigator.canPop(context)) {
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

                        if (!context.mounted) return;

                        if (Navigator.canPop(context)) {
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
          hint: "Ex : Prénom",
        ),
        const SizedBox(height: 14),
        buildDateField(
          controller: birthDateController,
          label: "Date de naissance",
          hint: "JJ/MM/AAAA",
        ),
        const SizedBox(height: 14),
        buildSelectionField(
          label: "Situation familiale",
          value: selectedFamilyStatus,
          onTap: showFamilyStatusSheet,
        ),
        const SizedBox(height: 14),
        buildSelectionField(
          label: "Statut professionnel",
          value: selectedWorkStatus,
          onTap: showWorkStatusSheet,
        ),
      ],
    );
  }

  Future<void> showPartnerSheet() async {
    await _showAdultProfileSheet(
      title: 'Conjoint',
      nameController: partnerNameController,
      birthController: partnerBirthDateController,
      workController: partnerWorkScheduleController,
      notesController: partnerNotesController,
      engagementController: engagementDateController,
      marriageController: marriageDateController,
      initialStatus: relationshipStatus,
      initialPhotoPath: profile.partnerPhotoPath,
      showCoupleStatus: true,
      onSave: (status, photoPath) async {
        setState(() {
          relationshipStatus = status;
          profile = profile.copyWith(partnerPhotoPath: photoPath);
        });
        await saveProfile();
      },
      onDelete: _deleteLegacyPartner,
    );
  }

  Future<void> _showAdultProfileSheet({
    required String title,
    required TextEditingController nameController,
    required TextEditingController birthController,
    required TextEditingController workController,
    required TextEditingController notesController,
    required TextEditingController engagementController,
    required TextEditingController marriageController,
    required String initialStatus,
    required String initialPhotoPath,
    required bool showCoupleStatus,
    required Future<void> Function(String status, String photoPath) onSave,
    required Future<void> Function() onDelete,
  }) async {
    var status = initialStatus.isEmpty ? 'En couple' : initialStatus;
    var photoPath = initialPhotoPath;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

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
                      icon: Icons.groups_2_outlined,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: buildSmallAvatar(
                        name: nameController.text,
                        size: 72,
                        imagePath: photoPath,
                        onTap: () async {
                          final selected = await pickImagePath();
                          if (selected.isNotEmpty) {
                            setModalState(() => photoPath = selected);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildTextField(
                      controller: nameController,
                      label: 'Prénom',
                      hint: "Ex : Willy",
                    ),
                    const SizedBox(height: 14),
                    buildDateField(
                      controller: birthController,
                      label: "Date de naissance",
                      hint: "JJ/MM/AAAA",
                    ),
                    if (showCoupleStatus) ...[
                      const SizedBox(height: 14),
                      buildDropdown(
                        label: 'Statut du couple',
                        value: status,
                        items: relationshipStatuses,
                        onChanged: (value) {
                          setModalState(() => status = value);
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (showCoupleStatus && status == "Mariée")
                      buildDateField(
                        controller: marriageController,
                        label: "Date de mariage",
                        hint: "JJ/MM/AAAA",
                      ),
                    if (showCoupleStatus && status == "Fiancée")
                      buildDateField(
                        controller: engagementController,
                        label: "Date de fiançailles",
                        hint: "JJ/MM/AAAA",
                      ),
                    const SizedBox(height: 14),
                    buildTextField(
                      controller: workController,
                      label: "Horaires ou planning de travail",
                      hint: "Ex : du lundi au vendredi, 8 h à 17 h...",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    buildTextField(
                      controller: notesController,
                      label: "Ce que Zelia doit savoir",
                      hint:
                          "Disponibilités, garde des enfants, habitudes ou informations utiles...",
                      maxLines: 5,
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        await onSave(status, photoPath);
                        if (sheetContext.mounted &&
                            Navigator.canPop(sheetContext)) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          final confirmed = await _confirmProfileDeletion(
                            message:
                                'Cette personne ne sera plus affichée dans ton profil.',
                          );
                          if (!confirmed) return;
                          await onDelete();
                          if (sheetContext.mounted &&
                              Navigator.canPop(sheetContext)) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Supprimer ce profil'),
                      ),
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

  Future<void> _deleteLegacyPartner() async {
    final personId = profile.partnerHumanPersonId.trim();
    if (personId.isNotEmpty) {
      final service = await HumanModelEditService.createProduction();
      final scope = AuthService.currentUserId;
      if (scope != null && scope.trim().isNotEmpty) {
        await service.commit(
          accountScopeId: scope,
          transform: (model) => model.copyWith(
            persons: model.persons
                .map(
                  (person) => person.id == personId
                      ? person.copyWith(status: HumanPersonStatus.historical)
                      : person,
                )
                .toList(),
            relationships: model.relationships
                .map(
                  (relation) => relation.targetPersonId == personId
                      ? relation.copyWith(status: HumanRecordStatus.historical)
                      : relation,
                )
                .toList(),
          ),
        );
      }
    }
    setState(() {
      partnerNameController.clear();
      partnerBirthDateController.clear();
      partnerWorkScheduleController.clear();
      partnerNotesController.clear();
      engagementDateController.clear();
      marriageDateController.clear();
      relationshipStatus = relationshipStatuses.first;
      profile = profile.copyWith(
        partnerHumanPersonId: '',
        partnerPhotoPath: '',
      );
    });
    await saveProfile(showSnack: false);
  }

  Future<void> showWorkScheduleSheet() async {
    var tempDays = List<String>.from(selectedWorkDays);
    var tempRanges = List<TimeRangeModel>.from(workTimeRanges).map((range) {
      if (schoolDaysFromRange(range).isNotEmpty || tempDays.isEmpty) {
        return range;
      }
      return range.copyWith(
        notes: encodeSchoolRangeNotes(
          days: tempDays,
          notes: cleanSchoolRangeNotes(range),
        ),
      );
    }).toList();

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
                          subtitle: cleanSchoolRangeNotes(range),
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
                    const SizedBox(height: 16),
                    buildTextField(
                      controller: workTravelMinutesController,
                      label: "Temps de trajet habituel",
                      hint: "Ex : 20 minutes",
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      onSave: () async {
                        setState(() {
                          selectedWorkDays = {
                            for (final range in tempRanges)
                              ...schoolDaysFromRange(range),
                          }.toList();
                          workTimeRanges = tempRanges;
                        });

                        await saveProfile();

                        if (!context.mounted) return;

                        if (Navigator.canPop(context)) {
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

                        if (!context.mounted) return;

                        if (Navigator.canPop(context)) {
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

                        if (!context.mounted) return;

                        if (Navigator.canPop(context)) {
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
    var selectedCountry = country;
    var selectedLanguage = spokenLanguage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => buildSheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildSheetHandle(),
              const SizedBox(height: 18),
              buildSheetTitle(
                title: 'Langue et région',
                icon: Icons.language_outlined,
              ),
              const SizedBox(height: 18),
              buildSelectionField(
                label: 'Pays',
                value: selectedCountry,
                onTap: () async {
                  showCountryPicker(
                    context: sheetContext,
                    showPhoneCode: false,
                    useSafeArea: true,
                    header: Builder(
                      builder: (countryContext) => Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Retour',
                              onPressed: () => Navigator.pop(countryContext),
                              icon: const Icon(Icons.arrow_back_ios_new),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Choisir un pays',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    countryListTheme: CountryListThemeData(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      backgroundColor: bg,
                      inputDecoration: const InputDecoration(
                        labelText: 'Rechercher un pays',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    onSelect: (value) => setSheetState(
                      () => selectedCountry =
                          value.getTranslatedName(sheetContext) ?? value.name,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              buildSelectionField(
                label: 'Langue principale',
                value: selectedLanguage,
                onTap: () async {
                  final selected = await showLanguageChoice(selectedLanguage);
                  if (selected != null && sheetContext.mounted) {
                    setSheetState(() => selectedLanguage = selected);
                  }
                },
              ),
              const SizedBox(height: 22),
              buildSheetActions(
                onSave: () async {
                  setState(() {
                    country = selectedCountry;
                    spokenLanguage = selectedLanguage;
                  });
                  Navigator.pop(sheetContext);
                  await saveProfile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> showLanguageChoice(String selected) async {
    const languages = [
      'Français',
      'English (bientôt disponible)',
    ];
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (choiceContext) => buildSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSheetHandle(),
            const SizedBox(height: 18),
            buildSheetTitle(
              title: 'Langue principale',
              icon: Icons.translate,
            ),
            const SizedBox(height: 14),
            for (final language in languages)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(language),
                trailing: language == selected
                    ? Icon(Icons.check_circle, color: accent)
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(choiceContext, language),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice == 'Français') return choice;
    if (!mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'L’anglais sera disponible dans une prochaine version.',
        ),
      ),
    );
    return null;
  }

  Future<void> _refreshTimeZoneFromPhone() async {
    final detected = await NotificationService.currentTimezoneId();
    if (!mounted || detected == timeZone) return;
    setState(() => timeZone = detected);
    await saveProfile();
  }

  Future<void> showPlacesSheet() async {
    var locating = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
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
                    title: 'Mes lieux',
                    icon: Icons.place_outlined,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ces lieux aident Zelia à mieux organiser tes trajets.',
                    style: TextStyle(color: textSoft, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.my_location, color: accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ma position actuelle',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                currentLocationLabel(),
                                style: TextStyle(color: textSoft),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: locating
                              ? null
                              : () async {
                                  setSheetState(() => locating = true);
                                  final message = await updateCurrentLocation();
                                  if (!mounted || !sheetContext.mounted) return;
                                  setSheetState(() => locating = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(message)),
                                  );
                                },
                          child: locating
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Actualiser'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  buildTextField(
                    controller: homeAddressController,
                    label: 'Mon domicile',
                    hint: 'Adresse du domicile',
                  ),
                  const SizedBox(height: 14),
                  buildTextField(
                    controller: workAddressController,
                    label: 'Mon travail',
                    hint: 'Adresse du travail',
                  ),
                  const SizedBox(height: 14),
                  buildTextField(
                    controller: importantPlacesController,
                    label: 'Mes autres lieux importants',
                    hint: 'École, sport, famille…',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 22),
                  buildSheetActions(
                    onSave: () async {
                      await saveProfile();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String currentLocationLabel() {
    final visibleCountry = currentCountry.trim().isNotEmpty
        ? currentCountry.trim()
        : country.trim();
    final parts =
        [city.trim(), visibleCountry].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'À compléter' : parts.join(', ');
  }

  Future<String> updateCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Active la localisation du téléphone pour continuer.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'La localisation n’est pas autorisée. Tu peux saisir tes lieux manuellement.';
      }
      final position = await Geolocator.getCurrentPosition();
      final places = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isEmpty) return 'Je n’ai pas trouvé le nom de cette ville.';
      final place = places.first;
      final resolvedCity = (place.locality?.trim().isNotEmpty == true
              ? place.locality
              : place.subAdministrativeArea) ??
          '';
      final resolvedCountry = place.country ?? '';
      if (!mounted) return 'Position trouvée.';
      setState(() {
        city = resolvedCity.trim();
        currentCountry = resolvedCountry.trim();
      });
      await saveProfile();
      return 'Ta position actuelle a été mise à jour.';
    } catch (_) {
      return 'Je n’ai pas pu trouver ta position. Réessaie dans un instant.';
    }
  }

  Future<void> showNotificationsSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationSettingsScreen(),
      ),
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
                          color: Colors.white.withValues(alpha: 0.85),
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
                          color: Colors.white.withValues(alpha: 0.88),
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

                        if (!context.mounted) return;

                        if (Navigator.canPop(context)) {
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
    var photoPath = child?.photoPath ?? '';

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
                        imagePath: photoPath,
                        onTap: () async {
                          final selected = await pickImagePath();
                          if (selected.isNotEmpty) {
                            setModalState(() => photoPath = selected);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildTextField(
                      controller: firstNameController,
                      label: "Prénom",
                      hint: "Ex : Prénom",
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
                          humanPersonId: child?.humanPersonId ?? "",
                          firstName: name,
                          age: calculateAgeFromBirthDate(birth),
                          birthDate: birth,
                          gender: gender,
                          school: "",
                          notes: notesController.text.trim(),
                          photoPath: photoPath,
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
                    if (child != null && index != null) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: () async {
                            final confirmed = await _confirmProfileDeletion(
                              message:
                                  'Le profil de ${child.firstName} ne sera plus affiché.',
                            );
                            if (!confirmed) return;
                            await _deleteChildProfile(index, child);
                            if (context.mounted && Navigator.canPop(context)) {
                              Navigator.pop(context);
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Supprimer ce profil'),
                        ),
                      ),
                    ],
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

  Future<bool> _confirmProfileDeletion({required String message}) async {
    return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) => Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: buildSheetContainer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildSheetHandle(),
                  const SizedBox(height: 20),
                  buildSheetTitle(
                    title: 'Supprimer ce profil ?',
                    icon: Icons.delete_outline,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    style: TextStyle(
                      color: textSoft,
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          style: premiumButtonStyle(),
                          child: const Text('Supprimer'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
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
            color: Colors.black.withValues(alpha: 0.12),
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
          color: textSoft.withValues(alpha: 0.25),
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
            color: accent.withValues(alpha: 0.12),
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

              if (!mounted) return;

              if (Navigator.canPop(context)) {
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
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: 0.10),
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
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: 0.10),
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
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: 0.10),
        ),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: items.contains(value) ? value : items.first,
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

  Widget buildSelectionField({
    required String label,
    required String value,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: textSoft, fontSize: 13)),
                  const SizedBox(height: 5),
                  Text(
                    cleanLabel(value),
                    style: TextStyle(
                      color: textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: accent),
          ],
        ),
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
        color: selected
            ? accent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? accent : accent.withValues(alpha: 0.10),
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
        color: Colors.white.withValues(alpha: 0.88),
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
              color: accent.withValues(alpha: 0.14),
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
    return SizedBox(
      height: 255,
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: 4,
            child: IgnorePointer(
              child: Image.asset(
                'assets/images/zelia_robot.png',
                width: 230,
                height: 250,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            left: 28,
            top: 44,
            right: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profil',
                  style: TextStyle(
                    color: textDark,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 46,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Gère tes informations, tes préférences et ton compte.',
                  style: TextStyle(
                    color: textSoft,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildIdentityCard() {
    final family =
        <({String name, String detail, String imagePath, VoidCallback tap})>[
      if (showPartnerField() && partnerNameController.text.trim().isNotEmpty)
        (
          name: partnerNameController.text.trim(),
          detail: 'Partenaire',
          imagePath: profile.partnerPhotoPath,
          tap: showPartnerSheet,
        ),
      for (var index = 0; index < children.length; index++)
        (
          name: children[index].firstName.trim().isEmpty
              ? 'Enfant'
              : children[index].firstName.trim(),
          detail: children[index].age.trim().isEmpty
              ? 'Profil enfant'
              : '${children[index].age.trim()} ans',
          imagePath: children[index].photoPath,
          tap: () => _openChildProfile(index),
        ),
      for (final person in additionalProfiles)
        (
          name: person.name,
          detail: person.relation,
          imagePath: person.photoPath,
          tap: () => _openAdditionalProfile(person.id),
        ),
    ];
    return Container(
      key: const ValueKey('profile-identity-card'),
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: showPersonalProfileHub,
            child: Row(
              children: [
                buildSmallAvatar(
                  name: firstNameController.text,
                  size: 76,
                  imagePath: profile.profilePhotoPath,
                  onTap: updateUserPhoto,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        firstNameController.text.trim().isEmpty
                            ? 'Mon profil'
                            : firstNameController.text.trim(),
                        style: TextStyle(
                          color: textDark,
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currentLocationLabel(),
                        style: TextStyle(
                          color: textSoft,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right, color: accent),
                ),
              ],
            ),
          ),
          if (!isLivingAlone()) ...[
            const SizedBox(height: 18),
            Divider(color: accent.withValues(alpha: 0.10)),
            const SizedBox(height: 12),
            Text(
              'MA FAMILLE',
              style: TextStyle(
                color: textSoft,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final person in family) ...[
                    _familyProfile(person),
                    const SizedBox(width: 18),
                  ],
                  _addFamilyProfile(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _familyProfile(
    ({String name, String detail, String imagePath, VoidCallback tap}) person,
  ) {
    return InkWell(
      onTap: person.tap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 82,
        child: Column(
          children: [
            buildSmallAvatar(
              name: person.name,
              size: 52,
              imagePath: person.imagePath,
              onTap: person.tap,
            ),
            const SizedBox(height: 6),
            Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textDark, fontWeight: FontWeight.w700),
            ),
            Text(
              person.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textSoft, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChildProfile(int index) async {
    final updated = await showChildEditor(
      child: children[index],
      index: index,
    );
    if (updated == null || !mounted) return;
    setState(() => children[index] = updated);
    await saveProfile(showSnack: false);
  }

  Widget _addFamilyProfile() {
    return InkWell(
      onTap: _openAddPerson,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 82,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, color: accent),
            ),
            const SizedBox(height: 6),
            Text(
              'Ajouter',
              style: TextStyle(color: textDark, fontWeight: FontWeight.w700),
            ),
            Text('un profil', style: TextStyle(color: textSoft, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddPerson() async {
    final alreadyHasPartner = profile.partnerHumanPersonId.trim().isNotEmpty ||
        partnerNameController.text.trim().isNotEmpty;
    var addedAsLegacyPartner = false;
    final added = await Navigator.of(context).push<HumanProfileAddition>(
      MaterialPageRoute<HumanProfileAddition>(
        builder: (_) => HumanProfileScreen(
          legacyProfile: profile,
          startAddingPerson: true,
        ),
      ),
    );
    if (added != null && mounted) {
      if (added.relationshipType == HumanRelationshipTypes.partner ||
          added.relationshipType == HumanRelationshipTypes.spouse) {
        if (!alreadyHasPartner) {
          addedAsLegacyPartner = true;
          setState(() {
            profile = profile.copyWith(
              partnerHumanPersonId: added.personId,
              partnerPhotoPath: added.photoPath,
            );
            partnerNameController.text = added.name;
            partnerBirthDateController.text = added.birthDate;
            relationshipStatus = added.relationshipStatus;
            engagementDateController.text =
                added.relationshipStatus == 'Fiancée'
                    ? added.engagementDate
                    : '';
            marriageDateController.text =
                added.relationshipStatus == 'Mariée' ? added.marriageDate : '';
            selectedFamilyStatus = familyStatuses[1];
          });
          await saveProfile(showSnack: false);
        }
      } else if (added.relationshipType == HumanRelationshipTypes.child) {
        setState(() {
          children.add(
            ChildProfile(
              humanPersonId: added.personId,
              firstName: added.name,
              age: '',
              birthDate: added.birthDate,
              gender: '',
              school: '',
              notes: '',
            ),
          );
          selectedFamilyStatus = familyStatuses[2];
        });
        await saveProfile(showSnack: false);
      }
    }
    await _loadAdditionalProfiles();
    if (added == null || !mounted) return;
    if (added.relationshipType == HumanRelationshipTypes.partner ||
        added.relationshipType == HumanRelationshipTypes.spouse) {
      if (addedAsLegacyPartner) {
        await showPartnerSheet();
      } else {
        await _openAdditionalProfile(added.personId);
      }
    } else if (added.relationshipType == HumanRelationshipTypes.child) {
      final childIndex = children.indexWhere(
        (child) => child.humanPersonId == added.personId,
      );
      if (childIndex >= 0) await _openChildProfile(childIndex);
    } else {
      await _openAdditionalProfile(added.personId);
    }
  }

  Future<void> _loadAdditionalProfiles() async {
    String? scope;
    try {
      scope = AuthService.currentUserId;
    } on Object {
      return;
    }
    if (scope == null || scope.trim().isEmpty) return;
    final service = await HumanModelEditService.createProduction();
    final state = await service.load(scope);
    if (!mounted || state == null) return;
    final representedIds = <String>{
      profile.partnerHumanPersonId,
      ...children.map((child) => child.humanPersonId),
    }..removeWhere((id) => id.trim().isEmpty);
    final profiles = <_AdditionalProfile>[];
    for (final relation in state.model.relationships) {
      if (relation.sourcePersonId != state.model.primaryPersonId ||
          relation.status != HumanRecordStatus.active ||
          representedIds.contains(relation.targetPersonId)) {
        continue;
      }
      final person = state.model.personById(relation.targetPersonId);
      if (person == null || person.status != HumanPersonStatus.active) continue;
      profiles.add(
        _AdditionalProfile(
          id: person.id,
          name: person.displayName?.trim().isNotEmpty == true
              ? person.displayName!.trim()
              : 'Personne',
          relation: _simpleRelationshipLabel(relation),
          photoPath: person.customFields['photoPath']?.toString() ?? '',
        ),
      );
    }
    setState(() => additionalProfiles = profiles);
  }

  Future<void> _openAdditionalProfile(String personId) async {
    final scope = AuthService.currentUserId;
    if (scope == null || scope.trim().isEmpty) return;
    final service = await HumanModelEditService.createProduction();
    final state = await service.load(scope);
    if (!mounted || state == null) return;
    final person = state.model.personById(personId);
    final relations = state.model.relationships.where(
      (relation) =>
          relation.sourcePersonId == state.model.primaryPersonId &&
          relation.targetPersonId == personId &&
          relation.status == HumanRecordStatus.active,
    );
    if (person == null || relations.isEmpty) return;
    final relation = relations.first;
    final rawBirth = person.customFields['birthDate']?.toString() ?? '';
    final parsedBirth = DateTime.tryParse(rawBirth);
    final name = TextEditingController(text: person.displayName ?? '');
    final birth = TextEditingController(
      text: parsedBirth == null
          ? normalizeFrenchDate(rawBirth)
          : formatFrenchDate(parsedBirth),
    );
    final work = TextEditingController(
      text: person.customFields['workSchedule']?.toString() ?? '',
    );
    final notes = TextEditingController(
      text: person.customFields['usefulNotes']?.toString() ?? '',
    );
    final engagement = TextEditingController(
      text: person.customFields['engagementDate']?.toString() ?? '',
    );
    final marriage = TextEditingController(
      text: person.customFields['marriageDate']?.toString() ?? '',
    );
    final isPartner = relation.type == HumanRelationshipTypes.partner ||
        relation.type == HumanRelationshipTypes.spouse;
    await _showAdultProfileSheet(
      title: isPartner ? 'Conjoint' : _simpleRelationshipLabel(relation),
      nameController: name,
      birthController: birth,
      workController: work,
      notesController: notes,
      engagementController: engagement,
      marriageController: marriage,
      initialStatus:
          person.customFields['relationshipStatus']?.toString() ?? 'En couple',
      initialPhotoPath: person.customFields['photoPath']?.toString() ?? '',
      showCoupleStatus: isPartner,
      onSave: (status, photoPath) async {
        final birthday = parseFrenchDate(birth.text);
        await service.commit(
          accountScopeId: scope,
          transform: (model) => model.copyWith(
            persons: model.persons
                .map(
                  (item) => item.id != personId
                      ? item
                      : item.copyWith(
                          displayName: name.text.trim(),
                          evidence: const HumanEvidence(
                            source: HumanInformationSource.explicitUserInput,
                            confirmation: HumanConfirmationStatus.confirmed,
                          ),
                          customFields: {
                            ...item.customFields,
                            if (birthday != null)
                              'birthDate': birthday.toUtc().toIso8601String(),
                            'photoPath': photoPath,
                            'workSchedule': work.text.trim(),
                            'usefulNotes': notes.text.trim(),
                            if (isPartner) 'relationshipStatus': status,
                            if (isPartner && status == 'Fiancée')
                              'engagementDate': engagement.text.trim(),
                            if (isPartner && status == 'Mariée')
                              'marriageDate': marriage.text.trim(),
                          }..removeWhere(
                              (key, _) =>
                                  (key == 'engagementDate' &&
                                      status != 'Fiancée') ||
                                  (key == 'marriageDate' && status != 'Mariée'),
                            ),
                        ),
                )
                .toList(),
          ),
        );
      },
      onDelete: () async {
        await service.commit(
          accountScopeId: scope,
          transform: (model) => model.copyWith(
            persons: model.persons
                .map(
                  (item) => item.id == personId
                      ? item.copyWith(status: HumanPersonStatus.historical)
                      : item,
                )
                .toList(),
            relationships: model.relationships
                .map(
                  (item) => item.targetPersonId == personId
                      ? item.copyWith(status: HumanRecordStatus.historical)
                      : item,
                )
                .toList(),
          ),
        );
      },
    );
    await _loadAdditionalProfiles();
  }

  Future<void> showPersonalProfileHub() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => buildSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSheetHandle(),
            const SizedBox(height: 18),
            buildSheetTitle(
              title: 'Tout sur moi',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 8),
            Text(
              'Les informations personnelles qui aident Zelia à mieux t’accompagner.',
              style: TextStyle(color: textSoft, height: 1.4),
            ),
            const SizedBox(height: 14),
            _personalHubRow(
              sheetContext,
              icon: Icons.badge_outlined,
              title: 'Mes informations principales',
              subtitle: 'Prénom, naissance, famille et travail',
              open: showMainInfoSheet,
            ),
            _personalHubRow(
              sheetContext,
              icon: Icons.access_time,
              title: scheduleTitle(),
              subtitle: workScheduleSummary(),
              open: showWorkScheduleSheet,
            ),
            _personalHubRow(
              sheetContext,
              icon: Icons.self_improvement_outlined,
              title: 'Mes activités',
              subtitle: personalActivities.isEmpty
                  ? 'À compléter'
                  : '${personalActivities.length} activité(s)',
              open: showPersonalActivitiesSheet,
            ),
            _personalHubRow(
              sheetContext,
              icon: Icons.place_outlined,
              title: 'Mes lieux',
              subtitle: currentLocationLabel(),
              open: showPlacesSheet,
            ),
            _personalHubRow(
              sheetContext,
              icon: Icons.auto_awesome_outlined,
              title: 'Ce que Zelia doit savoir sur moi',
              subtitle: personalNotesController.text.trim().isEmpty
                  ? 'À compléter'
                  : 'Voir mes informations',
              open: showPersonalNotesSheet,
            ),
            _personalHubRow(
              sheetContext,
              icon: Icons.health_and_safety_outlined,
              title: 'Ma santé',
              subtitle: allergiesController.text.trim().isEmpty &&
                      medicalNotesController.text.trim().isEmpty
                  ? 'À compléter'
                  : 'Voir mes informations',
              open: showHealthSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _personalHubRow(
    BuildContext sheetContext, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() open,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: accent),
      title: Text(title, style: TextStyle(color: textDark)),
      subtitle: Text(subtitle, style: TextStyle(color: textSoft)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.pop(sheetContext);
        Future<void>(() async {
          await open();
          if (mounted) await showPersonalProfileHub();
        });
      },
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
                color: Colors.white.withValues(alpha: 0.78),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.14),
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
                        backgroundColor: accent.withValues(alpha: 0.17),
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
                        color: accent.withValues(alpha: 0.16),
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
        buildAccountRow(),
        buildDivider(),
        buildProfileRow(
          icon: Icons.language_outlined,
          label: "Langue et région",
          value: null,
          iconColor: textSoft,
          onTap: showLocationSheet,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.notifications_none_rounded,
          label: "Notifications",
          value: null,
          iconColor: textSoft,
          onTap: showNotificationsSettings,
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.auto_awesome,
          label: "Mémoire Zelia",
          value: null,
          iconColor: textSoft,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MemoryLibraryScreen(),
              ),
            );
          },
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.shield_outlined,
          label: 'Confidentialité et mes données',
          value: null,
          iconColor: textSoft,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrivacyDataScreen(),
              ),
            );
          },
          showChevron: true,
        ),
        buildDivider(),
        buildProfileRow(
          icon: Icons.help_outline,
          label: 'Aide et informations',
          value: null,
          iconColor: textSoft,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HelpInformationScreen(),
              ),
            );
          },
          showChevron: true,
        ),
      ],
    );
  }

  Widget buildAccountRow() {
    final user = FirebaseAuth.instance.currentUser;
    final hasPermanentAccount = user != null && !user.isAnonymous;

    return buildProfileRow(
      icon: hasPermanentAccount
          ? Icons.verified_user_outlined
          : Icons.lock_outline,
      label: "Compte Zelia",
      value: null,
      iconColor: hasPermanentAccount ? accent : textSoft,
      onTap: showAccountSheet,
      showChevron: true,
    );
  }

  Future<void> showAccountSheet() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFFFFF7F3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
        builder: (_) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: AuthScreen(
              onAuthenticated: () async {
                await saveProfile(showSnack: false);
                if (!mounted) return;
                setState(() {});
              },
            ),
          );
        },
      );

      if (!mounted) return;
      setState(() {});
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFFF7F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Compte Zelia",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user.email ?? "Compte connecté",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSoft,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await AuthService.signOut();
                      if (!mounted) return;
                      Navigator.pop(context);
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text("Me déconnecter"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() {});
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
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: accent.withValues(alpha: 0.05),
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
    required String? value,
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
            if (value != null && value.trim().isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: value == "À compléter"
                        ? textSoft.withValues(alpha: 0.75)
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
      color: accent.withValues(alpha: 0.08),
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
              buildIdentityCard(),
              buildPremiumSectionsCard(),
              const SizedBox(height: 110),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AdditionalProfile {
  const _AdditionalProfile({
    required this.id,
    required this.name,
    required this.relation,
    required this.photoPath,
  });

  final String id;
  final String name;
  final String relation;
  final String photoPath;
}

String _simpleRelationshipLabel(HumanRelationship relationship) =>
    switch (relationship.type) {
      HumanRelationshipTypes.partner => 'Partenaire',
      HumanRelationshipTypes.spouse => 'Conjoint',
      HumanRelationshipTypes.child => 'Enfant',
      HumanRelationshipTypes.custom =>
        relationship.customType?.trim().isNotEmpty == true
            ? relationship.customType!.trim()
            : 'Autre',
      _ => 'Proche',
    };

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
