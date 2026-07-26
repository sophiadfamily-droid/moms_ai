import 'dart:collection';

import 'life_context_domains.dart';
import 'life_context_graph.dart';

enum LifeContextConsumerPurpose { conversation, planning, internalTechnical }

enum LifeContextSensitivityLevel {
  publicTechnical,
  ordinaryPersonal,
  privatePersonal,
  sensitive,
  highlySensitive,
}

enum LifeContextProjectionState { complete, partial }

enum LifeContextTruncationPolicy { omitWholeItem }

enum LifeContextProjectionSectionType {
  human,
  identity,
  event,
  task,
  routine,
  memory,
  relation,
}

abstract final class LifeContextProjectionFactKeys {
  static const displayName = 'displayName';
  static const status = 'status';
  static const kind = 'kind';
  static const start = 'start';
  static const end = 'end';
  static const dueDate = 'dueDate';
  static const durationMinutes = 'durationMinutes';
  static const travelGoMinutes = 'travelGoMinutes';
  static const travelBackMinutes = 'travelBackMinutes';
  static const marginMinutes = 'marginMinutes';
  static const recurringType = 'recurringType';
  static const syncStatus = 'syncStatus';
  static const revision = 'revision';
  static const days = 'days';
  static const startTime = 'startTime';
  static const endTime = 'endTime';
  static const travelMinutes = 'travelMinutes';
  static const anchorDateIso = 'anchorDateIso';
  static const weekOfMonth = 'weekOfMonth';
  static const title = 'title';
  static const category = 'category';
  static const sourceNodeId = 'sourceNodeId';
  static const targetNodeId = 'targetNodeId';
  static const actionRequired = 'actionRequired';
  static const importance = 'importance';
  static const urgency = 'urgency';
  static const flexibility = 'flexibility';

  static const all = {
    displayName,
    status,
    kind,
    start,
    end,
    dueDate,
    durationMinutes,
    travelGoMinutes,
    travelBackMinutes,
    marginMinutes,
    recurringType,
    syncStatus,
    revision,
    days,
    startTime,
    endTime,
    travelMinutes,
    anchorDateIso,
    weekOfMonth,
    title,
    category,
    sourceNodeId,
    targetNodeId,
    actionRequired,
    importance,
    urgency,
    flexibility,
  };
}

final class LifeContextProjectionException implements Exception {
  const LifeContextProjectionException(this.code);

  final String code;

  @override
  String toString() => 'LifeContextProjectionException($code)';
}

final class LifeContextConsumerContract {
  static const int currentSchemaVersion = 1;

  LifeContextConsumerContract._({
    required this.schemaVersion,
    required this.purpose,
    required this.purposeId,
    required Set<LifeContextProjectionSectionType> allowedSections,
    required Set<LifeContextSensitivityLevel> allowedSensitivities,
    required this.globalBudget,
    required Map<LifeContextProjectionSectionType, int> sectionBudgets,
    required this.pastWindow,
    required this.futureWindow,
    required this.includeHistorical,
    required this.includeFuture,
    required this.includeUncertain,
    required this.allowStale,
    required this.allowPartial,
    required Set<LifeContextDomain> requiredDomains,
    required this.maxRelationDepth,
    required this.maxRelations,
    required this.maxItems,
    required this.maxTextLength,
    required this.truncationPolicy,
  })  : allowedSections = UnmodifiableSetView(allowedSections),
        allowedSensitivities = UnmodifiableSetView(allowedSensitivities),
        sectionBudgets = UnmodifiableMapView(sectionBudgets),
        requiredDomains = UnmodifiableSetView(requiredDomains) {
    validate();
  }

  factory LifeContextConsumerContract.forPurpose(
    LifeContextConsumerPurpose purpose, {
    int schemaVersion = currentSchemaVersion,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const LifeContextProjectionException(
        'unsupported_consumer_contract_version',
      );
    }
    return switch (purpose) {
      LifeContextConsumerPurpose.conversation => LifeContextConsumerContract._(
          schemaVersion: schemaVersion,
          purpose: purpose,
          purposeId: 'conversation.context.v1',
          allowedSections: LifeContextProjectionSectionType.values.toSet(),
          allowedSensitivities: const {
            LifeContextSensitivityLevel.publicTechnical,
            LifeContextSensitivityLevel.ordinaryPersonal,
            LifeContextSensitivityLevel.privatePersonal,
          },
          globalBudget: 245,
          sectionBudgets: const {
            LifeContextProjectionSectionType.human: 55,
            LifeContextProjectionSectionType.identity: 10,
            LifeContextProjectionSectionType.event: 50,
            LifeContextProjectionSectionType.task: 30,
            LifeContextProjectionSectionType.routine: 20,
            LifeContextProjectionSectionType.memory: 30,
            LifeContextProjectionSectionType.relation: 50,
          },
          pastWindow: const Duration(days: 7),
          futureWindow: const Duration(days: 30),
          includeHistorical: false,
          includeFuture: true,
          includeUncertain: true,
          allowStale: true,
          allowPartial: true,
          requiredDomains: const {LifeContextDomain.human},
          maxRelationDepth: 1,
          maxRelations: 12,
          maxItems: 40,
          maxTextLength: 80,
          truncationPolicy: LifeContextTruncationPolicy.omitWholeItem,
        ),
      LifeContextConsumerPurpose.planning => LifeContextConsumerContract._(
          schemaVersion: schemaVersion,
          purpose: purpose,
          purposeId: 'planning.context.v1',
          allowedSections: const {
            LifeContextProjectionSectionType.human,
            LifeContextProjectionSectionType.event,
            LifeContextProjectionSectionType.routine,
            LifeContextProjectionSectionType.relation,
          },
          allowedSensitivities: const {
            LifeContextSensitivityLevel.publicTechnical,
            LifeContextSensitivityLevel.privatePersonal,
          },
          globalBudget: 180,
          sectionBudgets: const {
            LifeContextProjectionSectionType.human: 30,
            LifeContextProjectionSectionType.event: 110,
            LifeContextProjectionSectionType.routine: 35,
            LifeContextProjectionSectionType.relation: 15,
          },
          pastWindow: const Duration(days: 1),
          futureWindow: const Duration(days: 60),
          includeHistorical: false,
          includeFuture: true,
          includeUncertain: false,
          allowStale: true,
          allowPartial: true,
          requiredDomains: const {
            LifeContextDomain.event,
            LifeContextDomain.routine,
          },
          maxRelationDepth: 1,
          maxRelations: 8,
          maxItems: 60,
          maxTextLength: 0,
          truncationPolicy: LifeContextTruncationPolicy.omitWholeItem,
        ),
      LifeContextConsumerPurpose.internalTechnical =>
        LifeContextConsumerContract._(
          schemaVersion: schemaVersion,
          purpose: purpose,
          purposeId: 'internal.context.v1',
          allowedSections: LifeContextProjectionSectionType.values.toSet(),
          allowedSensitivities: const {
            LifeContextSensitivityLevel.publicTechnical,
          },
          globalBudget: 80,
          sectionBudgets: {
            for (final section in LifeContextProjectionSectionType.values)
              section: 20,
          },
          pastWindow: Duration.zero,
          futureWindow: Duration.zero,
          includeHistorical: false,
          includeFuture: false,
          includeUncertain: false,
          allowStale: true,
          allowPartial: true,
          requiredDomains: const {},
          maxRelationDepth: 1,
          maxRelations: 5,
          maxItems: 20,
          maxTextLength: 0,
          truncationPolicy: LifeContextTruncationPolicy.omitWholeItem,
        ),
    };
  }

  final int schemaVersion;
  final LifeContextConsumerPurpose purpose;
  final String purposeId;
  final Set<LifeContextProjectionSectionType> allowedSections;
  final Set<LifeContextSensitivityLevel> allowedSensitivities;
  final int globalBudget;
  final Map<LifeContextProjectionSectionType, int> sectionBudgets;
  final Duration pastWindow;
  final Duration futureWindow;
  final bool includeHistorical;
  final bool includeFuture;
  final bool includeUncertain;
  final bool allowStale;
  final bool allowPartial;
  final Set<LifeContextDomain> requiredDomains;
  final int maxRelationDepth;
  final int maxRelations;
  final int maxItems;
  final int maxTextLength;
  final LifeContextTruncationPolicy truncationPolicy;

  LifeContextConsumerContract requiringFreshData() => _copyWith(
        allowStale: false,
      );

  LifeContextConsumerContract requiringCompleteData() => _copyWith(
        allowPartial: false,
      );

  LifeContextConsumerContract includingHistoricalData() => _copyWith(
        includeHistorical: true,
      );

  LifeContextConsumerContract _copyWith({
    bool? allowStale,
    bool? allowPartial,
    bool? includeHistorical,
  }) =>
      LifeContextConsumerContract._(
        schemaVersion: schemaVersion,
        purpose: purpose,
        purposeId: purposeId,
        allowedSections: allowedSections,
        allowedSensitivities: allowedSensitivities,
        globalBudget: globalBudget,
        sectionBudgets: sectionBudgets,
        pastWindow: pastWindow,
        futureWindow: futureWindow,
        includeHistorical: includeHistorical ?? this.includeHistorical,
        includeFuture: includeFuture,
        includeUncertain: includeUncertain,
        allowStale: allowStale ?? this.allowStale,
        allowPartial: allowPartial ?? this.allowPartial,
        requiredDomains: requiredDomains,
        maxRelationDepth: maxRelationDepth,
        maxRelations: maxRelations,
        maxItems: maxItems,
        maxTextLength: maxTextLength,
        truncationPolicy: truncationPolicy,
      );

  void validate() {
    if (schemaVersion != currentSchemaVersion) {
      throw const LifeContextProjectionException(
        'unsupported_consumer_contract_version',
      );
    }
    if (purposeId.trim().isEmpty ||
        globalBudget < 1 ||
        maxRelationDepth < 0 ||
        maxRelations < 0 ||
        maxItems < 1 ||
        maxTextLength < 0 ||
        allowedSections.isEmpty ||
        sectionBudgets.entries.any(
          (entry) => entry.value < 1 || !allowedSections.contains(entry.key),
        ) ||
        allowedSections
            .any((section) => !sectionBudgets.containsKey(section)) ||
        allowedSensitivities
            .contains(LifeContextSensitivityLevel.highlySensitive)) {
      throw const LifeContextProjectionException('invalid_consumer_contract');
    }
  }
}

final class LifeContextProjectionFact {
  LifeContextProjectionFact({
    required this.key,
    required this.value,
    required this.sensitivity,
  }) {
    if (!LifeContextProjectionFactKeys.all.contains(key) ||
        value.trim().isEmpty ||
        sensitivity == LifeContextSensitivityLevel.highlySensitive) {
      throw const LifeContextProjectionException('invalid_projection_fact');
    }
  }

  final String key;
  final String value;
  final LifeContextSensitivityLevel sensitivity;

  int get budgetCost => 1;

  Map<String, Object?> toJson() => {
        'key': key,
        'value': value,
        'sensitivity': sensitivity.name,
      };
}

final class LifeContextProjectionProvenance {
  const LifeContextProjectionProvenance({
    required this.sourceDomain,
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.sourceKind,
    this.ruleId,
  });

  final LifeContextDomain sourceDomain;
  final String sourceId;
  final String sourceSnapshotId;
  final LifeContextSourceKind sourceKind;
  final String? ruleId;

  Map<String, Object?> toJson() => {
        'sourceDomain': sourceDomain.name,
        'sourceId': sourceId,
        'sourceSnapshotId': sourceSnapshotId,
        'sourceKind': sourceKind.name,
        if (ruleId != null) 'ruleId': ruleId,
      };
}

final class LifeContextProjectionItem {
  LifeContextProjectionItem({
    required this.id,
    required this.domain,
    required this.type,
    required List<LifeContextProjectionFact> facts,
    required this.confirmation,
    required this.freshness,
    required this.provenance,
    List<String> relationIds = const [],
    this.validFrom,
    this.validUntil,
  })  : facts = UnmodifiableListView(
          List<LifeContextProjectionFact>.of(facts)
            ..sort((a, b) => a.key.compareTo(b.key)),
        ),
        relationIds = UnmodifiableListView(
          List<String>.of(relationIds)..sort(),
        ) {
    if (id.trim().isEmpty ||
        type.trim().isEmpty ||
        facts.isEmpty ||
        (validFrom != null &&
            validUntil != null &&
            validUntil!.isBefore(validFrom!))) {
      throw const LifeContextProjectionException('invalid_projection_item');
    }
  }

  final String id;
  final LifeContextDomain domain;
  final String type;
  final List<LifeContextProjectionFact> facts;
  final LifeContextConfirmation confirmation;
  final LifeContextFreshness freshness;
  final LifeContextProjectionProvenance provenance;
  final List<String> relationIds;
  final DateTime? validFrom;
  final DateTime? validUntil;

  int get budgetCost => 1 + facts.fold(0, (sum, fact) => sum + fact.budgetCost);

  LifeContextSensitivityLevel get maximumSensitivity => facts
      .map((fact) => fact.sensitivity)
      .reduce((a, b) => a.index >= b.index ? a : b);

  Map<String, Object?> toJson() => {
        'id': id,
        'domain': domain.name,
        'type': type,
        'facts': facts.map((fact) => fact.toJson()).toList(),
        'confirmation': confirmation.name,
        'freshness': freshness.name,
        'provenance': provenance.toJson(),
        'budgetCost': budgetCost,
        if (relationIds.isNotEmpty) 'relationIds': relationIds,
        if (validFrom != null)
          'validFrom': validFrom!.toUtc().toIso8601String(),
        if (validUntil != null)
          'validUntil': validUntil!.toUtc().toIso8601String(),
      };
}

final class LifeContextProjectionSection {
  LifeContextProjectionSection({
    required this.type,
    required this.availability,
    required this.freshness,
    required List<LifeContextProjectionItem> items,
    required this.budgetLimit,
    required this.budgetUsed,
    required this.omittedCount,
    required this.truncated,
    this.warningCode,
  }) : items = UnmodifiableListView(items) {
    if (budgetLimit < 1 ||
        budgetUsed < 0 ||
        budgetUsed > budgetLimit ||
        omittedCount < 0) {
      throw const LifeContextProjectionException(
        'invalid_projection_section',
      );
    }
  }

  final LifeContextProjectionSectionType type;
  final LifeContextAvailability availability;
  final LifeContextFreshness freshness;
  final List<LifeContextProjectionItem> items;
  final int budgetLimit;
  final int budgetUsed;
  final int omittedCount;
  final bool truncated;
  final String? warningCode;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'availability': availability.name,
        'freshness': freshness.name,
        'items': items.map((item) => item.toJson()).toList(),
        'budgetLimit': budgetLimit,
        'budgetUsed': budgetUsed,
        'omittedCount': omittedCount,
        'truncated': truncated,
        if (warningCode != null) 'warningCode': warningCode,
      };
}

final class LifeContextProjection {
  static const int currentSchemaVersion = 1;

  LifeContextProjection({
    this.schemaVersion = currentSchemaVersion,
    required this.projectionId,
    required this.sourceSnapshotId,
    required this.accountScopeId,
    required this.purpose,
    required this.generatedAt,
    required this.state,
    required this.budgetRequested,
    required this.budgetUsed,
    required List<LifeContextProjectionSection> sections,
    required this.omittedCount,
    required List<String> warningCodes,
  })  : sections = UnmodifiableListView(
          List<LifeContextProjectionSection>.of(sections)
            ..sort((a, b) => a.type.index.compareTo(b.type.index)),
        ),
        warningCodes = UnmodifiableListView(
          List<String>.of(warningCodes)..sort(),
        ) {
    if (schemaVersion != currentSchemaVersion) {
      throw const LifeContextProjectionException(
        'unsupported_projection_version',
      );
    }
    if (projectionId.trim().isEmpty ||
        sourceSnapshotId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        budgetRequested < 1 ||
        budgetUsed < 0 ||
        budgetUsed > budgetRequested ||
        omittedCount < 0 ||
        sections.isEmpty) {
      throw const LifeContextProjectionException('invalid_projection');
    }
  }

  final int schemaVersion;
  final String projectionId;
  final String sourceSnapshotId;
  final String accountScopeId;
  final LifeContextConsumerPurpose purpose;
  final DateTime generatedAt;
  final LifeContextProjectionState state;
  final int budgetRequested;
  final int budgetUsed;
  final List<LifeContextProjectionSection> sections;
  final int omittedCount;
  final List<String> warningCodes;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'projectionId': projectionId,
        'sourceSnapshotId': sourceSnapshotId,
        'purpose': purpose.name,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'state': state.name,
        'budgetRequested': budgetRequested,
        'budgetUsed': budgetUsed,
        'sections': sections.map((section) => section.toJson()).toList(),
        'omittedCount': omittedCount,
        'warningCodes': warningCodes,
      };
}
