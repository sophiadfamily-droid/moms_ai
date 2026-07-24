import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/local_notification_models.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/models/proactive_notification_policy.dart';
import 'package:moms_ai/screens/daily_summary_screen.dart';
import 'package:moms_ai/screens/notification_settings_screen.dart';
import 'package:moms_ai/services/daily_summary_builder.dart';
import 'package:moms_ai/services/daily_summary_view_service.dart';
import 'package:moms_ai/services/local_notification_scheduler.dart';
import 'package:moms_ai/services/local_notification_registry.dart';
import 'package:moms_ai/services/notification_permission_service.dart';
import 'package:moms_ai/services/notification_privacy_sanitizer.dart';
import 'package:moms_ai/services/notification_settings_controller.dart';
import 'package:moms_ai/services/notification_settings_service.dart';
import 'package:moms_ai/services/proactive_notification_delivery_registry.dart';
import 'package:moms_ai/services/proactive_notification_orchestrator.dart';
import 'package:moms_ai/services/proactive_detection_registry.dart';
import 'package:moms_ai/services/proactive_notification_policy_engine.dart';
import 'package:moms_ai/services/proactive_notification_policy_service.dart';
import 'package:moms_ai/services/proactive_notification_settings_controller.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  tz_data.initializeTimeZones();
  final now = DateTime.utc(2026, 7, 24, 10);

  group('N.3 official policy and persistence', () {
    test('restrictive default is versioned, complete and deterministic', () {
      final policy = ProactiveNotificationPolicy.restrictiveDefault(
        accountScopeId: 'account-a',
        timezoneId: 'Europe/Paris',
        changedAt: now,
      );
      expect(policy.enabled, isFalse);
      expect(policy.dailySummarySettings.enabled, isFalse);
      expect(policy.criticalProductAlertPolicy.enabled, isFalse);
      expect(policy.categorySettings.values.every((item) => !item.enabled),
          isTrue);
      expect(
        ProactiveNotificationPolicy.fromJson(
          policy.toJson(),
          expectedAccountScopeId: 'account-a',
        ).toJson(),
        policy.toJson(),
      );
      final future = policy.toJson()..['schemaVersion'] = 2;
      expect(
        () => ProactiveNotificationPolicy.fromJson(
          future,
          expectedAccountScopeId: 'account-a',
        ),
        throwsFormatException,
      );
      final unknown = policy.toJson()..['marketing'] = true;
      expect(
        () => ProactiveNotificationPolicy.fromJson(
          unknown,
          expectedAccountScopeId: 'account-a',
        ),
        throwsFormatException,
      );
    });

    test('service isolates accounts, revisions writes and reads back',
        () async {
      final repository = _PolicyRepository();
      var scope = 'account-a';
      final service = ProactiveNotificationPolicyService(
        repository: repository,
        currentAccountScopeId: () => scope,
        currentTimezoneId: () async => 'Europe/Paris',
        now: () => now,
      );
      expect((await service.load()).enabled, isFalse);
      final saved = await service.update(
        (current, changedAt, timezone) => current.copyWith(
          enabled: true,
          changedAt: changedAt,
          timezoneId: timezone,
          changeSource: ProactivePolicyChangeSource.explicitUserSetting,
          policyRevision: 1,
        ),
      );
      expect(saved.enabled, isTrue);
      expect(saved.policyRevision, 1);
      scope = 'account-b';
      expect((await service.load()).enabled, isFalse);
    });

    test('pause is explicit, temporary or indefinite, and never models A.1',
        () {
      final pause = ProactiveNotificationPause(
        state: ProactivePauseState.pausedUntil,
        startedAt: now,
        resumesAt: now.add(const Duration(hours: 1)),
        reasonSource: ProactivePauseReasonSource.explicitUserSetting,
        createdByUser: true,
        policyRevision: 1,
        affectedCategories: const {
          ProactiveAlertCategory.deadlinePassed,
        },
      );
      pause.validate();
      expect(
        pause.isActiveAt(
          now.add(const Duration(minutes: 30)),
          ProactiveAlertCategory.deadlinePassed,
        ),
        isTrue,
      );
      expect(
        pause.isActiveAt(
          now.add(const Duration(hours: 2)),
          ProactiveAlertCategory.deadlinePassed,
        ),
        isFalse,
      );
      expect(
        File('lib/models/proactive_notification_policy.dart')
            .readAsStringSync(),
        isNot(contains('ActionAutonomyMode')),
      );
    });

    test('quiet hours validate weekdays and cross midnight deterministically',
        () {
      final quiet = NotificationQuietHours(
        startMinute: 22 * 60,
        endMinute: 7 * 60,
        timezoneId: 'Europe/Paris',
        changedAt: now,
      );
      expect(quiet.crossesMidnight, isTrue);
      expect(NotificationQuietHours.fromJson(quiet.toJson()).toJson(),
          quiet.toJson());
      expect(
        () => NotificationQuietHours(
          startMinute: 60,
          endMinute: 60,
          timezoneId: 'Europe/Paris',
        ),
        throwsFormatException,
      );
    });
  });

  group('N.3 policy engine', () {
    test('disabled, permission, category and evidence protections fail closed',
        () {
      final signal = _signal(now);
      final restrictive = _policy(now, enabled: false);
      expect(
        _decide(restrictive, signal, now).type,
        NotificationDeliveryDecisionType.suppressDisabled,
      );
      final enabled = _policy(now);
      expect(
        _decide(enabled, signal, now, permissionEnabled: false).type,
        NotificationDeliveryDecisionType.suppressPermission,
      );
      expect(
        _decide(
          enabled,
          _signal(
            now,
            confidence: DetectionConfidenceLevel.insufficient,
          ),
          now,
        ).type,
        NotificationDeliveryDecisionType.suppressInsufficientEvidence,
      );
    });

    test('eligible signal schedules once and duplicate is suppressed', () {
      final policy = _policy(now);
      final signal = _signal(now);
      final first = _decide(policy, signal, now);
      expect(first.type, NotificationDeliveryDecisionType.schedule);
      final duplicate = const ProactiveNotificationPolicyEngine().decideSignal(
        policy: policy,
        signal: signal,
        history: [
          NotificationDeliveryRecord(
            incidentFingerprint: signal.incidentFingerprint,
            category: ProactiveAlertCategory.deadlinePassed,
            decidedAt: now,
            decision: first.type,
            replacementCount: 0,
            deferralCount: 0,
            critical: false,
          ),
        ],
        permission: _permission(now),
        notificationSettings: _notificationSettings(now),
        now: now.add(const Duration(minutes: 1)),
      );
      expect(
        duplicate.type,
        NotificationDeliveryDecisionType.suppressDuplicate,
      );
    });

    test('temporary and indefinite pause suppress without changing A.1', () {
      final base = _policy(now);
      final paused = base.copyWith(
        pause: ProactiveNotificationPause(
          state: ProactivePauseState.pausedIndefinitely,
          startedAt: now,
          reasonSource: ProactivePauseReasonSource.explicitUserSetting,
          createdByUser: true,
          policyRevision: base.policyRevision,
          affectedCategories: const {
            ProactiveAlertCategory.deadlinePassed,
          },
        ),
      );
      expect(
        _decide(paused, _signal(now), now).type,
        NotificationDeliveryDecisionType.suppressPaused,
      );
    });

    test('quiet hours defer once and rate limits include in summary', () {
      final quietPolicy = _policy(
        DateTime.utc(2026, 7, 24, 21),
        quiet: NotificationQuietHours(
          startMinute: 22 * 60,
          endMinute: 7 * 60,
          timezoneId: 'Europe/Paris',
          changedAt: now,
        ),
      );
      final quiet = _decide(
        quietPolicy,
        _signal(DateTime.utc(2026, 7, 24, 21)),
        DateTime.utc(2026, 7, 24, 21),
      );
      expect(quiet.type, NotificationDeliveryDecisionType.deferUntil);
      expect(quiet.scheduledAt, isNotNull);

      final policy = _policy(now);
      final history = List.generate(
        policy.rateLimitPolicy.maximumTotalPerDay,
        (index) => NotificationDeliveryRecord(
          incidentFingerprint: 'old-$index',
          category: ProactiveAlertCategory.deadlinePassed,
          decidedAt: now.subtract(Duration(hours: index + 1)),
          decision: NotificationDeliveryDecisionType.schedule,
          replacementCount: 0,
          deferralCount: 0,
          critical: false,
        ),
      );
      final limited = const ProactiveNotificationPolicyEngine().decideSignal(
        policy: policy,
        signal: _signal(now),
        history: history,
        permission: _permission(now),
        notificationSettings: _notificationSettings(now),
        now: now,
      );
      expect(
        limited.type,
        NotificationDeliveryDecisionType.includeInDailySummary,
      );
    });

    test(
        'important alert requires strong current N.2 proof and is never OS critical',
        () {
      final policy = _policy(now, critical: true);
      final strong = _signal(
        now,
        severity: DetectionTechnicalSeverity.important,
        confidence: DetectionConfidenceLevel.certain,
        coverage: DetectionCoverageKind.complete,
      );
      expect(_decide(policy, strong, now).isCriticalProductAlert, isTrue);
      final omission = _signal(
        now,
        reason: ProactiveDetectionReason.potentialOmission,
        detector: ProactiveDetectorType.potentialOmission,
        severity: DetectionTechnicalSeverity.important,
        confidence: DetectionConfidenceLevel.certain,
        coverage: DetectionCoverageKind.complete,
      );
      expect(_decide(policy, omission, now).isCriticalProductAlert, isFalse);
      expect(
        File('ios/Runner/Runner.entitlements').existsSync()
            ? File('ios/Runner/Runner.entitlements').readAsStringSync()
            : '',
        isNot(contains('critical-alerts')),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        allOf(
          isNot(contains('SCHEDULE_EXACT_ALARM')),
          isNot(contains('USE_FULL_SCREEN_INTENT')),
        ),
      );
    });
  });

  group('N.3 daily summary and architecture', () {
    test('summary is deterministic, bounded, generic and excludes resolved',
        () {
      final policy = _policy(now, summary: true);
      final signals = [
        _signal(now, id: 'one'),
        _signal(now,
            id: 'two', reason: ProactiveDetectionReason.objectivelyDelayed),
        _signal(now, id: 'gone').copyWith(
          state: ProactiveDetectionState.resolved,
          resolvedAt: now,
        ),
      ];
      final result = const DailySummaryBuilder().build(
        accountScopeId: 'account-a',
        signals: signals,
        coverage: _coverage(),
        policy: policy,
        now: now,
      );
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.itemReferences, ['one', 'two']);
      expect(result.snapshot!.itemReferences, isNot(contains('gone')));
      expect(result.snapshot!.itemReferences.length,
          lessThanOrEqualTo(policy.rateLimitPolicy.maximumSummaryItems));
    });

    test('empty or disabled summary produces no snapshot', () {
      expect(
        const DailySummaryBuilder()
            .build(
              accountScopeId: 'account-a',
              signals: const [],
              coverage: _coverage(),
              policy: _policy(now, summary: true),
              now: now,
            )
            .snapshot,
        isNull,
      );
    });

    test('delivery history is bounded and contains no business content', () {
      expect(
        () => ProactiveNotificationDeliveryState(
          accountScopeId: 'account-a',
          records: List.generate(
            ProactiveNotificationDeliveryState.maximumRecords + 1,
            (index) => NotificationDeliveryRecord(
              incidentFingerprint: 'incident-$index',
              category: ProactiveAlertCategory.deadlinePassed,
              decidedAt: now,
              decision: NotificationDeliveryDecisionType.schedule,
              replacementCount: 0,
              deferralCount: 0,
              critical: false,
            ),
          ),
          updatedAt: now,
        ),
        throwsFormatException,
      );
      final source =
          File('lib/services/proactive_notification_delivery_registry.dart')
              .readAsStringSync();
      expect(source, isNot(contains('title')));
      expect(source, isNot(contains('body')));
      expect(source, isNot(contains('OpenAI')));
    });

    test('production path is N.2 to N.3 to N.1 without mutation or ledger', () {
      final service =
          File('lib/services/notification_service.dart').readAsStringSync();
      final orchestrator =
          File('lib/services/proactive_notification_orchestrator.dart')
              .readAsStringSync();
      expect(service, contains('ProactiveNotificationOrchestrator'));
      expect(service, isNot(contains('DetectionNotificationCoordinator(')));
      expect(orchestrator, isNot(contains('OpenAI')));
      expect(orchestrator, isNot(contains('ActionLedger')));
      expect(orchestrator, isNot(contains('ChatScreen')));
      expect(
        File('lib/screens/notification_settings_screen.dart')
            .readAsStringSync(),
        allOf(
          isNot(contains('SharedPreferences')),
          isNot(contains('FlutterLocalNotificationsPlugin')),
        ),
      );
    });

    test('orchestrator schedules once, records reality and cancels on pause',
        () async {
      final platform = _PlatformGateway();
      final localRegistry = _LocalRegistry();
      final settingsRepository = _SettingsRepository();
      final settingsService = NotificationSettingsService(
        repository: settingsRepository,
        currentAccountScopeId: () => 'account-a',
        currentTimezoneId: () async => 'Europe/Paris',
        now: () => now,
      );
      await settingsService.save(
        enabled: true,
        permissionPromptExplained: true,
        soundEnabled: false,
        vibrationEnabled: false,
        badgeEnabled: false,
      );
      final permissionService =
          NotificationPermissionService(_PermissionGateway(now));
      final scheduler = LocalNotificationScheduler(
        platform: platform,
        permissionService: permissionService,
        settingsService: settingsService,
        registry: localRegistry,
        currentAccountScopeId: () => 'account-a',
        now: () => now,
      );
      final policyRepository = _PolicyRepository()
        ..values['account-a'] = _policy(now, summary: false);
      final policyService = ProactiveNotificationPolicyService(
        repository: policyRepository,
        currentAccountScopeId: () => 'account-a',
        currentTimezoneId: () async => 'Europe/Paris',
        now: () => now,
      );
      final signals = _SignalRegistry(now);
      final deliveries = _DeliveryRegistry(now);
      final orchestrator = ProactiveNotificationOrchestrator(
        scheduler: scheduler,
        signalRegistry: signals,
        deliveryRegistry: deliveries,
        policyService: policyService,
        permissionService: permissionService,
        notificationSettingsService: settingsService,
        currentAccountScopeId: () => 'account-a',
        now: () => now,
      );
      final signal = _signal(now);
      final result = ProactiveDetectionResult(
        activeSignals: [signal],
        resolvedSignals: const [],
        coverage: _coverage(),
        numberSuppressed: 0,
        evaluatedAt: now,
      );
      final first =
          await orchestrator.apply(result, timezoneId: 'Europe/Paris');
      expect(first.numberScheduled, 1);
      expect(platform.scheduled, hasLength(1));
      expect(deliveries.state.records, hasLength(1));
      final scheduledSignal = signals.state.signals.single;
      expect(scheduledSignal.state, ProactiveDetectionState.scheduled);

      policyRepository.values['account-a'] = _policy(
        now,
        summary: false,
      ).copyWith(
        pause: ProactiveNotificationPause(
          state: ProactivePauseState.pausedIndefinitely,
          startedAt: now,
          reasonSource: ProactivePauseReasonSource.explicitUserSetting,
          createdByUser: true,
          policyRevision: 1,
          affectedCategories: const {
            ProactiveAlertCategory.deadlinePassed,
          },
        ),
      );
      final paused = await orchestrator.apply(
        ProactiveDetectionResult(
          activeSignals: [scheduledSignal],
          resolvedSignals: const [],
          coverage: _coverage(),
          numberSuppressed: 0,
          evaluatedAt: now,
        ),
        timezoneId: 'Europe/Paris',
      );
      expect(paused.numberCancelled, 1);
      expect(platform.cancelled, isNotEmpty);
      expect(signals.state.signals.single.notificationLogicalId, isNull);
    });

    testWidgets('advanced settings stay responsive on phone, tablet and 1.6',
        (tester) async {
      final policyService = ProactiveNotificationPolicyService(
        repository: _PolicyRepository(),
        currentAccountScopeId: () => 'account-a',
        currentTimezoneId: () async => 'Europe/Paris',
        now: () => now,
      );
      final settingsService = NotificationSettingsService(
        repository: _SettingsRepository(),
        currentAccountScopeId: () => 'account-a',
        currentTimezoneId: () async => 'Europe/Paris',
        now: () => now,
      );
      for (final size in const [Size(390, 844), Size(1024, 768)]) {
        final baseController = NotificationSettingsController(
          settingsService: settingsService,
          permissionService:
              NotificationPermissionService(_PermissionGateway(now)),
          sendTest: () async => const NotificationScheduleResult(
            NotificationScheduleResultType.delivered,
            'test_delivered',
          ),
        );
        final proactiveController = ProactiveNotificationSettingsController(
          service: policyService,
        );
        await baseController.load();
        await proactiveController.load();
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.6),
              ),
              child: NotificationSettingsScreen(
                controller: baseController,
                proactiveController: proactiveController,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(baseController.loading, isFalse);
        expect(proactiveController.loading, isFalse);
        expect(baseController.settings, isNotNull);
        expect(proactiveController.policy, isNotNull);
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsOneWidget);
        await tester.drag(
          find.byType(Scrollable),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();
        for (var index = 0; index < 4; index++) {
          await tester.drag(
            find.byType(Scrollable),
            const Offset(0, -700),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
      final source = File('lib/screens/notification_settings_screen.dart')
          .readAsStringSync();
      expect(source, contains('Alertes automatiques'));
      expect(source, contains('Résumé quotidien'));
      expect(source, contains('Alertes importantes'));
    });

    testWidgets('summary UI is prudent and contains no technical IDs',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DailySummaryScreen(
            loader: () async => const DailySummaryViewData(
              localDate: '2026-07-24',
              categoryCounts: {
                ProactiveAlertCategory.deadlinePassed: 2,
              },
              coverageState: DetectionCoverageKind.partial,
              omittedCount: 1,
              hasStaleInformation: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Résumé quotidien'), findsOneWidget);
      expect(find.text('Échéances dépassées'), findsOneWidget);
      expect(find.textContaining('Certaines informations'), findsOneWidget);
      expect(find.textContaining('incident-'), findsNothing);
      expect(find.textContaining('account-a'), findsNothing);
    });
  });
}

NotificationDeliveryDecision _decide(
  ProactiveNotificationPolicy policy,
  ProactiveDetectionSignal signal,
  DateTime now, {
  bool permissionEnabled = true,
}) =>
    const ProactiveNotificationPolicyEngine().decideSignal(
      policy: policy,
      signal: signal,
      history: const [],
      permission: _permission(now, enabled: permissionEnabled),
      notificationSettings: _notificationSettings(now),
      now: now,
    );

ProactiveNotificationPolicy _policy(
  DateTime now, {
  bool enabled = true,
  bool summary = true,
  bool critical = false,
  NotificationQuietHours? quiet,
}) {
  final categories = <ProactiveAlertCategory, AlertCategorySettings>{
    for (final category in ProactiveAlertCategory.values)
      category: AlertCategorySettings(
        enabled: category != ProactiveAlertCategory.potentialOmission,
        deliveryMode: NotificationDeliveryMode.immediateAndSummary,
        includeInDailySummary: true,
        allowImmediateDelivery: true,
        allowDuringQuietHours: true,
        criticalEligibility: {
          ProactiveAlertCategory.deadlineApproaching,
          ProactiveAlertCategory.deadlinePassed,
          ProactiveAlertCategory.objectivelyDelayed,
          ProactiveAlertCategory.structuredConflict,
        }.contains(category),
        cooldown: const Duration(hours: 12),
        dailyMaximum: 4,
        priority: 50,
        minimumConfidence: DetectionConfidenceLevel.strong,
        minimumEvidenceLevel: DetectionEvidenceLevel.explicit,
      ),
  };
  categories[ProactiveAlertCategory.potentialOmission] =
      AlertCategorySettings.restrictive();
  return ProactiveNotificationPolicy(
    enabled: enabled,
    categorySettings: categories,
    dailySummarySettings: DailySummarySettings(
      enabled: summary,
      localMinute: 18 * 60,
      timezoneId: 'Europe/Paris',
      weekendBehavior: DailySummaryWeekendBehavior.followSelectedDays,
      deferAfterQuietHours: true,
      includedCategories: categories.keys.toSet(),
    ),
    quietHours: quiet,
    pause: ProactiveNotificationPause.inactive(),
    criticalProductAlertPolicy: CriticalProductAlertPolicy(
      enabled: critical,
      allowDuringQuietHours: false,
      allowDuringTemporaryPause: false,
      maximumPerDay: 1,
      horizon: const Duration(hours: 6),
    ),
    rateLimitPolicy: NotificationRateLimitPolicy.restrictive(),
    timezoneId: 'Europe/Paris',
    changedAt: now,
    changeSource: ProactivePolicyChangeSource.explicitUserSetting,
    accountScopeId: 'account-a',
    policyRevision: 1,
    notificationPrivacyMode: NotificationPrivacyMode.genericOnly,
  );
}

ProactiveDetectionSignal _signal(
  DateTime now, {
  String id = 'one',
  ProactiveDetectionReason reason = ProactiveDetectionReason.deadlinePassed,
  ProactiveDetectorType detector = ProactiveDetectorType.deadline,
  DetectionConfidenceLevel confidence = DetectionConfidenceLevel.strong,
  DetectionCoverageKind coverage = DetectionCoverageKind.complete,
  DetectionTechnicalSeverity severity = DetectionTechnicalSeverity.attention,
}) =>
    ProactiveDetectionSignal(
      detectionId: id,
      accountScopeId: 'account-a',
      detectorType: detector,
      reasonCode: reason,
      state: ProactiveDetectionState.eligible,
      confidenceLevel: confidence,
      evidenceLevel: DetectionEvidenceLevel.explicit,
      evidence: [
        DetectionEvidence(
          sourceType: DetectionEvidenceSource.explicitDeadline,
          domain: LifeContextDomain.task,
          sourceId: 'task-$id',
          revision: 2,
          freshness: LifeContextFreshness.current,
          availability: LifeContextAvailability.available,
          certainty: DetectionEvidenceLevel.explicit,
          instant: now,
        ),
      ],
      sourceRevisions: {'task-$id': 2},
      detectedAt: now,
      validFrom: now.add(const Duration(minutes: 2)),
      validUntil: now.add(const Duration(hours: 12)),
      observedAt: now,
      replacementKey: 'incident-$id',
      incidentFingerprint: 'incident-$id',
      interactionDestination: NotificationDestinationType.home,
      policyVersion: 1,
      coverageState: coverage,
      technicalSeverity: severity,
    );

DetectionCoverageState _coverage() => DetectionCoverageState(
      kind: DetectionCoverageKind.complete,
      evaluatedDomains: const {LifeContextDomain.task},
      unavailableDomains: const {},
      staleDomains: const {},
      numberEvaluated: 2,
      numberTruncated: 0,
      evaluableCategories: ProactiveDetectorType.values.toSet(),
      nonEvaluableCategories: const {},
    );

NotificationPermissionState _permission(
  DateTime now, {
  bool enabled = true,
}) =>
    NotificationPermissionState(
      platform: NotificationPlatform.android,
      state: enabled
          ? NotificationPermissionStatus.authorized
          : NotificationPermissionStatus.denied,
      checkedAt: now,
      canRequest: !enabled,
      canOpenSettings: !enabled,
      notificationsEnabled: enabled,
    );

NotificationSettings _notificationSettings(DateTime now) =>
    NotificationSettings(
      accountScopeId: 'account-a',
      enabled: true,
      permissionPromptExplained: true,
      privacyMode: NotificationPrivacyMode.genericOnly,
      soundEnabled: false,
      vibrationEnabled: false,
      badgeEnabled: false,
      timezoneId: 'Europe/Paris',
      changedAt: now,
      source: NotificationSettingsSource.explicitUserSetting,
      policyRevision: 1,
    );

final class _PolicyRepository implements ProactiveNotificationPolicyRepository {
  final values = <String, ProactiveNotificationPolicy>{};

  @override
  Future<ProactiveNotificationPolicy?> load(String accountScopeId) async =>
      values[accountScopeId];

  @override
  Future<void> save(ProactiveNotificationPolicy policy) async {
    values[policy.accountScopeId] = policy;
  }
}

final class _SettingsRepository implements NotificationSettingsRepository {
  NotificationSettings? value;

  @override
  Future<NotificationSettings?> load(String accountScopeId) async => value;

  @override
  Future<void> save(NotificationSettings settings) async {
    value = settings;
  }
}

final class _PermissionGateway implements NotificationPermissionGateway {
  const _PermissionGateway(this.now);

  final DateTime now;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<NotificationPermissionState> read() async => _permission(now);

  @override
  Future<NotificationPermissionState> request() async => _permission(now);
}

final class _PlatformGateway implements LocalNotificationPlatformGateway {
  final scheduled = <LocalNotificationRequest>[];
  final cancelled = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedule({
    required LocalNotificationRequest request,
    required DateTime platformInstant,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {
    scheduled.add(request);
  }

  @override
  Future<void> showNow({
    required LocalNotificationRequest request,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {}

  @override
  Future<void> cancel(int platformNotificationId) async {
    cancelled.add(platformNotificationId);
    scheduled.removeWhere(
      (item) => item.platformNotificationId == platformNotificationId,
    );
  }

  @override
  Future<bool?> isChannelEnabled(String channelId) async => true;

  @override
  Future<Set<int>> pendingIds() async =>
      scheduled.map((item) => item.platformNotificationId).toSet();
}

final class _LocalRegistry implements LocalNotificationRegistry {
  NotificationRegistryState state = NotificationRegistryState(
    accountScopeId: 'account-a',
    entries: const [],
  );

  @override
  Future<NotificationRegistryState> load(String accountScopeId) async => state;

  @override
  Future<void> save(NotificationRegistryState value) async {
    state = value;
  }
}

final class _SignalRegistry implements ProactiveDetectionRegistry {
  _SignalRegistry(DateTime now)
      : state = ProactiveDetectionRegistryState(
          accountScopeId: 'account-a',
          signals: const [],
          updatedAt: now,
        );

  ProactiveDetectionRegistryState state;

  @override
  Future<ProactiveDetectionRegistryState> load(
    String accountScopeId,
  ) async =>
      state;

  @override
  Future<void> save(ProactiveDetectionRegistryState value) async {
    state = value;
  }
}

final class _DeliveryRegistry implements ProactiveNotificationDeliveryRegistry {
  _DeliveryRegistry(DateTime now)
      : state = ProactiveNotificationDeliveryState(
          accountScopeId: 'account-a',
          records: const [],
          updatedAt: now,
        );

  ProactiveNotificationDeliveryState state;

  @override
  Future<ProactiveNotificationDeliveryState> load(
    String accountScopeId,
  ) async =>
      state;

  @override
  Future<void> save(ProactiveNotificationDeliveryState value) async {
    state = value;
  }
}
