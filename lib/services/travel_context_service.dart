class TravelContextService {
  static int parseTravelMinutes(dynamic value) {
    if (value == null) return 0;

    final raw = value.toString().trim().toLowerCase();

    if (raw.isEmpty) return 0;

    final direct = int.tryParse(raw);
    if (direct != null) return direct.clamp(0, 240);

    final numberMatch = RegExp(r'\d+').firstMatch(raw);
    if (numberMatch == null) return 0;

    final minutes = int.tryParse(numberMatch.group(0) ?? "") ?? 0;

    if (raw.contains("h") || raw.contains("heure")) {
      return (minutes * 60).clamp(0, 240);
    }

    return minutes.clamp(0, 240);
  }

  static Map<String, dynamic> buildTravelMetadata({
    dynamic travelMinutes,
    String origin = "",
    String destination = "",
    String mode = "unknown",
    String provider = "manual_profile",
  }) {
    final minutes = parseTravelMinutes(travelMinutes);

    return {
      "travelBeforeMinutes": minutes,
      "travelAfterMinutes": minutes,
      "travelMinutes": minutes,
      "origin": origin,
      "destination": destination,
      "mode": mode,
      "provider": provider,
      "isDynamic": false,
    };
  }

  static Map<String, dynamic> buildFutureDynamicTravelPlaceholder({
    String origin = "",
    String destination = "",
    String mode = "driving",
  }) {
    return {
      "travelBeforeMinutes": 0,
      "travelAfterMinutes": 0,
      "travelMinutes": 0,
      "origin": origin,
      "destination": destination,
      "mode": mode,
      "provider": "future_dynamic_provider",
      "isDynamic": true,
      "trafficAware": true,
    };
  }
}
