import 'dart:collection';

import '../life_context/life_context_graph.dart';
import 'priority_models.dart';

enum PriorityPropagationDirection { dependentToPrerequisite }

enum PriorityPropagationCycleState { none, cycleDetected }

enum PriorityPropagationTruncationState { complete, truncated }

enum PriorityPropagationFreshness {
  fresh,
  stale,
  unavailable,
  corrupted,
}

final class PriorityPropagationPath {
  PriorityPropagationPath({
    required List<String> nodeIds,
    required List<String> dependencyIds,
    required this.depth,
    required this.truncated,
  })  : nodeIds = UnmodifiableListView(nodeIds),
        dependencyIds = UnmodifiableListView(dependencyIds) {
    if (depth < 1 ||
        nodeIds.length != depth + 1 ||
        dependencyIds.length != depth ||
        nodeIds.any((id) => id.trim().isEmpty) ||
        dependencyIds.any((id) => id.trim().isEmpty)) {
      throw const PriorityException('invalid_priority_propagation_path');
    }
  }

  final List<String> nodeIds;
  final List<String> dependencyIds;
  final int depth;
  final bool truncated;

  Map<String, Object?> toJson() => {
        'nodeIds': nodeIds,
        'dependencyIds': dependencyIds,
        'depth': depth,
        'truncated': truncated,
      };
}

final class PriorityDependencyInfluence {
  static const int currentSchemaVersion = 1;

  PriorityDependencyInfluence({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.sourceCandidateId,
    required this.targetCandidateId,
    required this.dependencyId,
    required this.dependencyType,
    required this.depth,
    required this.direction,
    required this.rawContribution,
    required this.depthFactor,
    required this.confirmationFactor,
    required this.freshnessFactor,
    required this.finalContribution,
    required this.provenance,
    required this.path,
    required this.containsCycle,
    required this.truncated,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const PriorityException(
        'unsupported_priority_influence_version',
      );
    }
    if (id.trim().isEmpty ||
        sourceCandidateId.trim().isEmpty ||
        targetCandidateId.trim().isEmpty ||
        sourceCandidateId == targetCandidateId ||
        dependencyId.trim().isEmpty ||
        depth < 1 ||
        path.depth != depth ||
        !_unit(depthFactor) ||
        !_unit(confirmationFactor) ||
        !_unit(freshnessFactor) ||
        !rawContribution.isFinite ||
        rawContribution < 0 ||
        rawContribution > 100 ||
        !finalContribution.isFinite ||
        finalContribution < 0 ||
        finalContribution > 100) {
      throw const PriorityException('invalid_priority_influence');
    }
    provenance.validate();
  }

  final int schemaVersion;
  final String id;
  final String sourceCandidateId;
  final String targetCandidateId;
  final String dependencyId;
  final LifeContextDependencyType dependencyType;
  final int depth;
  final PriorityPropagationDirection direction;
  final double rawContribution;
  final double depthFactor;
  final double confirmationFactor;
  final double freshnessFactor;
  final double finalContribution;
  final PriorityProvenance provenance;
  final PriorityPropagationPath path;
  final bool containsCycle;
  final bool truncated;

  static bool _unit(double value) => value.isFinite && value >= 0 && value <= 1;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'sourceCandidateId': sourceCandidateId,
        'targetCandidateId': targetCandidateId,
        'dependencyId': dependencyId,
        'dependencyType': dependencyType.name,
        'depth': depth,
        'direction': direction.name,
        'rawContribution': rawContribution,
        'depthFactor': depthFactor,
        'confirmationFactor': confirmationFactor,
        'freshnessFactor': freshnessFactor,
        'finalContribution': finalContribution,
        'provenance': provenance.toJson(),
        'path': path.toJson(),
        'containsCycle': containsCycle,
        'truncated': truncated,
      };
}

final class PriorityPropagationCycle {
  PriorityPropagationCycle({
    required this.id,
    required List<String> nodeIds,
    required List<String> dependencyIds,
  })  : nodeIds = UnmodifiableListView(nodeIds),
        dependencyIds = UnmodifiableListView(dependencyIds) {
    if (id.trim().isEmpty ||
        nodeIds.length < 2 ||
        dependencyIds.isEmpty ||
        nodeIds.any((value) => value.trim().isEmpty) ||
        dependencyIds.any((value) => value.trim().isEmpty)) {
      throw const PriorityException('invalid_priority_cycle');
    }
  }

  final String id;
  final List<String> nodeIds;
  final List<String> dependencyIds;

  Map<String, Object?> toJson() => {
        'id': id,
        'nodeIds': nodeIds,
        'dependencyIds': dependencyIds,
      };
}

final class PropagatedPriorityScore {
  static const int currentSchemaVersion = 1;

  PropagatedPriorityScore({
    this.schemaVersion = currentSchemaVersion,
    required this.candidate,
    required this.directScore,
    required this.propagatedContribution,
    required this.adjustedScore,
    required this.confidence,
    required this.freshness,
    required List<PriorityMissingData> missingData,
    required List<PriorityDependencyInfluence> influences,
    required this.omittedInfluenceCount,
    required this.cycleState,
    required this.truncationState,
    required this.formulaVersion,
    required this.propagationVersion,
  })  : missingData = UnmodifiableListView(
          List<PriorityMissingData>.of(missingData)
            ..sort((a, b) => a.index.compareTo(b.index)),
        ),
        influences = UnmodifiableListView(
          List<PriorityDependencyInfluence>.of(influences)
            ..sort((a, b) {
              final contribution =
                  b.finalContribution.compareTo(a.finalContribution);
              return contribution != 0 ? contribution : a.id.compareTo(b.id);
            }),
        ) {
    if (schemaVersion != currentSchemaVersion) {
      throw const PriorityException(
        'unsupported_propagated_priority_score_version',
      );
    }
    if (candidate.id != directScore.candidateId ||
        !propagatedContribution.isFinite ||
        propagatedContribution < 0 ||
        propagatedContribution > 100 ||
        !adjustedScore.isFinite ||
        adjustedScore < 0 ||
        adjustedScore > 100 ||
        omittedInfluenceCount < 0 ||
        formulaVersion != directScore.formulaVersion ||
        propagationVersion < 1) {
      throw const PriorityException('invalid_propagated_priority_score');
    }
  }

  final int schemaVersion;
  final PriorityCandidate candidate;
  final PriorityScore directScore;
  final double propagatedContribution;
  final double adjustedScore;
  final PriorityConfidence confidence;
  final PriorityPropagationFreshness freshness;
  final List<PriorityMissingData> missingData;
  final List<PriorityDependencyInfluence> influences;
  final int omittedInfluenceCount;
  final PriorityPropagationCycleState cycleState;
  final PriorityPropagationTruncationState truncationState;
  final int formulaVersion;
  final int propagationVersion;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'candidateId': candidate.id,
        'directScore': directScore.toJson(),
        'propagatedContribution': propagatedContribution,
        'adjustedScore': adjustedScore,
        'confidence': confidence.name,
        'freshness': freshness.name,
        'missingData': missingData.map((item) => item.name).toList(),
        'influences': influences.map((item) => item.toJson()).toList(),
        'omittedInfluenceCount': omittedInfluenceCount,
        'cycleState': cycleState.name,
        'truncationState': truncationState.name,
        'formulaVersion': formulaVersion,
        'propagationVersion': propagationVersion,
      };
}

final class PropagatedPriorityRankedCandidate {
  const PropagatedPriorityRankedCandidate({
    required this.rank,
    required this.score,
  });

  final int rank;
  final PropagatedPriorityScore score;
}

final class PropagatedPriorityRanking {
  static const int currentSchemaVersion = 1;

  PropagatedPriorityRanking({
    this.schemaVersion = currentSchemaVersion,
    required this.sourceSnapshotId,
    required this.evaluatedAt,
    required this.propagationVersion,
    required List<PropagatedPriorityRankedCandidate> items,
    required List<PriorityPropagationCycle> cycles,
    required this.omittedCount,
    required this.truncationState,
  })  : items = UnmodifiableListView(items),
        cycles = UnmodifiableListView(
          List<PriorityPropagationCycle>.of(cycles)
            ..sort((a, b) => a.id.compareTo(b.id)),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        sourceSnapshotId.trim().isEmpty ||
        propagationVersion < 1 ||
        omittedCount < 0 ||
        items
            .asMap()
            .entries
            .any((entry) => entry.value.rank != entry.key + 1)) {
      throw const PriorityException('invalid_propagated_priority_ranking');
    }
  }

  final int schemaVersion;
  final String sourceSnapshotId;
  final DateTime evaluatedAt;
  final int propagationVersion;
  final List<PropagatedPriorityRankedCandidate> items;
  final List<PriorityPropagationCycle> cycles;
  final int omittedCount;
  final PriorityPropagationTruncationState truncationState;
}
