import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/priority/priority_models.dart';

final class PriorityCandidateAdapter {
  const PriorityCandidateAdapter();

  List<PriorityCandidate> fromProjection(
    LifeContextProjection projection, {
    required DateTime evaluatedAt,
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
          evaluatedAt.toUtc(),
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
    DateTime evaluatedAt,
  ) {
    final isStructuredConstraint =
        item.domain == LifeContextDomain.memory && item.type == 'constraint';
    if (item.domain == LifeContextDomain.memory && !isStructuredConstraint ||
        item.domain == LifeContextDomain.human ||
        item.domain == LifeContextDomain.identity) {
      return null;
    }
    final facts = {for (final fact in item.facts) fact.key: fact.value};
    final source = switch (item.domain) {
      LifeContextDomain.task => PrioritySourceDomain.task,
      LifeContextDomain.event => PrioritySourceDomain.event,
      LifeContextDomain.routine => PrioritySourceDomain.routine,
      LifeContextDomain.memory when isStructuredConstraint =>
        PrioritySourceDomain.constraint,
      _ => null,
    };
    if (source == null) return null;

    final rawStatus = facts[LifeContextProjectionFactKeys.status];
    final type = switch (source) {
      PrioritySourceDomain.task => PriorityCandidateType.task,
      PrioritySourceDomain.event =>
        facts[LifeContextProjectionFactKeys.actionRequired] == 'true'
            ? PriorityCandidateType.eventPreparation
            : PriorityCandidateType.eventCommitment,
      PrioritySourceDomain.routine
          when facts[LifeContextProjectionFactKeys.actionRequired] == 'true' &&
              _parseDate(facts[LifeContextProjectionFactKeys.start]) != null =>
        PriorityCandidateType.routineOccurrence,
      PrioritySourceDomain.constraint
          when item.confirmation == LifeContextConfirmation.confirmed &&
              rawStatus == 'active' &&
              _isActiveAt(item, evaluatedAt) =>
        PriorityCandidateType.constraint,
      _ => null,
    };
    if (type == null) return null;

    final status = switch (rawStatus) {
      'active' || null => PriorityCandidateStatus.active,
      'completed' => PriorityCandidateStatus.completed,
      'cancelled' => PriorityCandidateStatus.cancelled,
      'expired' => PriorityCandidateStatus.expired,
      'invalid' => PriorityCandidateStatus.invalid,
      'historical' => PriorityCandidateStatus.historical,
      'future' => PriorityCandidateStatus.future,
      'deleted' ||
      'rejected' ||
      'superseded' ||
      'obsolete' ||
      'archived' ||
      'proposed' =>
        PriorityCandidateStatus.invalid,
      _ when source == PrioritySourceDomain.constraint =>
        PriorityCandidateStatus.invalid,
      _ => PriorityCandidateStatus.active,
    };
    if ({
          PriorityCandidateStatus.completed,
          PriorityCandidateStatus.cancelled,
          PriorityCandidateStatus.expired,
          PriorityCandidateStatus.invalid,
        }.contains(status) ||
        item.confirmation == LifeContextConfirmation.rejected ||
        source == PrioritySourceDomain.constraint &&
            item.confirmation != LifeContextConfirmation.confirmed) {
      return null;
    }
    final rawDeadline = facts[LifeContextProjectionFactKeys.dueDate];
    final rawStart = facts[LifeContextProjectionFactKeys.start];
    final start = _parseDate(rawStart);
    final rawEnd = facts[LifeContextProjectionFactKeys.end];
    final factEnd = _parseDate(rawEnd);
    final itemEnd = item.validUntil?.toUtc();
    final eventEnd = factEnd == null
        ? itemEnd
        : itemEnd == null || factEnd.isBefore(itemEnd)
            ? factEnd
            : itemEnd;
    if (source == PrioritySourceDomain.event &&
        (start == null ||
            rawEnd != null && factEnd == null ||
            eventEnd == null ||
            !eventEnd.isAfter(start) ||
            !eventEnd.isAfter(evaluatedAt))) {
      return null;
    }
    final eventInProgress = source == PrioritySourceDomain.event &&
        !start!.isAfter(evaluatedAt) &&
        eventEnd!.isAfter(evaluatedAt);
    final deadline = _parseDate(rawDeadline) ??
        (source == PrioritySourceDomain.event && !eventInProgress
            ? start
            : null);
    if (rawDeadline != null && deadline == null ||
        source == PrioritySourceDomain.event &&
            (rawStart == null || _parseDate(rawStart) == null)) {
      return null;
    }
    final consequenceType =
        _consequenceType(facts[LifeContextProjectionFactKeys.consequenceType]);
    final consequenceLevel = _consequenceLevel(
        facts[LifeContextProjectionFactKeys.consequenceLevel]);
    if ((consequenceType == PriorityConsequenceType.unknown) !=
        (consequenceLevel == PriorityConsequenceLevel.unknown)) {
      return null;
    }
    return PriorityCandidate(
      id: 'priority:${source.name}:${item.provenance.sourceId}',
      accountScopeId: projection.accountScopeId,
      sourceDomain: source,
      sourceId: item.provenance.sourceId,
      type: type,
      status: status,
      deadline: deadline,
      temporalStart: start,
      createdAt: _parseDate(facts[LifeContextProjectionFactKeys.createdAt]),
      effortMinutes: _parsePositiveInt(
          facts[LifeContextProjectionFactKeys.durationMinutes]),
      flexibility: source == PrioritySourceDomain.event
          ? PriorityFlexibility.fixed
          : _flexibility(facts[LifeContextProjectionFactKeys.flexibility]),
      explicitImportance:
          _parseUnit(facts[LifeContextProjectionFactKeys.importance]),
      explicitUrgency: _parseUnit(facts[LifeContextProjectionFactKeys.urgency]),
      consequenceType: consequenceType,
      consequenceLevel: consequenceLevel,
      category: _category(facts[LifeContextProjectionFactKeys.category]),
      subjectEntityId: _validOptionalId(
          facts[LifeContextProjectionFactKeys.subjectEntityId]),
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

  bool _isActiveAt(LifeContextProjectionItem item, DateTime evaluatedAt) {
    final validFrom = item.validFrom?.toUtc();
    final validUntil = item.validUntil?.toUtc();
    if (validFrom != null &&
            validUntil != null &&
            validFrom.isAfter(validUntil) ||
        validFrom != null && validFrom.isAfter(evaluatedAt) ||
        validUntil != null && !evaluatedAt.isBefore(validUntil)) {
      return false;
    }
    return true;
  }

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

  String? _validOptionalId(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : null;

  PriorityConsequenceType _consequenceType(String? value) =>
      PriorityConsequenceType.values
          .where((item) => item.name == value)
          .firstOrNull ??
      PriorityConsequenceType.unknown;

  PriorityConsequenceLevel _consequenceLevel(String? value) =>
      PriorityConsequenceLevel.values
          .where((item) => item.name == value)
          .firstOrNull ??
      PriorityConsequenceLevel.unknown;

  PriorityCategory _category(String? value) =>
      PriorityCategory.values.where((item) => item.name == value).firstOrNull ??
      PriorityCategory.unknown;

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
