import '../models/proactive_detection.dart';
import '../models/proactive_notification_policy.dart';
import 'package:timezone/timezone.dart' as tz;
import 'daily_summary_builder.dart';
import 'proactive_detection_registry.dart';
import 'proactive_notification_policy_engine.dart';
import 'proactive_notification_policy_service.dart';

final class AttentionSourceLabels {
  const AttentionSourceLabels({
    this.eventTitles = const {},
    this.routineTitles = const {},
    this.taskTitles = const {},
  });

  final Map<String, String> eventTitles;
  final Map<String, String> routineTitles;
  final Map<String, String> taskTitles;
}

final class TaskAttentionViewData {
  const TaskAttentionViewData({
    required this.taskTitle,
    required this.category,
    required this.taskId,
  });

  final String taskTitle;
  final ProactiveAlertCategory category;
  final String taskId;
}

final class ConflictAttentionViewData {
  const ConflictAttentionViewData({
    required this.eventTitle,
    required this.routineTitle,
    required this.targetDate,
    this.eventId,
    this.routineId,
  });

  final String eventTitle;
  final String routineTitle;
  final DateTime? targetDate;
  final String? eventId;
  final String? routineId;
}

typedef AttentionSourceLabelLoader = Future<AttentionSourceLabels> Function(
  String accountScopeId,
);

final class DailySummaryViewData {
  const DailySummaryViewData({
    required this.localDate,
    required this.categoryCounts,
    required this.coverageState,
    required this.omittedCount,
    required this.hasStaleInformation,
    this.categoryTargetDates = const {},
    this.conflicts = const [],
    this.tasks = const [],
  });

  final String localDate;
  final Map<ProactiveAlertCategory, int> categoryCounts;
  final DetectionCoverageKind coverageState;
  final int omittedCount;
  final bool hasStaleInformation;
  final Map<ProactiveAlertCategory, DateTime> categoryTargetDates;
  final List<ConflictAttentionViewData> conflicts;
  final List<TaskAttentionViewData> tasks;
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
    this.loadSourceLabels,
  });

  final ProactiveDetectionRegistry registry;
  final ProactiveNotificationPolicyService policyService;
  final String? Function() currentAccountScopeId;
  final DailySummaryBuilder builder;
  final DateTime Function() now;
  final AttentionSourceLabelLoader? loadSourceLabels;

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
    final targetDates = _targetDates(active);
    final conflicts = await _conflictDetails(scope, active);
    final tasks = await _taskDetails(scope, active);
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
        categoryTargetDates: targetDates,
        conflicts: conflicts,
        tasks: tasks,
      );
    }
    return DailySummaryViewData(
      localDate: snapshot.localDate,
      categoryCounts: snapshot.categoryCounts,
      coverageState: snapshot.coverageState,
      omittedCount: snapshot.omittedCount,
      hasStaleInformation:
          snapshot.coverageState != DetectionCoverageKind.complete,
      categoryTargetDates: targetDates,
      conflicts: conflicts,
      tasks: tasks,
    );
  }

  Future<List<TaskAttentionViewData>> _taskDetails(
    String scope,
    List<ProactiveDetectionSignal> signals,
  ) async {
    final taskSignals = signals
        .where(
          (item) =>
              item.isActiveAttention &&
              {
                ProactiveDetectionReason.deadlineApproaching,
                ProactiveDetectionReason.deadlinePassed,
                ProactiveDetectionReason.objectivelyDelayed,
              }.contains(item.reasonCode),
        )
        .take(20)
        .toList(growable: false);
    if (taskSignals.isEmpty) return const [];
    AttentionSourceLabels labels = const AttentionSourceLabels();
    final loader = loadSourceLabels;
    if (loader != null) {
      try {
        labels = await loader(scope);
      } on Object {
        // A safe generic title remains available if labels cannot be loaded.
      }
    }
    final byTask = <String, TaskAttentionViewData>{};
    for (final signal in taskSignals) {
      final evidence = signal.evidence.where(
        (item) => item.domain.name == 'task',
      );
      final taskId = evidence.isNotEmpty
          ? evidence.first.sourceId
          : signal.sourceRevisions.keys.firstOrNull;
      if (taskId == null || taskId.trim().isEmpty) continue;
      byTask[taskId] = TaskAttentionViewData(
        taskTitle: _safeLabel(labels.taskTitles[taskId], 'une tâche'),
        category: ProactiveNotificationPolicyEngine.categoryForSignal(signal),
        taskId: taskId,
      );
    }
    return byTask.values.toList(growable: false);
  }

  Future<List<ConflictAttentionViewData>> _conflictDetails(
    String scope,
    List<ProactiveDetectionSignal> signals,
  ) async {
    final conflictSignals = signals
        .where(
          (item) =>
              item.isActiveAttention &&
              item.reasonCode == ProactiveDetectionReason.structuredConflict,
        )
        .take(20)
        .toList(growable: false);
    if (conflictSignals.isEmpty) return const [];
    AttentionSourceLabels labels = const AttentionSourceLabels();
    final loader = loadSourceLabels;
    if (loader != null) {
      try {
        labels = await loader(scope);
      } on Object {
        // The attention center keeps a safe generic fallback when a domain
        // label is temporarily unavailable.
      }
    }
    return conflictSignals.map((signal) {
      final eventEvidence = signal.evidence
          .where((item) => item.domain.name == 'event')
          .toList(growable: false);
      final routineEvidence = signal.evidence.where(
        (item) => item.domain.name == 'routine',
      );
      final eventId =
          eventEvidence.isEmpty ? null : eventEvidence.first.sourceId;
      final secondEventId =
          eventEvidence.length < 2 ? null : eventEvidence[1].sourceId;
      final occurrenceId =
          routineEvidence.isEmpty ? null : routineEvidence.first.sourceId;
      final routineId = occurrenceId == null ? null : _routineId(occurrenceId);
      final starts = signal.evidence
          .map((item) => item.intervalStart)
          .whereType<DateTime>();
      final targetDate = starts.isEmpty
          ? null
          : starts.reduce((a, b) => a.isBefore(b) ? a : b);
      return ConflictAttentionViewData(
        eventTitle: _safeLabel(
          eventId == null ? null : labels.eventTitles[eventId],
          'un rendez-vous',
        ),
        routineTitle: _safeLabel(
          routineId == null
              ? (secondEventId == null
                  ? null
                  : labels.eventTitles[secondEventId])
              : labels.routineTitles[routineId],
          routineId == null ? 'un autre rendez-vous' : 'une routine',
        ),
        targetDate: targetDate,
        eventId: eventId,
        routineId: routineId,
      );
    }).toList(growable: false);
  }

  static String _routineId(String occurrenceId) {
    final match = RegExp(r'^(.*):\d{4}-\d{2}-\d{2}$').firstMatch(occurrenceId);
    return match?.group(1) ?? occurrenceId;
  }

  static String _safeLabel(String? value, String fallback) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  static Map<ProactiveAlertCategory, DateTime> _targetDates(
    List<ProactiveDetectionSignal> signals,
  ) {
    final result = <ProactiveAlertCategory, DateTime>{};
    for (final signal in signals.where((item) => item.isActiveAttention)) {
      final starts = signal.evidence
          .map((item) => item.intervalStart)
          .whereType<DateTime>();
      if (starts.isEmpty) continue;
      final earliest = starts.reduce((a, b) => a.isBefore(b) ? a : b);
      final category =
          ProactiveNotificationPolicyEngine.categoryForSignal(signal);
      final previous = result[category];
      if (previous == null || earliest.isBefore(previous)) {
        result[category] = earliest;
      }
    }
    return Map.unmodifiable(result);
  }
}
