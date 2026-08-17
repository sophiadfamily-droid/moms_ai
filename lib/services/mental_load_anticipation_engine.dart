import '../models/life_context/life_context_domains.dart';
import '../models/life_context/life_context_graph.dart';
import '../models/mental_load_anticipation.dart';
import '../models/proactive_detection.dart';
import 'proactive_detection_engine.dart';

final class MentalLoadAnticipationPolicy {
  const MentalLoadAnticipationPolicy({
    this.horizon = const Duration(days: 14),
    this.urgentEventLead = const Duration(days: 2),
    this.urgentDeadlineLead = const Duration(days: 1),
    this.maximumCandidates = 8,
  });

  final Duration horizon;
  final Duration urgentEventLead;
  final Duration urgentDeadlineLead;
  final int maximumCandidates;

  void validate() {
    if (horizon <= Duration.zero ||
        urgentEventLead <= Duration.zero ||
        urgentDeadlineLead <= Duration.zero ||
        maximumCandidates < 1 ||
        maximumCandidates > 32) {
      throw const FormatException('mental_load_anticipation_policy_invalid');
    }
  }
}

/// First Stage 9 reasoning slice.
///
/// It anticipates only a preparation Task explicitly and structurally linked
/// to a future Event. It never infers a preparation from an Event title and it
/// performs no write, notification scheduling or action execution.
final class MentalLoadAnticipationEngine {
  const MentalLoadAnticipationEngine();

  List<MentalLoadAnticipation> evaluate({
    required ProactiveDetectionInput input,
    required MentalLoadAnticipationPolicy policy,
    required DateTime now,
  }) {
    policy.validate();
    final current = now.toUtc();
    if (!input.coverage.evaluableCategories
        .contains(ProactiveDetectorType.potentialOmission)) {
      return const [];
    }

    final subjects = <String, DetectionSubject>{
      for (final subject in input.subjects)
        '${subject.domain.name}:${subject.kind.name}:${subject.sourceId}':
            subject,
    };
    final candidates = <MentalLoadAnticipation>[];

    for (final dependency in input.dependencies) {
      if (!_isConfirmedExplicitPreparation(dependency, current)) continue;
      final preparation = subjects[dependency.prerequisiteNodeId];
      final event = subjects[dependency.dependentNodeId];
      if (preparation == null || event == null) continue;
      if (!_isUsablePreparation(preparation) || !_isUsableEvent(event)) {
        continue;
      }

      final deadline = preparation.deadline!.toUtc();
      final eventStart = event.plannedStart!.toUtc();
      if (eventStart.isBefore(current) ||
          eventStart.isAfter(current.add(policy.horizon)) ||
          deadline.isAfter(eventStart)) {
        continue;
      }

      final evidence = <DetectionEvidence>[
        ...preparation.evidence.where(_isConfirmedEvidence),
        ...event.evidence.where(_isConfirmedEvidence),
      ];
      if (evidence.isEmpty) continue;

      final priority =
          !deadline.isAfter(current.add(policy.urgentDeadlineLead)) ||
                  !eventStart.isAfter(current.add(policy.urgentEventLead))
              ? MentalLoadAnticipationPriority.urgent
              : MentalLoadAnticipationPriority.important;
      candidates.add(MentalLoadAnticipation(
        id: 'mental-load:${dependency.id}',
        accountScopeId: input.accountScopeId,
        reason: MentalLoadAnticipationReason.explicitPreparationBeforeEvent,
        priority: priority,
        preparationSourceId: preparation.sourceId,
        eventSourceId: event.sourceId,
        preparationDeadline: deadline,
        eventStart: eventStart,
        evidence: evidence,
      ));
    }

    candidates.sort((a, b) {
      final priority = b.priority.index.compareTo(a.priority.index);
      if (priority != 0) return priority;
      final event = a.eventStart.compareTo(b.eventStart);
      if (event != 0) return event;
      return a.id.compareTo(b.id);
    });
    return candidates.take(policy.maximumCandidates).toList(growable: false);
  }

  static bool _isConfirmedExplicitPreparation(
    LifeContextDependency dependency,
    DateTime now,
  ) =>
      dependency.validity.isActiveAt(now) &&
      dependency.provenance.confirmation == LifeContextConfirmation.confirmed &&
      dependency.provenance.ruleId ==
          LifeContextRegisteredRuleIds.explicitDependency &&
      (dependency.type == LifeContextDependencyType.requires ||
          dependency.type == LifeContextDependencyType.explicitUserDependency);

  static bool _isUsablePreparation(DetectionSubject subject) =>
      subject.kind == DetectionSubjectKind.task &&
      subject.domain == LifeContextDomain.task &&
      subject.active &&
      !subject.completed &&
      !subject.deleted &&
      subject.deadline != null &&
      subject.isCurrent;

  static bool _isUsableEvent(DetectionSubject subject) =>
      subject.kind == DetectionSubjectKind.event &&
      subject.domain == LifeContextDomain.event &&
      subject.active &&
      !subject.deleted &&
      subject.plannedStart != null &&
      subject.isCurrent;

  static bool _isConfirmedEvidence(DetectionEvidence evidence) =>
      evidence.confirmed &&
      evidence.freshness == LifeContextFreshness.current &&
      evidence.availability == LifeContextAvailability.available &&
      evidence.certainty != DetectionEvidenceLevel.insufficient;
}
