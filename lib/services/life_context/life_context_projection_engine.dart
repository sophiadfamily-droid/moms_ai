import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/life_context/life_context_snapshot.dart';

/// The only LC.3 construction boundary.
///
/// This pure projection reads one LC.1 snapshot and, when needed, its matching
/// LC.2 graph. It never loads, writes, persists, logs, or calls a model API.
final class LifeContextProjectionEngine {
  LifeContextProjectionEngine({
    EntityIdGenerator projectionIdGenerator = const UuidV7EntityIdGenerator(),
  }) : _projectionIdGenerator = projectionIdGenerator;

  final EntityIdGenerator _projectionIdGenerator;

  LifeContextProjection build({
    required LifeContextSnapshot snapshot,
    LifeContextGraph? graph,
    required LifeContextConsumerContract contract,
  }) {
    snapshot.validateCanonical();
    contract.validate();
    final scope = snapshot.accountScopeId!;
    if (graph != null) {
      graph.validate();
      if (graph.accountScopeId != scope ||
          graph.snapshotId != snapshot.snapshotId) {
        throw const LifeContextProjectionException(
          'projection_source_mismatch',
        );
      }
    }

    final sourceMetadata = <LifeContextDomain, LifeContextSourceMetadata>{
      LifeContextDomain.human: snapshot.human!.metadata,
      LifeContextDomain.identity: snapshot.identityDomain!.metadata,
      LifeContextDomain.event: snapshot.eventDomain!.metadata,
      LifeContextDomain.task: snapshot.taskDomain!.metadata,
      LifeContextDomain.routine: snapshot.routineDomain!.metadata,
      LifeContextDomain.memory: snapshot.memoryDomain!.metadata,
    };
    _validateRequiredDomains(sourceMetadata, contract);
    _validateFreshness(sourceMetadata, contract);

    final candidates =
        <LifeContextProjectionSectionType, List<LifeContextProjectionItem>>{
      LifeContextProjectionSectionType.human:
          _humanCandidates(snapshot, contract),
      LifeContextProjectionSectionType.identity:
          _identityCandidates(snapshot, contract),
      LifeContextProjectionSectionType.event:
          _eventCandidates(snapshot, contract),
      LifeContextProjectionSectionType.task:
          _taskCandidates(snapshot, contract),
      LifeContextProjectionSectionType.routine:
          _routineCandidates(snapshot, contract),
      LifeContextProjectionSectionType.memory:
          _memoryCandidates(snapshot, contract),
      LifeContextProjectionSectionType.relation:
          _relationCandidates(snapshot, graph, contract),
    };

    var globalRemaining = contract.globalBudget;
    var totalUsed = 0;
    var totalOmitted = 0;
    var totalSelected = 0;
    final warnings = <String>{};
    final sections = <LifeContextProjectionSection>[];

    for (final sectionType in LifeContextProjectionSectionType.values) {
      if (!contract.allowedSections.contains(sectionType)) continue;
      final metadata = _metadataFor(sectionType, sourceMetadata, graph);
      final sectionBudget = contract.sectionBudgets[sectionType]!;
      final selected = <LifeContextProjectionItem>[];
      var sectionUsed = 0;
      var omitted = 0;
      final source = candidates[sectionType]!
          .where(
            (item) =>
                (contract.includeFuture ||
                    item.validFrom == null ||
                    !item.validFrom!.isAfter(snapshot.generatedAt)) &&
                (contract.includeHistorical ||
                    item.validUntil == null ||
                    !item.validUntil!.isBefore(snapshot.generatedAt)),
          )
          .toList()
        ..sort(_candidateOrder);
      for (final item in source) {
        if (totalSelected >= contract.maxItems ||
            item.budgetCost > sectionBudget - sectionUsed ||
            item.budgetCost > globalRemaining) {
          omitted++;
          continue;
        }
        selected.add(item);
        sectionUsed += item.budgetCost;
        globalRemaining -= item.budgetCost;
        totalUsed += item.budgetCost;
        totalSelected++;
      }
      totalOmitted += omitted;
      if (omitted > 0) warnings.add('projection_truncated');
      final availability = metadata?.availability ??
          (graph == null
              ? LifeContextAvailability.unsupported
              : LifeContextAvailability.available);
      final freshness = metadata?.freshness ?? LifeContextFreshness.current;
      final warningCode = _availabilityWarning(availability, freshness);
      if (warningCode != null) warnings.add(warningCode);
      sections.add(
        LifeContextProjectionSection(
          type: sectionType,
          availability: availability,
          freshness: freshness,
          items: selected,
          budgetLimit: sectionBudget,
          budgetUsed: sectionUsed,
          omittedCount: omitted,
          truncated: omitted > 0,
          warningCode: warningCode,
        ),
      );
    }

    final partial = warnings.isNotEmpty ||
        sections.any(
          (section) => {
            LifeContextAvailability.unavailable,
            LifeContextAvailability.corrupted,
            LifeContextAvailability.unsupported,
            LifeContextAvailability.accountMismatch,
          }.contains(section.availability),
        );
    if (partial && !contract.allowPartial) {
      throw const LifeContextProjectionException(
        'partial_projection_not_allowed',
      );
    }
    return LifeContextProjection(
      projectionId: _projectionIdGenerator.generate(),
      sourceSnapshotId: snapshot.snapshotId!,
      accountScopeId: scope,
      purpose: contract.purpose,
      generatedAt: snapshot.generatedAt,
      state: partial
          ? LifeContextProjectionState.partial
          : LifeContextProjectionState.complete,
      budgetRequested: contract.globalBudget,
      budgetUsed: totalUsed,
      sections: sections,
      omittedCount: totalOmitted,
      warningCodes: warnings.toList(),
    );
  }

  void _validateRequiredDomains(
    Map<LifeContextDomain, LifeContextSourceMetadata> metadata,
    LifeContextConsumerContract contract,
  ) {
    for (final domain in contract.requiredDomains) {
      final source = metadata[domain]!;
      if ({
        LifeContextAvailability.unavailable,
        LifeContextAvailability.corrupted,
        LifeContextAvailability.unsupported,
        LifeContextAvailability.accountMismatch,
      }.contains(source.availability)) {
        throw const LifeContextProjectionException(
          'required_projection_domain_unavailable',
        );
      }
      if (!contract.allowStale &&
          (source.freshness == LifeContextFreshness.stale ||
              source.availability == LifeContextAvailability.availableStale)) {
        throw const LifeContextProjectionException(
          'stale_projection_domain_not_allowed',
        );
      }
    }
  }

  void _validateFreshness(
    Map<LifeContextDomain, LifeContextSourceMetadata> metadata,
    LifeContextConsumerContract contract,
  ) {
    if (contract.allowStale) return;
    final allowedDomains = {
      if (contract.allowedSections
          .contains(LifeContextProjectionSectionType.human))
        LifeContextDomain.human,
      if (contract.allowedSections
          .contains(LifeContextProjectionSectionType.identity))
        LifeContextDomain.identity,
      if (contract.allowedSections
          .contains(LifeContextProjectionSectionType.event))
        LifeContextDomain.event,
      if (contract.allowedSections
          .contains(LifeContextProjectionSectionType.task))
        LifeContextDomain.task,
      if (contract.allowedSections
          .contains(LifeContextProjectionSectionType.routine))
        LifeContextDomain.routine,
      if (contract.allowedSections
          .contains(LifeContextProjectionSectionType.memory))
        LifeContextDomain.memory,
    };
    for (final domain in allowedDomains) {
      final source = metadata[domain]!;
      if (source.freshness == LifeContextFreshness.stale ||
          source.availability == LifeContextAvailability.availableStale) {
        throw const LifeContextProjectionException(
          'stale_projection_domain_not_allowed',
        );
      }
    }
  }

  List<LifeContextProjectionItem> _humanCandidates(
    LifeContextSnapshot snapshot,
    LifeContextConsumerContract contract,
  ) {
    final section = snapshot.human!;
    final result = <LifeContextProjectionItem>[];
    if (contract.purpose == LifeContextConsumerPurpose.conversation) {
      for (final person in section.persons) {
        if (person.status != 'active' || person.id != section.primaryPersonId) {
          continue;
        }
        final facts = <LifeContextProjectionFact>[
          _fact(
            LifeContextProjectionFactKeys.status,
            person.status,
            LifeContextSensitivityLevel.publicTechnical,
          ),
          if (person.displayName != null)
            _fact(
              LifeContextProjectionFactKeys.displayName,
              person.displayName!,
              LifeContextSensitivityLevel.ordinaryPersonal,
              contract: contract,
            ),
        ];
        _addAllowed(
          result,
          _item(
            snapshot,
            section.metadata,
            person.id,
            LifeContextDomain.human,
            'person',
            facts,
            _confirmation(person.confirmation),
          ),
          contract,
        );
      }
      for (final household in section.households) {
        _addAllowed(
          result,
          _recordItem(
            snapshot,
            section.metadata,
            household,
            'household',
            LifeContextSensitivityLevel.ordinaryPersonal,
            contract,
          ),
          contract,
        );
      }
      for (final residence in section.residences) {
        _addAllowed(
          result,
          _recordItem(
            snapshot,
            section.metadata,
            residence,
            'residence',
            LifeContextSensitivityLevel.privatePersonal,
            contract,
          ),
          contract,
        );
      }
    }
    for (final responsibility in section.responsibilities) {
      _addAllowed(
        result,
        _recordItem(
          snapshot,
          section.metadata,
          responsibility,
          'responsibility',
          LifeContextSensitivityLevel.privatePersonal,
          contract,
        ),
        contract,
      );
    }
    return result;
  }

  List<LifeContextProjectionItem> _identityCandidates(
    LifeContextSnapshot snapshot,
    LifeContextConsumerContract contract,
  ) {
    if (contract.purpose != LifeContextConsumerPurpose.conversation) {
      return const [];
    }
    final section = snapshot.identityDomain!;
    return section.links
        .map(
          (link) => _item(
            snapshot,
            section.metadata,
            link.entityId,
            LifeContextDomain.identity,
            'identityLink',
            [
              _fact(
                LifeContextProjectionFactKeys.status,
                link.confirmed ? 'confirmed' : 'needsConfirmation',
                LifeContextSensitivityLevel.publicTechnical,
              ),
            ],
            link.confirmed
                ? LifeContextConfirmation.confirmed
                : LifeContextConfirmation.needsConfirmation,
          ),
        )
        .where((item) => _isAllowed(item, contract))
        .toList();
  }

  List<LifeContextProjectionItem> _eventCandidates(
    LifeContextSnapshot snapshot,
    LifeContextConsumerContract contract,
  ) {
    final section = snapshot.eventDomain!;
    final lower = snapshot.generatedAt.subtract(contract.pastWindow);
    final upper = snapshot.generatedAt.add(contract.futureWindow);
    final result = <LifeContextProjectionItem>[];
    for (final event in section.events) {
      final start = DateTime.tryParse(event.startDateTimeIso)?.toUtc();
      if (start == null || start.isBefore(lower) || start.isAfter(upper)) {
        continue;
      }
      final facts = <LifeContextProjectionFact>[
        _fact(
          LifeContextProjectionFactKeys.start,
          event.startDateTimeIso,
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.end,
          event.endDateTimeIso,
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.durationMinutes,
          '${event.durationMinutes}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.travelGoMinutes,
          '${event.travelGoMinutes}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.travelBackMinutes,
          '${event.travelBackMinutes}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.marginMinutes,
          '${event.marginMinutes}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        if (event.recurringType.isNotEmpty)
          _fact(
            LifeContextProjectionFactKeys.recurringType,
            event.recurringType,
            LifeContextSensitivityLevel.publicTechnical,
          ),
        _fact(
          LifeContextProjectionFactKeys.syncStatus,
          event.syncStatus,
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.revision,
          '${event.revision}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        if (contract.purpose == LifeContextConsumerPurpose.conversation &&
            contract.maxTextLength > 0)
          _fact(
            LifeContextProjectionFactKeys.title,
            event.title,
            LifeContextSensitivityLevel.ordinaryPersonal,
            contract: contract,
          ),
      ];
      _addAllowed(
        result,
        _item(
          snapshot,
          section.metadata,
          event.id,
          LifeContextDomain.event,
          'event',
          facts,
          LifeContextConfirmation.confirmed,
          validFrom: start,
          validUntil: DateTime.tryParse(event.endDateTimeIso)?.toUtc(),
        ),
        contract,
      );
    }
    return result;
  }

  List<LifeContextProjectionItem> _taskCandidates(
    LifeContextSnapshot snapshot,
    LifeContextConsumerContract contract,
  ) {
    if (contract.purpose != LifeContextConsumerPurpose.conversation) {
      return const [];
    }
    final section = snapshot.taskDomain!;
    final result = <LifeContextProjectionItem>[];
    for (final task in section.tasks) {
      if (task.isCompleted && !contract.includeHistorical) continue;
      final facts = <LifeContextProjectionFact>[
        _fact(
          LifeContextProjectionFactKeys.status,
          task.isCompleted ? 'completed' : 'active',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        if (task.dueDate != null)
          _fact(
            LifeContextProjectionFactKeys.dueDate,
            task.dueDate!,
            LifeContextSensitivityLevel.publicTechnical,
          ),
        if (contract.maxTextLength > 0)
          _fact(
            LifeContextProjectionFactKeys.title,
            task.title,
            LifeContextSensitivityLevel.ordinaryPersonal,
            contract: contract,
          ),
      ];
      _addAllowed(
        result,
        _item(
          snapshot,
          section.metadata,
          task.id,
          LifeContextDomain.task,
          'task',
          facts,
          LifeContextConfirmation.confirmed,
        ),
        contract,
      );
    }
    return result;
  }

  List<LifeContextProjectionItem> _routineCandidates(
    LifeContextSnapshot snapshot,
    LifeContextConsumerContract contract,
  ) {
    final section = snapshot.routineDomain!;
    final result = <LifeContextProjectionItem>[];
    for (final routine in section.routines) {
      final facts = <LifeContextProjectionFact>[
        if (routine.days.isNotEmpty)
          _fact(
            LifeContextProjectionFactKeys.days,
            routine.days.join(','),
            LifeContextSensitivityLevel.publicTechnical,
          ),
        if (routine.startTime != null)
          _fact(
            LifeContextProjectionFactKeys.startTime,
            routine.startTime!,
            LifeContextSensitivityLevel.publicTechnical,
          ),
        if (routine.endTime != null)
          _fact(
            LifeContextProjectionFactKeys.endTime,
            routine.endTime!,
            LifeContextSensitivityLevel.publicTechnical,
          ),
        if (routine.travelMinutes != null)
          _fact(
            LifeContextProjectionFactKeys.travelMinutes,
            '${routine.travelMinutes}',
            LifeContextSensitivityLevel.publicTechnical,
          ),
        if (routine.recurrenceType != null)
          _fact(
            LifeContextProjectionFactKeys.recurringType,
            routine.recurrenceType!,
            LifeContextSensitivityLevel.publicTechnical,
          ),
        _fact(
          LifeContextProjectionFactKeys.travelGoMinutes,
          '${routine.travelGoMinutes}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.travelBackMinutes,
          '${routine.travelBackMinutes}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.marginMinutes,
          '${routine.marginMinutes}',
          LifeContextSensitivityLevel.publicTechnical,
        ),
        if (routine.anchorDateIso != null)
          _fact(
            LifeContextProjectionFactKeys.anchorDateIso,
            routine.anchorDateIso!,
            LifeContextSensitivityLevel.publicTechnical,
          ),
        if (routine.weekOfMonth != null)
          _fact(
            LifeContextProjectionFactKeys.weekOfMonth,
            '${routine.weekOfMonth}',
            LifeContextSensitivityLevel.publicTechnical,
          ),
        if (contract.purpose == LifeContextConsumerPurpose.conversation &&
            routine.label != null)
          _fact(
            LifeContextProjectionFactKeys.title,
            routine.label!,
            LifeContextSensitivityLevel.ordinaryPersonal,
            contract: contract,
          ),
      ];
      _addAllowed(
        result,
        _item(
          snapshot,
          section.metadata,
          routine.id,
          LifeContextDomain.routine,
          'routine',
          facts,
          LifeContextConfirmation.confirmed,
        ),
        contract,
      );
    }
    return result;
  }

  List<LifeContextProjectionItem> _relationCandidates(
    LifeContextSnapshot snapshot,
    LifeContextGraph? graph,
    LifeContextConsumerContract contract,
  ) {
    if (graph == null || contract.maxRelations == 0) return const [];
    final result = <LifeContextProjectionItem>[];
    for (final relation in graph.relations) {
      if (result.length >= contract.maxRelations) break;
      if (relation.confirmation == LifeContextConfirmation.rejected ||
          (!contract.includeUncertain &&
              relation.confirmation != LifeContextConfirmation.confirmed) ||
          (!contract.includeHistorical &&
              relation.status == LifeContextNodeStatus.historical)) {
        continue;
      }
      if (contract.purpose == LifeContextConsumerPurpose.planning &&
          relation.type != LifeContextRelationType.responsibilityFor) {
        continue;
      }
      final sensitivity =
          relation.type == LifeContextRelationType.responsibilityFor
              ? LifeContextSensitivityLevel.privatePersonal
              : LifeContextSensitivityLevel.ordinaryPersonal;
      final facts = [
        _fact(
          LifeContextProjectionFactKeys.kind,
          relation.type.name,
          sensitivity,
        ),
        _fact(
          LifeContextProjectionFactKeys.sourceNodeId,
          relation.sourceNodeId,
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.targetNodeId,
          relation.targetNodeId,
          LifeContextSensitivityLevel.publicTechnical,
        ),
      ];
      _addAllowed(
        result,
        LifeContextProjectionItem(
          id: relation.id,
          domain: relation.provenance.sourceDomain,
          type: 'relation',
          facts: facts,
          confirmation: relation.confirmation,
          freshness: relation.freshness,
          provenance: LifeContextProjectionProvenance(
            sourceDomain: relation.provenance.sourceDomain,
            sourceId: relation.provenance.sourceRecordId,
            sourceSnapshotId: snapshot.snapshotId!,
            sourceKind: relation.provenance.sectionSource,
            ruleId: relation.provenance.ruleId,
          ),
          relationIds: [relation.id],
          validFrom: relation.validity.validFrom,
          validUntil: relation.validity.validUntil,
        ),
        contract,
      );
    }
    return result;
  }

  List<LifeContextProjectionItem> _memoryCandidates(
    LifeContextSnapshot snapshot,
    LifeContextConsumerContract contract,
  ) {
    if (contract.purpose != LifeContextConsumerPurpose.conversation) {
      return const [];
    }
    final section = snapshot.memoryDomain!;
    final result = <LifeContextProjectionItem>[];
    for (final memory in section.memories) {
      if (memory.isExplicitHealth ||
          memory.structuredDomain?.trim().isNotEmpty == true ||
          const {'rejected', 'expired', 'deleted', 'obsolete', 'superseded'}
              .contains(memory.status)) {
        continue;
      }
      final confirmation = _memoryConfirmation(memory.confirmation);
      final facts = <LifeContextProjectionFact>[
        _fact(
          LifeContextProjectionFactKeys.category,
          memory.category.isEmpty ? 'other' : memory.category,
          LifeContextSensitivityLevel.publicTechnical,
        ),
        _fact(
          LifeContextProjectionFactKeys.title,
          memory.text,
          memory.sensitivity == 'sensitive'
              ? LifeContextSensitivityLevel.sensitive
              : LifeContextSensitivityLevel.ordinaryPersonal,
          contract: contract,
        ),
      ];
      _addAllowed(
        result,
        _item(
          snapshot,
          section.metadata,
          memory.id,
          LifeContextDomain.memory,
          'memory',
          facts,
          confirmation,
          validFrom: memory.validFrom,
          validUntil: memory.validUntil,
        ),
        contract,
      );
    }
    return result;
  }

  LifeContextProjectionItem _recordItem(
    LifeContextSnapshot snapshot,
    LifeContextSourceMetadata metadata,
    HumanContextRecord record,
    String type,
    LifeContextSensitivityLevel sensitivity,
    LifeContextConsumerContract contract,
  ) {
    final facts = <LifeContextProjectionFact>[
      _fact(LifeContextProjectionFactKeys.kind, record.kind, sensitivity),
      if (record.label != null &&
          contract.purpose == LifeContextConsumerPurpose.conversation)
        _fact(
          LifeContextProjectionFactKeys.title,
          record.label!,
          sensitivity,
          contract: contract,
        ),
      if (record.validFrom != null)
        _fact(
          LifeContextProjectionFactKeys.start,
          record.validFrom!.toUtc().toIso8601String(),
          LifeContextSensitivityLevel.publicTechnical,
        ),
      if (record.validUntil != null)
        _fact(
          LifeContextProjectionFactKeys.end,
          record.validUntil!.toUtc().toIso8601String(),
          LifeContextSensitivityLevel.publicTechnical,
        ),
    ];
    return _item(
      snapshot,
      metadata,
      record.id,
      LifeContextDomain.human,
      type,
      facts,
      _confirmation(record.confirmation),
      validFrom: record.validFrom,
      validUntil: record.validUntil,
    );
  }

  LifeContextProjectionItem _item(
    LifeContextSnapshot snapshot,
    LifeContextSourceMetadata metadata,
    String id,
    LifeContextDomain domain,
    String type,
    List<LifeContextProjectionFact> facts,
    LifeContextConfirmation confirmation, {
    DateTime? validFrom,
    DateTime? validUntil,
  }) =>
      LifeContextProjectionItem(
        id: '${domain.name}:$type:$id',
        domain: domain,
        type: type,
        facts: facts,
        confirmation: confirmation,
        freshness: metadata.freshness,
        provenance: LifeContextProjectionProvenance(
          sourceDomain: domain,
          sourceId: id,
          sourceSnapshotId: snapshot.snapshotId!,
          sourceKind: metadata.source,
        ),
        validFrom: validFrom,
        validUntil: validUntil,
      );

  LifeContextProjectionFact _fact(
    String key,
    String value,
    LifeContextSensitivityLevel sensitivity, {
    LifeContextConsumerContract? contract,
  }) {
    var normalized = value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final limit = contract?.maxTextLength;
    if (limit != null && limit > 0 && normalized.length > limit) {
      normalized = normalized.substring(0, limit).trimRight();
    }
    return LifeContextProjectionFact(
      key: key,
      value: normalized,
      sensitivity: sensitivity,
    );
  }

  void _addAllowed(
    List<LifeContextProjectionItem> target,
    LifeContextProjectionItem item,
    LifeContextConsumerContract contract,
  ) {
    if (_isAllowed(item, contract)) target.add(item);
  }

  bool _isAllowed(
    LifeContextProjectionItem item,
    LifeContextConsumerContract contract,
  ) {
    if (item.confirmation == LifeContextConfirmation.rejected) return false;
    if (!contract.includeUncertain &&
        item.confirmation != LifeContextConfirmation.confirmed) {
      return false;
    }
    if (!contract.includeHistorical &&
        item.confirmation == LifeContextConfirmation.historical) {
      return false;
    }
    return item.facts.every(
      (fact) =>
          fact.sensitivity != LifeContextSensitivityLevel.highlySensitive &&
          contract.allowedSensitivities.contains(fact.sensitivity),
    );
  }

  int _candidateOrder(
    LifeContextProjectionItem first,
    LifeContextProjectionItem second,
  ) {
    final confirmation = _confirmationRank(first.confirmation) -
        _confirmationRank(second.confirmation);
    if (confirmation != 0) return confirmation;
    final freshness = first.freshness.index.compareTo(second.freshness.index);
    if (freshness != 0) return freshness;
    return first.id.compareTo(second.id);
  }

  int _confirmationRank(LifeContextConfirmation value) => switch (value) {
        LifeContextConfirmation.confirmed => 0,
        LifeContextConfirmation.needsConfirmation => 1,
        LifeContextConfirmation.proposed => 2,
        LifeContextConfirmation.inferred => 3,
        LifeContextConfirmation.historical => 4,
        LifeContextConfirmation.rejected => 5,
      };

  LifeContextConfirmation _confirmation(String value) =>
      LifeContextConfirmation.values.firstWhere(
        (status) => status.name == value,
        orElse: () => LifeContextConfirmation.needsConfirmation,
      );

  LifeContextSourceMetadata? _metadataFor(
    LifeContextProjectionSectionType type,
    Map<LifeContextDomain, LifeContextSourceMetadata> metadata,
    LifeContextGraph? graph,
  ) =>
      switch (type) {
        LifeContextProjectionSectionType.human =>
          metadata[LifeContextDomain.human],
        LifeContextProjectionSectionType.identity =>
          metadata[LifeContextDomain.identity],
        LifeContextProjectionSectionType.event =>
          metadata[LifeContextDomain.event],
        LifeContextProjectionSectionType.task =>
          metadata[LifeContextDomain.task],
        LifeContextProjectionSectionType.routine =>
          metadata[LifeContextDomain.routine],
        LifeContextProjectionSectionType.memory =>
          metadata[LifeContextDomain.memory],
        LifeContextProjectionSectionType.relation =>
          graph == null ? null : metadata[LifeContextDomain.human],
      };

  LifeContextConfirmation _memoryConfirmation(String value) => switch (value) {
        'confirmed' => LifeContextConfirmation.confirmed,
        'rejected' => LifeContextConfirmation.rejected,
        'obsolete' => LifeContextConfirmation.historical,
        'inferred' => LifeContextConfirmation.inferred,
        _ => LifeContextConfirmation.needsConfirmation,
      };

  String? _availabilityWarning(
    LifeContextAvailability availability,
    LifeContextFreshness freshness,
  ) {
    if (freshness == LifeContextFreshness.stale ||
        availability == LifeContextAvailability.availableStale) {
      return 'stale_section';
    }
    return switch (availability) {
      LifeContextAvailability.unavailable => 'unavailable_section',
      LifeContextAvailability.corrupted => 'corrupted_section',
      LifeContextAvailability.unsupported => 'unsupported_section',
      LifeContextAvailability.accountMismatch => 'account_mismatch',
      _ => null,
    };
  }
}
