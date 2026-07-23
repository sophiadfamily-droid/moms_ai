import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/priority/priority_models.dart';

final class PriorityCandidateAdapter {
  const PriorityCandidateAdapter();

  List<PriorityCandidate> fromProjection(
    LifeContextProjection projection, {
    Map<String, List<PriorityDirectImpact>> directImpactsByItemId = const {},
  }) {
    if (projection.accountScopeId.trim().isEmpty) {
      throw const PriorityException('priority_projection_scope_missing');
    }
    final result = <PriorityCandidate>[];
    for (final section in projection.sections) {
      for (final item in section.items) {
        final candidate = _candidate(
          projection,
          item,
          directImpactsByItemId[item.id] ?? const [],
        );
        if (candidate != null) result.add(candidate);
      }
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(result);
  }

  List<PriorityDirectImpact> directImpactsFromConsequences(
    Iterable<LifeContextTechnicalConsequence> consequences, {
    required String sourceSnapshotId,
  }) {
    final result = <PriorityDirectImpact>[];
    final seen = <String>{};
    for (final consequence in consequences) {
      if (consequence.depth != 1 ||
          consequence.confirmation == LifeContextConfirmation.rejected ||
          !seen.add(
            '${consequence.triggerNodeId}:${consequence.affectedNodeId}:'
            '${consequence.impactType.name}',
          )) {
        continue;
      }
      result.add(
        PriorityDirectImpact(
          id: 'impact:${consequence.triggerNodeId}:'
              '${consequence.affectedNodeId}:${consequence.impactType.name}',
          type: PriorityImpactType.technicalConsequence,
          depth: 1,
          confirmation: consequence.confirmation,
          provenance: PriorityProvenance(
            sourceSnapshotId: sourceSnapshotId,
            sourceItemId: consequence.triggerNodeId,
            sourceKind: 'lifeContextConsequence',
            ruleId: consequence.ruleId,
          ),
        ),
      );
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(result);
  }

  PriorityCandidate? _candidate(
    LifeContextProjection projection,
    LifeContextProjectionItem item,
    List<PriorityDirectImpact> impacts,
  ) {
    if (item.domain == LifeContextDomain.memory ||
        item.domain == LifeContextDomain.human ||
        item.domain == LifeContextDomain.identity) {
      return null;
    }
    final facts = {for (final fact in item.facts) fact.key: fact.value};
    final source = switch (item.domain) {
      LifeContextDomain.task => PrioritySourceDomain.task,
      LifeContextDomain.event => PrioritySourceDomain.event,
      LifeContextDomain.routine => PrioritySourceDomain.routine,
      _ => null,
    };
    if (source == null) return null;

    final type = switch (source) {
      PrioritySourceDomain.task => PriorityCandidateType.task,
      PrioritySourceDomain.event
          when facts[LifeContextProjectionFactKeys.actionRequired] == 'true' =>
        PriorityCandidateType.eventPreparation,
      PrioritySourceDomain.routine
          when facts[LifeContextProjectionFactKeys.actionRequired] == 'true' &&
              _parseDate(facts[LifeContextProjectionFactKeys.start]) != null =>
        PriorityCandidateType.routineOccurrence,
      _ => null,
    };
    if (type == null) return null;

    final status = switch (facts[LifeContextProjectionFactKeys.status]) {
      'completed' => PriorityCandidateStatus.completed,
      'historical' => PriorityCandidateStatus.historical,
      'future' => PriorityCandidateStatus.future,
      _ => PriorityCandidateStatus.active,
    };
    if (status == PriorityCandidateStatus.completed ||
        item.confirmation == LifeContextConfirmation.rejected) {
      return null;
    }
    return PriorityCandidate(
      id: 'priority:${source.name}:${item.provenance.sourceId}',
      accountScopeId: projection.accountScopeId,
      sourceDomain: source,
      sourceId: item.provenance.sourceId,
      type: type,
      status: status,
      deadline: _parseDate(facts[LifeContextProjectionFactKeys.dueDate]) ??
          (type == PriorityCandidateType.eventPreparation
              ? _parseDate(facts[LifeContextProjectionFactKeys.start])
              : null),
      temporalStart: _parseDate(facts[LifeContextProjectionFactKeys.start]),
      effortMinutes: _parsePositiveInt(
          facts[LifeContextProjectionFactKeys.durationMinutes]),
      flexibility:
          _flexibility(facts[LifeContextProjectionFactKeys.flexibility]),
      explicitImportance:
          _parseUnit(facts[LifeContextProjectionFactKeys.importance]),
      explicitUrgency: _parseUnit(facts[LifeContextProjectionFactKeys.urgency]),
      directImpacts: impacts.where((impact) => impact.depth == 1).toList(),
      confirmation: item.confirmation,
      freshness: _freshness(item.freshness),
      provenance: PriorityProvenance(
        sourceSnapshotId: projection.sourceSnapshotId,
        sourceItemId: item.id,
        sourceKind: item.provenance.sourceKind.name,
        ruleId: item.provenance.ruleId,
      ),
      sourceRevision:
          int.tryParse(facts[LifeContextProjectionFactKeys.revision] ?? ''),
      syncStatus: facts[LifeContextProjectionFactKeys.syncStatus] ?? 'unknown',
    );
  }

  DateTime? _parseDate(String? value) =>
      value == null ? null : DateTime.tryParse(value)?.toUtc();

  int? _parsePositiveInt(String? value) {
    final parsed = value == null ? null : int.tryParse(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  double? _parseUnit(String? value) {
    final parsed = value == null ? null : double.tryParse(value);
    return parsed != null && parsed.isFinite && parsed >= 0 && parsed <= 1
        ? parsed
        : null;
  }

  PriorityFlexibility _flexibility(String? value) => switch (value) {
        'fixed' => PriorityFlexibility.fixed,
        'low' => PriorityFlexibility.low,
        'flexible' => PriorityFlexibility.flexible,
        'veryFlexible' => PriorityFlexibility.veryFlexible,
        _ => PriorityFlexibility.unknown,
      };

  PriorityFreshness _freshness(LifeContextFreshness value) => switch (value) {
        LifeContextFreshness.current => PriorityFreshness.current,
        LifeContextFreshness.stale => PriorityFreshness.stale,
        LifeContextFreshness.unknown => PriorityFreshness.unknown,
      };
}
