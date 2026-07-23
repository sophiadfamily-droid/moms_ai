import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/priority/priority_models.dart';

final class PriorityGraphCandidateAdapter {
  const PriorityGraphCandidateAdapter();

  LifeContextGraphNode? nodeForCandidate(
    PriorityCandidate candidate,
    LifeContextGraph graph,
  ) {
    if (candidate.accountScopeId != graph.accountScopeId) {
      throw const PriorityException('priority_graph_account_mismatch');
    }
    final domain = switch (candidate.sourceDomain) {
      PrioritySourceDomain.task => LifeContextDomain.task,
      PrioritySourceDomain.event => LifeContextDomain.event,
      PrioritySourceDomain.routine => LifeContextDomain.routine,
    };
    final type = switch (candidate.sourceDomain) {
      PrioritySourceDomain.task => LifeContextNodeType.task,
      PrioritySourceDomain.event => LifeContextNodeType.event,
      PrioritySourceDomain.routine => LifeContextNodeType.routine,
    };
    final expectedId =
        LifeContextGraphNode.deterministicId(domain, type, candidate.sourceId);
    for (final node in graph.nodes) {
      if (node.id == expectedId &&
          node.domain == domain &&
          node.resourceType == type &&
          node.sourceId == candidate.sourceId) {
        return node;
      }
    }
    return null;
  }

  Map<String, PriorityRankedCandidate> candidatesByNode(
    PriorityRanking ranking,
    LifeContextGraph graph, {
    required String expectedAccountScopeId,
  }) {
    if (graph.accountScopeId != expectedAccountScopeId) {
      throw const PriorityException('priority_graph_account_mismatch');
    }
    final result = <String, PriorityRankedCandidate>{};
    for (final item in ranking.items) {
      if (item.candidate.accountScopeId != expectedAccountScopeId) {
        throw const PriorityException('priority_graph_account_mismatch');
      }
      final node = nodeForCandidate(item.candidate, graph);
      if (node != null) result[node.id] = item;
    }
    return Map.unmodifiable(result);
  }
}
