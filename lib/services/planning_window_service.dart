class PlanningWindow {
  final int startHour;
  final int endHour;
  final int preferredStartHour;
  final int preferredEndHour;
  final bool allowNightHours;
  final bool avoidMorning;

  const PlanningWindow({
    required this.startHour,
    required this.endHour,
    required this.preferredStartHour,
    required this.preferredEndHour,
    required this.allowNightHours,
    required this.avoidMorning,
  });
}

class PlanningWindowService {
  static PlanningWindow build({
    required List<Map<String, dynamic>> reasoning,
  }) {
    final avoidMorning = _shouldAvoidMorning(reasoning);
    final prefersAfternoon = _prefersAfternoon(reasoning);
    final scheduleMode = _scheduleMode(reasoning);

    if (scheduleMode == "night") {
      return const PlanningWindow(
        startHour: 12,
        endHour: 24,
        preferredStartHour: 16,
        preferredEndHour: 23,
        allowNightHours: true,
        avoidMorning: true,
      );
    }

    if (scheduleMode == "late") {
      return PlanningWindow(
        startHour: avoidMorning ? 12 : 8,
        endHour: 23,
        preferredStartHour: 14,
        preferredEndHour: 22,
        allowNightHours: false,
        avoidMorning: avoidMorning,
      );
    }

    if (prefersAfternoon || avoidMorning) {
      return PlanningWindow(
        startHour: avoidMorning ? 12 : 8,
        endHour: 21,
        preferredStartHour: 13,
        preferredEndHour: 20,
        allowNightHours: false,
        avoidMorning: avoidMorning,
      );
    }

    return const PlanningWindow(
      startHour: 8,
      endHour: 21,
      preferredStartHour: 9,
      preferredEndHour: 18,
      allowNightHours: false,
      avoidMorning: false,
    );
  }

  static bool _shouldAvoidMorning(
    List<Map<String, dynamic>> reasoning,
  ) {
    return reasoning.any((item) {
      return item["type"] == "schedule_constraint" &&
          item["avoidMorning"] == true;
    });
  }

  static bool _prefersAfternoon(
    List<Map<String, dynamic>> reasoning,
  ) {
    return reasoning.any((item) {
      return item["type"] == "schedule_preference" &&
          item["preferredPeriod"] == "afternoon";
    });
  }

  static String _scheduleMode(
    List<Map<String, dynamic>> reasoning,
  ) {
    var hasLateMode = false;

    for (final item in reasoning) {
      if (item["type"] != "schedule_constraint") {
        continue;
      }

      final mode = item["scheduleMode"]?.toString().trim().toLowerCase() ?? "";

      if (mode == "night") {
        return "night";
      }

      if (mode == "late") {
        hasLateMode = true;
      }
    }

    return hasLateMode ? "late" : "standard";
  }
}
