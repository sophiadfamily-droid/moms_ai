import 'memory_engine_service.dart';
import 'natural_event_request_service.dart';
import 'natural_language_normalizer.dart';
import 'planning_search_request_service.dart';
import 'shopping_conversation_intent_detector.dart';
import 'task_creation_draft_service.dart';

enum ConversationRequestDomain {
  event,
  task,
  shopping,
  memory,
}

final class ConversationCompoundRequest {
  const ConversationCompoundRequest({
    required this.parts,
    required this.domains,
  });

  final List<String> parts;
  final List<ConversationRequestDomain?> domains;
}

/// Sépare uniquement des demandes autonomes et explicitement reconnaissables.
///
/// Une simple énumération (par exemple « lait et pain ») reste intacte. Le
/// premier fragment peut être une réponse contextuelle lorsqu'une interaction
/// est déjà en cours, mais chaque fragment suivant doit porter sa propre
/// commande afin qu'aucune action ne soit inventée.
final class ConversationCompoundRequestService {
  const ConversationCompoundRequestService({
    this.maximumParts = 3,
  });

  final int maximumParts;

  ConversationCompoundRequest? split(
    String input, {
    required DateTime referenceDate,
    bool allowContextualLeadingPart = false,
  }) {
    final original = input.trim();
    if (original.isEmpty || maximumParts < 2) return null;
    final normalization = const NaturalLanguageNormalizer().normalize(original);
    if (normalization.preservedAmbiguities.contains(
          'critical_negation_scope',
        ) ||
        NaturalLanguageNormalizer.hasNegation(original)) {
      return null;
    }

    final parts = original
        .split(_separator)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2 || parts.length > maximumParts) return null;

    final domains = parts
        .map((part) => _domain(part, referenceDate))
        .toList(growable: false);
    if (domains.skip(1).any((domain) => domain == null)) return null;
    if (domains.first == null && !allowContextualLeadingPart) return null;

    final explicitDomains = domains.whereType<ConversationRequestDomain>();
    if (domains.first != null && explicitDomains.toSet().length < 2) {
      // Les demandes d'un même domaine restent la responsabilité de leur
      // parseur (par exemple plusieurs articles de courses).
      return null;
    }

    return ConversationCompoundRequest(
      parts: List.unmodifiable(parts),
      domains: List.unmodifiable(domains),
    );
  }

  static final RegExp _separator = RegExp(
    r'\s*(?:;|\n+|\bpuis\b|\bensuite\b|\bet\s+aussi\b|'
    r'\bet\b(?=\s+(?:(?:je\s+(?:veux|voudrais|souhaite)|tu\s+peux)\s+)?'
    r'(?:ajout\w*|achet\w*|cree?\w*|note\w*|rappel\w*|souviens\w*|'
    r'memoris\w*|retiens?\w*|planifi\w*|programm\w*|cale\w*|trouve\w*|'
    r'cherche\w*|propose\w*|annul\w*|supprim\w*|deplac\w*|decal\w*|'
    r'modifi\w*|change\w*)))\s*',
    caseSensitive: false,
  );

  static ConversationRequestDomain? _domain(
    String part,
    DateTime referenceDate,
  ) {
    if (MemoryEngineService.hasExplicitMemoryRequest(part)) {
      return ConversationRequestDomain.memory;
    }
    if (const ShoppingConversationIntentDetector()
        .classify(part)
        .isActionable) {
      return ConversationRequestDomain.shopping;
    }
    if (const TaskCreationDraftService().extract(
          part,
          referenceDate: referenceDate,
        ) !=
        null) {
      return ConversationRequestDomain.task;
    }
    final normalized =
        const NaturalLanguageNormalizer().normalize(part).normalizedText;
    if (RegExp(
      r'^(?:rappelle\s+moi|fais\s+moi\s+penser|je\s+dois|il\s+faut\s+que)\b',
    ).hasMatch(normalized)) {
      return ConversationRequestDomain.task;
    }
    if (NaturalEventRequestService.parseAction(
              part,
              now: referenceDate,
            ) !=
            null ||
        PlanningSearchRequestService.parse(part, now: referenceDate) != null) {
      return ConversationRequestDomain.event;
    }
    if (RegExp(
          r'\b(?:rendez\s+vous|dentiste|medecin|docteur|pediatre|kine|'
          r'osteopathe|coiffeur|coiffeuse|consultation|reunion|creneau)\b',
        ).hasMatch(normalized) &&
        RegExp(
          r'^(?:(?:je\s+(?:veux|voudrais|souhaite)|tu\s+peux)\s+)?'
          r'(?:ajoute|cree|note|planifie|programme|cale|trouve|cherche|'
          r'propose|annule|supprime|deplace|decale|modifie|change)\b',
        ).hasMatch(normalized)) {
      return ConversationRequestDomain.event;
    }
    return null;
  }
}
