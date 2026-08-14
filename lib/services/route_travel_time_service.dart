import 'dart:async';

import 'package:flutter/services.dart';

enum RouteTravelMode {
  automobile,
  publicTransport,
  walking,
}

final class RouteTravelTimeRequest {
  const RouteTravelTimeRequest({
    required this.origin,
    required this.destination,
    required this.departureAt,
    this.mode = RouteTravelMode.automobile,
  });

  final String origin;
  final String destination;
  final DateTime departureAt;
  final RouteTravelMode mode;
}

abstract interface class RouteTravelTimeGateway {
  Future<int?> estimateMinutes(RouteTravelTimeRequest request);
}

abstract interface class RouteTravelConsentGateway {
  Future<bool> isAuthorized();

  Future<void> setAuthorized(bool authorized);
}

/// Uses the native Apple Maps routing service on iOS.
///
/// This boundary is called only after the profile-owned travel calculation
/// setting has been enabled. It never records either endpoint and it does not
/// emit them to diagnostics.
final class AppleMapsRouteTravelTimeGateway
    implements RouteTravelTimeGateway, RouteTravelConsentGateway {
  const AppleMapsRouteTravelTimeGateway({
    MethodChannel channel = const MethodChannel(
      'com.zelia.app/route_travel_time',
    ),
    Duration timeout = const Duration(seconds: 12),
  })  : _channel = channel,
        _timeout = timeout;

  final MethodChannel _channel;
  final Duration _timeout;

  @override
  Future<bool> isAuthorized() async {
    try {
      return await _channel
              .invokeMethod<bool>('isTravelCalculationAuthorized')
              .timeout(_timeout) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<void> setAuthorized(bool authorized) async {
    await _channel.invokeMethod<void>(
      'setTravelCalculationAuthorized',
      {'authorized': authorized},
    ).timeout(_timeout);
  }

  @override
  Future<int?> estimateMinutes(RouteTravelTimeRequest request) async {
    if (!await isAuthorized()) return null;
    final origin = _boundedPlace(request.origin);
    final destination = _boundedPlace(request.destination);
    if (origin == null || destination == null) return null;
    if (_normalized(origin) == _normalized(destination)) return 0;

    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'estimateTravelTime',
        {
          'origin': origin,
          'destination': destination,
          'departureAtMilliseconds': request.departureAt.millisecondsSinceEpoch,
          'mode': request.mode.name,
        },
      ).timeout(_timeout);
      final rawMinutes = result?['minutes'];
      final minutes = rawMinutes is num
          ? rawMinutes.ceil()
          : int.tryParse(rawMinutes?.toString() ?? '');
      if (minutes == null || minutes < 0 || minutes > 24 * 60) return null;
      return minutes;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static String? _boundedPlace(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty || cleaned.length > 240) return null;
    return cleaned;
  }

  static String _normalized(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[^a-z0-9àâäçéèêëîïôöùûü]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
