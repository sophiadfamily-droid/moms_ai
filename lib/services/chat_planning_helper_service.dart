class ChatPlanningHelperService {
  ChatPlanningHelperService._();

  static String normalizeTime(String value) {
    final trimmed = value.trim();

    if (trimmed.contains(":")) {
      return trimmed;
    }

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length == 1 || digits.length == 2) {
      return "${digits.padLeft(2, "0")}:00";
    }

    if (digits.length == 3) {
      return "0${digits[0]}:${digits.substring(1)}";
    }

    if (digits.length >= 4) {
      return "${digits.substring(0, 2)}:${digits.substring(2, 4)}";
    }

    return trimmed;
  }

  static String buildStartDateTimeIso({
    required String date,
    required String time,
  }) {
    return "${date}T${normalizeTime(time)}:00";
  }

  static String buildEndDateTimeIso({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final start = DateTime.tryParse(
      buildStartDateTimeIso(
        date: date,
        time: time,
      ),
    );

    if (start == null) {
      return "";
    }

    final end = start.add(
      Duration(minutes: durationMinutes),
    );

    final y = end.year.toString();
    final m = end.month.toString().padLeft(2, "0");
    final d = end.day.toString().padLeft(2, "0");
    final h = end.hour.toString().padLeft(2, "0");
    final min = end.minute.toString().padLeft(2, "0");

    return "$y-$m-${d}T$h:$min:00";
  }

  static String endTimeFromDuration({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final endIso = buildEndDateTimeIso(
      date: date,
      time: time,
      durationMinutes: durationMinutes,
    );

    if (endIso.isEmpty) {
      return "";
    }

    final end = DateTime.tryParse(endIso);

    if (end == null) {
      return "";
    }

    final h = end.hour.toString().padLeft(2, "0");
    final m = end.minute.toString().padLeft(2, "0");

    return "$h:$m";
  }

  static bool durationContextIsClear(String text) {
    final lower = text.toLowerCase();

    return lower.contains("pendant") ||
        lower.contains("dure") ||
        lower.contains("durée") ||
        lower.contains("pour") ||
        lower.contains("environ") ||
        lower.contains("minutes") ||
        lower.contains("minute") ||
        lower.contains("heures") ||
        lower.contains("heure") ||
        lower.contains("h");
  }

  static int parseDurationMinutes(String text) {
    final lower = text.trim().toLowerCase().replaceAll("’", "'");

    if (lower.isEmpty) {
      return 0;
    }

    final minuteMatch = RegExp(
      r'(\d+)\s*(minutes|minute|min)\b',
    ).firstMatch(lower);

    if (minuteMatch != null) {
      return int.tryParse(minuteMatch.group(1) ?? "") ?? 0;
    }

    final hourWordMatch = RegExp(
      r'(\d+)\s*(heures|heure)\b',
    ).firstMatch(lower);

    if (hourWordMatch != null) {
      final hours = int.tryParse(hourWordMatch.group(1) ?? "") ?? 0;
      return hours > 0 ? hours * 60 : 0;
    }

    final compactDurationMatch = RegExp(
      r'^(\d+)\s*h(?:\s*(\d+))?$',
    ).firstMatch(lower);

    if (compactDurationMatch != null) {
      final hours = int.tryParse(compactDurationMatch.group(1) ?? "") ?? 0;
      final minutes = int.tryParse(compactDurationMatch.group(2) ?? "") ?? 0;

      return (hours * 60) + minutes;
    }

    final contextualHourMatch = RegExp(
      r'(\d+)\s*h(?:\s*(\d+))?',
    ).firstMatch(lower);

    if (contextualHourMatch != null && durationContextIsClear(lower)) {
      final prefix = lower.substring(0, contextualHourMatch.start).trimRight();

      final looksLikeAppointmentTime =
          RegExp(r'(?:^|\s)(?:à|a|vers)$').hasMatch(prefix);

      if (!looksLikeAppointmentTime) {
        final hours = int.tryParse(contextualHourMatch.group(1) ?? "") ?? 0;
        final minutes = int.tryParse(contextualHourMatch.group(2) ?? "") ?? 0;

        return (hours * 60) + minutes;
      }
    }

    return 0;
  }
}
