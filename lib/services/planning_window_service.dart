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
    final nightLife = _hasNightSchedule(reasoning);
    final lateLife = _hasLateSchedule(reasoning);

    if (nightLife) {
      return const PlanningWindow(
        startHour: 12,
        endHour: 24,
        preferredStartHour: 16,
        preferredEndHour: 23,
        allowNightHours: true,
        avoidMorning: true,
      );
    }

    if (lateLife) {
      return const PlanningWindow(
        startHour: 8,
        endHour: 23,
        preferredStartHour: 14,
        preferredEndHour: 22,
        allowNightHours: false,
        avoidMorning: false,
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

  static bool _shouldAvoidMorning(List<Map<String, dynamic>> reasoning) {
    return reasoning.any((item) {
      return item["type"] == "schedule_constraint" &&
          item["avoidMorning"] == true;
    });
  }

  static bool _prefersAfternoon(List<Map<String, dynamic>> reasoning) {
    return reasoning.any((item) {
      return item["type"] == "schedule_preference" &&
          item["preferredPeriod"] == "afternoon";
    });
  }

  static bool _hasNightSchedule(List<Map<String, dynamic>> reasoning) {
    final text =
        reasoning.map((item) => item.toString().toLowerCase()).join(" ");

    return text.contains("travail de nuit") ||
        text.contains("horaires de nuit") ||
        text.contains("nuit") ||
        text.contains("night");
  }

  static bool _hasLateSchedule(List<Map<String, dynamic>> reasoning) {
    final text =
        reasoning.map((item) => item.toString().toLowerCase()).join(" ");

    return text.contains("soir") ||
        text.contains("tard") ||
        text.contains("late") ||
        text.contains("soirée") ||
        text.contains("soiree");
  }
}
