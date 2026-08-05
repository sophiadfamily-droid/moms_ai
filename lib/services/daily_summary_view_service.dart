import '../models/proactive_detection.dart';
import '../models/proactive_notification_policy.dart';
import 'package:timezone/timezone.dart' as tz;
import 'daily_summary_builder.dart';
import 'proactive_detection_registry.dart';
import 'proactive_notification_policy_engine.dart';
import 'proactive_notification_policy_service.dart';

final class DailySummaryViewData {
  const DailySummaryViewData({
    required this.localDate,
    required this.categoryCounts,
    required this.coverageState,
    required this.omittedCount,
    required this.hasStaleInformation,
  });

  final String localDate;
  final Map<ProactiveAlertCategory, int> categoryCounts;
  final DetectionCoverageKind coverageState;
  final int omittedCount;
  final bool hasStaleInformation;
}

/// Read-only presentation boundary. The snapshot remains a projection, never
/// a business source, and no technical identifier is exposed to the widget.
final class DailySummaryViewService {
  const DailySummaryViewService({
    required this.registry,
    required this.policyService,
    required this.currentAccountScopeId,
    this.builder = const DailySummaryBuilder(),
    this.now = DateTime.now,
  });

  final ProactiveDetectionRegistry registry;
  final ProactiveNotificationPolicyService policyService;
  final String? Function() currentAccountScopeId;
  final DailySummaryBuilder builder;
  final DateTime Function() now;

  Future<DailySummaryViewData?> load() async {
    final scope = currentAccountScopeId();
    if (scope == null || scope.trim().isEmpty) return null;
    final state = await registry.load(scope);
    final policy = await policyService.load();
    final active = state.signals
        .where(
          (item) =>
              item.state != ProactiveDetectionState.resolved &&
              item.state != ProactiveDetectionState.expired,
        )
        .toList();
    final coverageKind = active.isEmpty
        ? DetectionCoverageKind.partial
        : active.any(
            (item) => item.coverageState != DetectionCoverageKind.complete,
          )
            ? DetectionCoverageKind.partial
            : DetectionCoverageKind.complete;
    final coverage = DetectionCoverageState(
      kind: coverageKind,
      evaluatedDomains: active
          .expand((item) => item.evidence.map((evidence) => evidence.domain))
          .toSet(),
      unavailableDomains: const {},
      staleDomains: active
          .where((item) => item.coverageState == DetectionCoverageKind.stale)
          .expand((item) => item.evidence.map((evidence) => evidence.domain))
          .toSet(),
      numberEvaluated: active.length,
      numberTruncated: 0,
      evaluableCategories: active.map((item) => item.detectorType).toSet(),
      nonEvaluableCategories: const {},
    );
    final result = builder.build(
      accountScopeId: scope,
      signals: active,
      coverage: coverage,
      policy: policy,
      now: now(),
    );
    final snapshot = result.snapshot;
    if (snapshot == null) {
      if (active.isEmpty) return null;
      final current = now().toUtc();
      final byIncident = <String, ProactiveDetectionSignal>{};
      for (final signal in active) {
        if (signal.isActiveAttention && signal.validUntil.isAfter(current)) {
          byIncident[signal.incidentFingerprint] = signal;
        }
      }
      final selected = byIncident.values
          .take(policy.rateLimitPolicy.maximumSummaryItems)
          .toList(growable: false);
      if (selected.isEmpty) return null;
      final counts = <ProactiveAlertCategory, int>{};
      for (final signal in selected) {
        final category =
            ProactiveNotificationPolicyEngine.categoryForSignal(signal);
        counts[category] = (counts[category] ?? 0) + 1;
      }
      final location = tz.getLocation(policy.dailySummarySettings.timezoneId);
      final local = tz.TZDateTime.from(current, location);
      return DailySummaryViewData(
        localDate: '${local.year.toString().padLeft(4, '0')}-'
            '${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')}',
        categoryCounts: counts,
        coverageState: coverage.kind,
        omittedCount: byIncident.length - selected.length,
        hasStaleInformation: coverage.kind != DetectionCoverageKind.complete,
      );
    }
    return DailySummaryViewData(
      localDate: snapshot.localDate,
      categoryCounts: snapshot.categoryCounts,
      coverageState: snapshot.coverageState,
      omittedCount: snapshot.omittedCount,
      hasStaleInformation:
          snapshot.coverageState != DetectionCoverageKind.complete,
    );
  }
}
