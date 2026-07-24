import 'package:timezone/timezone.dart' as tz;

import '../models/proactive_detection.dart';
import '../models/proactive_notification_policy.dart';
import 'proactive_notification_policy_engine.dart';

final class DailySummaryBuildResult {
  const DailySummaryBuildResult({
    required this.snapshot,
    required this.code,
  });

  final DailySummarySnapshot? snapshot;
  final String code;
}

/// Pure, bounded summary projection. It does not generate prose or evidence.
final class DailySummaryBuilder {
  const DailySummaryBuilder();

  DailySummaryBuildResult build({
    required String accountScopeId,
    required List<ProactiveDetectionSignal> signals,
    required DetectionCoverageState coverage,
    required ProactiveNotificationPolicy policy,
    required DateTime now,
    DailySummarySnapshot? previous,
  }) {
    policy.validate();
    if (!policy.dailySummarySettings.enabled ||
        policy.accountScopeId != accountScopeId) {
      return const DailySummaryBuildResult(
        snapshot: null,
        code: 'daily_summary_disabled',
      );
    }
    final current = now.toUtc();
    final byIncident = <String, ProactiveDetectionSignal>{};
    for (final signal in signals) {
      if (signal.accountScopeId != accountScopeId ||
          !signal.isNotifiable ||
          !signal.validUntil.isAfter(current)) {
        continue;
      }
      final category =
          ProactiveNotificationPolicyEngine.categoryForSignal(signal);
      final settings = policy.categorySettings[category]!;
      if (!settings.enabled ||
          !settings.includeInDailySummary ||
          !policy.dailySummarySettings.includedCategories.contains(category)) {
        continue;
      }
      final existing = byIncident[signal.incidentFingerprint];
      if (existing == null || _rank(signal) > _rank(existing)) {
        byIncident[signal.incidentFingerprint] = signal;
      }
    }
    final ordered = byIncident.values.toList()
      ..sort((a, b) {
        final categoryA =
            ProactiveNotificationPolicyEngine.categoryForSignal(a);
        final categoryB =
            ProactiveNotificationPolicyEngine.categoryForSignal(b);
        final priority = policy.categorySettings[categoryB]!.priority
            .compareTo(policy.categorySettings[categoryA]!.priority);
        if (priority != 0) return priority;
        final severity = _rank(b).compareTo(_rank(a));
        return severity != 0
            ? severity
            : a.incidentFingerprint.compareTo(b.incidentFingerprint);
      });
    if (ordered.isEmpty) {
      return const DailySummaryBuildResult(
        snapshot: null,
        code: 'daily_summary_empty',
      );
    }
    final selected =
        ordered.take(policy.rateLimitPolicy.maximumSummaryItems).toList();
    final location = tz.getLocation(policy.dailySummarySettings.timezoneId);
    final local = tz.TZDateTime.from(current, location);
    final localDate = '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final counts = <ProactiveAlertCategory, int>{};
    final revisions = <String, int>{};
    for (final signal in selected) {
      final category =
          ProactiveNotificationPolicyEngine.categoryForSignal(signal);
      counts[category] = (counts[category] ?? 0) + 1;
      for (final entry in signal.sourceRevisions.entries) {
        revisions[entry.key] = entry.value;
      }
    }
    final highest = selected
        .map((item) => item.technicalSeverity)
        .reduce((a, b) => _severityRank(a) >= _severityRank(b) ? a : b);
    final warnings = <ProactivePolicyWarning>{
      if (coverage.kind != DetectionCoverageKind.complete)
        ProactivePolicyWarning.partialCoverage,
    };
    return DailySummaryBuildResult(
      snapshot: DailySummarySnapshot(
        summaryId: 'summary-$accountScopeId-$localDate',
        accountScopeId: accountScopeId,
        localDate: localDate,
        timezoneId: policy.dailySummarySettings.timezoneId,
        generatedAt: current,
        coverageState: coverage.kind,
        sourceRevisions: revisions,
        itemReferences:
            selected.map((item) => item.detectionId).toList(growable: false),
        categoryCounts: counts,
        highestTechnicalSeverity: highest,
        omittedCount: ordered.length - selected.length,
        resolvedSinceLastSummaryCount: previous == null
            ? 0
            : previous.itemReferences
                .where(
                  (item) =>
                      !selected.any((signal) => signal.detectionId == item),
                )
                .length,
        warningCodes: warnings,
        expiresAt: current.add(const Duration(days: 1)),
        replacementKey: 'n3-daily-summary',
        status: DailySummaryStatus.built,
      ),
      code: 'daily_summary_built',
    );
  }

  static int _rank(ProactiveDetectionSignal signal) =>
      _severityRank(signal.technicalSeverity) * 10 +
      switch (signal.reasonCode) {
        ProactiveDetectionReason.structuredConflict => 5,
        ProactiveDetectionReason.deadlinePassed => 4,
        ProactiveDetectionReason.objectivelyDelayed => 3,
        ProactiveDetectionReason.deadlineApproaching => 2,
        ProactiveDetectionReason.potentialOmission => 1,
      };

  static int _severityRank(DetectionTechnicalSeverity severity) =>
      switch (severity) {
        DetectionTechnicalSeverity.information => 1,
        DetectionTechnicalSeverity.attention => 2,
        DetectionTechnicalSeverity.important => 3,
      };
}
