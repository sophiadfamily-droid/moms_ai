import '../models/user_profile.dart';

class SchoolScheduleMetadataService {
  static const String daysMarker = "__DAYS__:";

  static List<String> daysFromRange(TimeRangeModel range) {
    final notes = range.notes.trim();

    if (!notes.contains(daysMarker)) {
      return const [];
    }

    final markerIndex = notes.indexOf(daysMarker);
    final afterMarker = notes.substring(markerIndex + daysMarker.length);
    final endIndex = afterMarker.indexOf("__");
    final encoded =
        endIndex == -1 ? afterMarker : afterMarker.substring(0, endIndex);

    return encoded
        .split("|")
        .map((day) => day.trim())
        .where((day) => day.isNotEmpty)
        .toList();
  }

  static String cleanNotes(TimeRangeModel range) {
    final notes = range.notes;

    if (!notes.contains(daysMarker)) {
      return notes.trim();
    }

    final markerIndex = notes.indexOf(daysMarker);
    final before = notes.substring(0, markerIndex).trim();
    final afterMarker = notes.substring(markerIndex + daysMarker.length);
    final endIndex = afterMarker.indexOf("__");

    if (endIndex == -1) {
      return before;
    }

    final after = afterMarker.substring(endIndex + 2).trim();

    return [before, after].where((part) => part.isNotEmpty).join(" ").trim();
  }

  static String encodeNotes({
    required List<String> days,
    required String notes,
  }) {
    final cleanDays =
        days.map((day) => day.trim()).where((day) => day.isNotEmpty).toList();

    final cleanNotes = notes.trim();

    if (cleanDays.isEmpty) {
      return cleanNotes;
    }

    final marker = "$daysMarker${cleanDays.join("|")}__";

    return cleanNotes.isEmpty ? marker : "$marker $cleanNotes";
  }
}
