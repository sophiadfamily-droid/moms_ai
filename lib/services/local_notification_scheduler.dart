import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../models/local_notification_models.dart';
import 'local_notification_registry.dart';
import 'notification_permission_service.dart';
import 'notification_privacy_sanitizer.dart';
import 'notification_settings_service.dart';

enum NotificationScheduleResultType {
  scheduled,
  delivered,
  cancelled,
  idempotent,
  replaced,
  permissionRequired,
  channelDisabled,
  disabled,
  expired,
  invalidTime,
  platformFailure,
}

final class NotificationScheduleResult {
  const NotificationScheduleResult(this.type, this.code, [this.request]);
  final NotificationScheduleResultType type;
  final String code;
  final LocalNotificationRequest? request;
}

abstract interface class LocalNotificationPlatformGateway {
  Future<void> initialize();
  Future<void> schedule({
    required LocalNotificationRequest request,
    required DateTime platformInstant,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  });
  Future<void> showNow({
    required LocalNotificationRequest request,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  });
  Future<void> cancel(int platformNotificationId);
  Future<Set<int>> pendingIds();
  Future<bool?> isChannelEnabled(String channelId);
}

final class NotificationTimeResolver {
  const NotificationTimeResolver();

  DateTime resolve(LocalNotificationRequest request) {
    final location = tz.getLocation(request.timezoneId);
    if (request.scheduleMeaning ==
        NotificationScheduleMeaning.absoluteInstant) {
      return request.scheduledAt.toUtc();
    }
    final supplied = request.scheduledAt;
    final local = tz.TZDateTime(
      location,
      supplied.year,
      supplied.month,
      supplied.day,
      supplied.hour,
      supplied.minute,
    );
    if (local.year != supplied.year ||
        local.month != supplied.month ||
        local.day != supplied.day ||
        local.hour != supplied.hour ||
        local.minute != supplied.minute) {
      throw const FormatException('notification_nonexistent_local_time');
    }
    return local.toUtc();
  }
}

final class LocalNotificationScheduler {
  const LocalNotificationScheduler({
    required this.platform,
    required this.permissionService,
    required this.settingsService,
    required this.registry,
    required this.currentAccountScopeId,
    this.sanitizer = const NotificationPrivacySanitizer(),
    this.timeResolver = const NotificationTimeResolver(),
    this.now = DateTime.now,
  });

  final LocalNotificationPlatformGateway platform;
  final NotificationPermissionService permissionService;
  final NotificationSettingsService settingsService;
  final LocalNotificationRegistry registry;
  final String? Function() currentAccountScopeId;
  final NotificationPrivacySanitizer sanitizer;
  final NotificationTimeResolver timeResolver;
  final DateTime Function() now;

  Future<void> initialize() => platform.initialize();

  Future<NotificationScheduleResult> schedule(
    LocalNotificationRequest request,
  ) async {
    request.validate();
    final scope = _scope();
    if (request.accountScopeId != scope) {
      throw const FormatException('notification_account_mismatch');
    }
    final settings = await settingsService.load();
    if (!settings.enabled) {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.disabled,
        'notifications_disabled',
      );
    }
    final permission = await permissionService.readCurrent();
    if (!permission.notificationsEnabled) {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.permissionRequired,
        'notification_permission_required',
      );
    }
    final content = sanitizer.sanitize(
      request: request,
      privacyMode: settings.privacyMode,
      interactionToken: request.correlationId,
    );
    if (await platform.isChannelEnabled(content.systemCategory) == false) {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.channelDisabled,
        'notification_channel_disabled',
      );
    }
    final instant = timeResolver.resolve(request);
    final current = now().toUtc();
    if (request.expiresAt?.toUtc().isBefore(current) == true) {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.expired,
        'notification_expired',
      );
    }
    if (!instant.isAfter(current)) {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.invalidTime,
        'notification_time_in_past',
      );
    }
    var state = await registry.load(scope);
    final sameId = state.entries.where(
      (item) => item.logicalNotificationId == request.logicalNotificationId,
    );
    if (sameId.isNotEmpty) {
      if (sameId.first.structuralReceipt == request.structuralReceipt) {
        return NotificationScheduleResult(
          NotificationScheduleResultType.idempotent,
          'notification_already_scheduled',
          sameId.first,
        );
      }
      throw const FormatException('notification_idempotency_conflict');
    }
    final replaced = request.replacementKey == null
        ? <LocalNotificationRequest>[]
        : state.entries
            .where((item) => item.replacementKey == request.replacementKey)
            .toList();
    for (final old in replaced) {
      await platform.cancel(old.platformNotificationId);
    }
    final registered = request.withStatus(LocalNotificationStatus.registered);
    state = _replaceState(
      state,
      [
        for (final item in state.entries)
          if (!replaced.contains(item)) item,
        registered,
      ],
    );
    await registry.save(state);
    try {
      await platform.schedule(
        request: request,
        platformInstant: instant,
        content: content,
        settings: settings,
      );
      final scheduled = request.withStatus(LocalNotificationStatus.scheduled);
      await registry.save(_replaceEntry(state, scheduled));
      return NotificationScheduleResult(
        replaced.isEmpty
            ? NotificationScheduleResultType.scheduled
            : NotificationScheduleResultType.replaced,
        replaced.isEmpty ? 'notification_scheduled' : 'notification_replaced',
        scheduled,
      );
    } on Object {
      await registry.save(
        _replaceEntry(
          state,
          request.withStatus(LocalNotificationStatus.failed),
        ),
      );
      return const NotificationScheduleResult(
        NotificationScheduleResultType.platformFailure,
        'notification_platform_failure',
      );
    }
  }

  Future<NotificationScheduleResult> reschedule(
    LocalNotificationRequest request,
  ) async {
    final scope = _scope();
    final state = await registry.load(scope);
    final existing = state.entries
        .where(
          (item) => item.logicalNotificationId == request.logicalNotificationId,
        )
        .toList(growable: false);
    if (existing.isEmpty) {
      return schedule(request);
    }
    if (existing.single.structuralReceipt == request.structuralReceipt) {
      return NotificationScheduleResult(
        NotificationScheduleResultType.idempotent,
        'notification_already_scheduled',
        existing.single,
      );
    }
    await platform.cancel(existing.single.platformNotificationId);
    await registry.save(
      _replaceState(
        state,
        state.entries.where(
          (item) => item.logicalNotificationId != request.logicalNotificationId,
        ),
      ),
    );
    final result = await schedule(request);
    if (result.type == NotificationScheduleResultType.scheduled) {
      return NotificationScheduleResult(
        NotificationScheduleResultType.replaced,
        'notification_rescheduled',
        result.request,
      );
    }
    return result;
  }

  Future<NotificationScheduleResult> deliverImmediateTestNotification(
    LocalNotificationRequest request,
  ) async {
    if (request.category != LocalNotificationCategory.test ||
        request.source != LocalNotificationSource.explicitTest) {
      throw const FormatException('notification_test_request_invalid');
    }
    final scope = _scope();
    final settings = await settingsService.load();
    final permission = await permissionService.readCurrent();
    if (!settings.enabled || !permission.notificationsEnabled) {
      return NotificationScheduleResult(
        settings.enabled
            ? NotificationScheduleResultType.permissionRequired
            : NotificationScheduleResultType.disabled,
        settings.enabled
            ? 'notification_permission_required'
            : 'notifications_disabled',
      );
    }
    final content = sanitizer.sanitize(
      request: request,
      privacyMode: settings.privacyMode,
      interactionToken: request.correlationId,
    );
    if (await platform.isChannelEnabled(content.systemCategory) == false) {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.channelDisabled,
        'notification_channel_disabled',
      );
    }
    try {
      await platform.showNow(
        request: request,
        content: content,
        settings: settings,
      );
      final delivered = request.withStatus(LocalNotificationStatus.delivered);
      final state = await registry.load(scope);
      await registry.save(_replaceEntry(state, delivered));
      return NotificationScheduleResult(
        NotificationScheduleResultType.delivered,
        'notification_test_delivered',
        delivered,
      );
    } on Object {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.platformFailure,
        'notification_platform_failure',
      );
    }
  }

  Future<NotificationScheduleResult> cancel(String logicalId) async {
    final scope = _scope();
    final state = await registry.load(scope);
    final matches =
        state.entries.where((item) => item.logicalNotificationId == logicalId);
    if (matches.isEmpty) {
      return const NotificationScheduleResult(
        NotificationScheduleResultType.idempotent,
        'notification_already_absent',
      );
    }
    final item = matches.first;
    await platform.cancel(item.platformNotificationId);
    await registry.save(
      _replaceEntry(state, item.withStatus(LocalNotificationStatus.cancelled)),
    );
    return NotificationScheduleResult(
      NotificationScheduleResultType.cancelled,
      'notification_cancelled',
      item,
    );
  }

  Future<void> cancelByReplacementKey(String key) async {
    final state = await registry.load(_scope());
    for (final item
        in state.entries.where((item) => item.replacementKey == key)) {
      await cancel(item.logicalNotificationId);
    }
  }

  Future<void> cancelAllForAccount() async {
    final state = await registry.load(_scope());
    for (final item in state.entries) {
      await platform.cancel(item.platformNotificationId);
    }
    await registry.save(
      NotificationRegistryState(
        accountScopeId: state.accountScopeId,
        entries: state.entries
            .map((item) => item.withStatus(LocalNotificationStatus.cancelled)),
      ),
    );
  }

  Future<List<LocalNotificationRequest>> listPending() async {
    final state = await registry.load(_scope());
    return state.entries
        .where((item) => item.status == LocalNotificationStatus.scheduled)
        .toList(growable: false);
  }

  Future<void> reconcileWithPlatform() async {
    final scope = _scope();
    final state = await registry.load(scope);
    final pending = await platform.pendingIds();
    final current = now().toUtc();
    final reconciled = state.entries.map((item) {
      if (item.expiresAt?.toUtc().isBefore(current) == true) {
        return item.withStatus(LocalNotificationStatus.expired);
      }
      if (item.status == LocalNotificationStatus.scheduled &&
          !pending.contains(item.platformNotificationId)) {
        return item.withStatus(LocalNotificationStatus.delivered);
      }
      return item;
    });
    await registry.save(_replaceState(state, reconciled));
  }

  NotificationRegistryState _replaceEntry(
    NotificationRegistryState state,
    LocalNotificationRequest replacement,
  ) =>
      _replaceState(state, [
        for (final item in state.entries)
          if (item.logicalNotificationId != replacement.logicalNotificationId)
            item,
        replacement,
      ]);

  NotificationRegistryState _replaceState(
    NotificationRegistryState state,
    Iterable<LocalNotificationRequest> values,
  ) {
    final sorted = values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return NotificationRegistryState(
      accountScopeId: state.accountScopeId,
      entries: sorted.take(NotificationRegistryState.maximumEntries),
    );
  }

  String _scope() {
    final value = currentAccountScopeId();
    if (value == null || value.trim().isEmpty) {
      throw const FormatException('notification_auth_required');
    }
    return value;
  }
}

final class NotificationInteractionPayload {
  const NotificationInteractionPayload({
    required this.schemaVersion,
    required this.notificationId,
    required this.destinationType,
    required this.interactionToken,
  });

  factory NotificationInteractionPayload.parse(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map ||
        decoded.keys.toSet().difference({
          'schemaVersion',
          'notificationId',
          'destinationType',
          'interactionToken',
        }).isNotEmpty ||
        decoded['schemaVersion'] != 1) {
      throw const FormatException('notification_interaction_payload_invalid');
    }
    final destination = NotificationDestinationType.values
        .where((item) => item.name == decoded['destinationType'])
        .single;
    return NotificationInteractionPayload(
      schemaVersion: 1,
      notificationId: decoded['notificationId'] as String,
      destinationType: destination,
      interactionToken: decoded['interactionToken'] as String,
    );
  }

  final int schemaVersion;
  final String notificationId;
  final NotificationDestinationType destinationType;
  final String interactionToken;
}
