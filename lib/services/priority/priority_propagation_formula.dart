import '../../models/life_context/life_context_graph.dart';
import '../../models/priority/priority_models.dart';

final class PriorityDependencyRule {
  const PriorityDependencyRule({
    required this.type,
    required this.propagates,
    required this.baseCoefficient,
    required this.maximumDepth,
    required this.requiresConfirmed,
    required this.technicalReasonCode,
  });

  final LifeContextDependencyType type;
  final bool propagates;
  final double baseCoefficient;
  final int maximumDepth;
  final bool requiresConfirmed;
  final String technicalReasonCode;
}

abstract final class PriorityPropagationFormula {
  static const int version = 1;
  static const int maximumDepth = 3;
  static const int maximumVisitedNodes = 100;
  static const int maximumVisitedEdges = 200;
  static const int maximumInfluencesPerCandidate = 5;
  static const int maximumRankingSize = 100;
  static const double maximumContributionPerInfluence = 12;
  static const double maximumContributionPerCandidate = 25;

  static const Map<int, double> depthFactors = {1: 1, 2: .5, 3: .25};

  static const Map<LifeContextDependencyType, PriorityDependencyRule> rules = {
    LifeContextDependencyType.requires: PriorityDependencyRule(
      type: LifeContextDependencyType.requires,
      propagates: true,
      baseCoefficient: .20,
      maximumDepth: 3,
      requiresConfirmed: true,
      technicalReasonCode: 'requires_prerequisite_reinforcement',
    ),
    LifeContextDependencyType.blocks: PriorityDependencyRule(
      type: LifeContextDependencyType.blocks,
      propagates: true,
      baseCoefficient: .25,
      maximumDepth: 3,
      requiresConfirmed: true,
      technicalReasonCode: 'blocks_prerequisite_reinforcement',
    ),
    LifeContextDependencyType.follows: PriorityDependencyRule(
      type: LifeContextDependencyType.follows,
      propagates: true,
      baseCoefficient: .10,
      maximumDepth: 2,
      requiresConfirmed: true,
      technicalReasonCode: 'follows_prerequisite_reinforcement',
    ),
    LifeContextDependencyType.explicitUserDependency: PriorityDependencyRule(
      type: LifeContextDependencyType.explicitUserDependency,
      propagates: true,
      baseCoefficient: .20,
      maximumDepth: 3,
      requiresConfirmed: true,
      technicalReasonCode: 'explicit_dependency_reinforcement',
    ),
    LifeContextDependencyType.belongsTo: PriorityDependencyRule(
      type: LifeContextDependencyType.belongsTo,
      propagates: false,
      baseCoefficient: 0,
      maximumDepth: 0,
      requiresConfirmed: true,
      technicalReasonCode: 'belongs_to_not_propagated',
    ),
    LifeContextDependencyType.scheduledBy: PriorityDependencyRule(
      type: LifeContextDependencyType.scheduledBy,
      propagates: false,
      baseCoefficient: 0,
      maximumDepth: 0,
      requiresConfirmed: true,
      technicalReasonCode: 'scheduled_by_not_propagated',
    ),
    LifeContextDependencyType.generatedFrom: PriorityDependencyRule(
      type: LifeContextDependencyType.generatedFrom,
      propagates: false,
      baseCoefficient: 0,
      maximumDepth: 0,
      requiresConfirmed: true,
      technicalReasonCode: 'generated_from_not_propagated',
    ),
    LifeContextDependencyType.custom: PriorityDependencyRule(
      type: LifeContextDependencyType.custom,
      propagates: false,
      baseCoefficient: 0,
      maximumDepth: 0,
      requiresConfirmed: true,
      technicalReasonCode: 'custom_dependency_unsupported',
    ),
  };

  static void validate() {
    if (rules.length != LifeContextDependencyType.values.length ||
        depthFactors.length != maximumDepth ||
        depthFactors.entries.any(
          (entry) =>
              entry.key < 1 ||
              entry.key > maximumDepth ||
              !entry.value.isFinite ||
              entry.value <= 0 ||
              entry.value > 1,
        ) ||
        rules.entries.any(
          (entry) =>
              entry.key != entry.value.type ||
              !entry.value.baseCoefficient.isFinite ||
              entry.value.baseCoefficient < 0 ||
              entry.value.baseCoefficient > 1 ||
              entry.value.maximumDepth < 0 ||
              entry.value.maximumDepth > maximumDepth ||
              entry.value.technicalReasonCode.trim().isEmpty,
        )) {
      throw const PriorityException('invalid_priority_propagation_formula');
    }
  }
}
