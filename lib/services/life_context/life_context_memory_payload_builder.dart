import '../../models/life_context/life_context_provenance.dart';
import '../../models/life_context/memory_context.dart';
import 'life_context_memory_serializer.dart';

final class LifeContextMemoryPayloadBuilder {
  const LifeContextMemoryPayloadBuilder();

  List<Map<String, dynamic>> build({
    required MemoryContext context,
    required String message,
    int limit = 12,
  }) {
    final selected = select(
      context: context,
      message: message,
      limit: limit,
    );
    return selected.memories
        .map(LifeContextMemorySerializer.toBackendMap)
        .toList(growable: false);
  }

  MemoryContext select({
    required MemoryContext context,
    required String message,
    int limit = 12,
  }) {
    if (limit <= 0 || context.isEmpty) return MemoryContext.empty;

    final query = _normalize(message);
    final queryWords = _keywords(query);
    final planningRequest = _containsAny(query, const [
      'planif',
      'organis',
      'creneau',
      'disponib',
      'agenda',
      'rendez-vous',
      'rdv',
    ]);
    final sensitiveDomains = _requestedSensitiveDomains(query);

    final scored = context.memories.where((memory) {
      if (memory.text.trim().isEmpty) return false;
      if (memory.sensitivity == LifeContextSensitivity.sensitive &&
          !_isSensitiveMemoryRequested(memory, sensitiveDomains)) {
        return false;
      }
      return true;
    }).map((memory) {
      return (
        memory: memory,
        score: _score(
          memory,
          queryWords: queryWords,
          planningRequest: planningRequest,
        ),
      );
    }).where((entry) {
      return entry.score > 0;
    }).toList()
      ..sort((first, second) {
        final score = second.score.compareTo(first.score);
        if (score != 0) return score;
        final importance =
            second.memory.importance.compareTo(first.memory.importance);
        if (importance != 0) return importance;
        return _dateRank(second.memory).compareTo(_dateRank(first.memory));
      });

    return MemoryContext(
      memories: scored.take(limit).map((entry) => entry.memory).toList(),
    );
  }

  int _score(
    LifeMemoryFact memory, {
    required Set<String> queryWords,
    required bool planningRequest,
  }) {
    final memoryWords = _keywords(
      '${memory.normalizedText} ${memory.category} ${memory.semanticType.name}',
    );
    final sharedWords = memoryWords.intersection(queryWords).length;
    var score = sharedWords * 4;

    if (planningRequest &&
        const {
          LifeMemorySemanticType.routine,
          LifeMemorySemanticType.constraint,
          LifeMemorySemanticType.preference,
        }.contains(memory.semanticType)) {
      score += 4;
    }

    if (_categoryMatches(memory.category, queryWords)) score += 3;
    if (score > 0) score += memory.importance;
    return score;
  }

  bool _categoryMatches(String category, Set<String> queryWords) {
    final normalized = _normalize(category);
    const aliases = <String, Set<String>>{
      'children': {'enfant', 'fils', 'fille', 'ecole', 'creche'},
      'partner': {'mari', 'femme', 'conjoint', 'partenaire'},
      'family': {'famille', 'parent', 'enfant'},
      'health': {'sante', 'medecin', 'medical', 'allergie'},
      'finance': {'budget', 'banque', 'facture', 'argent'},
      'work': {'travail', 'bureau', 'client', 'reunion'},
      'routine': {'routine', 'habitude', 'planning', 'agenda'},
      'preferences': {'prefere', 'preference'},
      'preference': {'prefere', 'preference'},
      'constraint': {'contrainte', 'indisponible', 'disponible'},
    };
    final categoryWords = aliases[normalized] ?? {normalized};
    return categoryWords.any(queryWords.contains);
  }

  Set<String> _requestedSensitiveDomains(String query) {
    final domains = <String>{};
    if (_containsAny(query, const [
      'sante',
      'medical',
      'medecin',
      'allerg',
      'traitement',
      'urgence',
    ])) {
      domains.add('health');
    }
    if (_containsAny(query, const [
      'enfant',
      'fils',
      'fille',
      'ecole',
      'creche',
      'mineur',
    ])) {
      domains.add('children');
    }
    if (_containsAny(query, const [
      'budget',
      'finance',
      'banque',
      'facture',
      'administr',
    ])) {
      domains.add('finance');
    }
    return domains;
  }

  bool _isSensitiveMemoryRequested(
    LifeMemoryFact memory,
    Set<String> requestedDomains,
  ) {
    final value = _normalize('${memory.category} ${memory.text}');
    if (requestedDomains.contains('health') &&
        _containsAny(value, const [
          'health',
          'sante',
          'medical',
          'medecin',
          'allerg',
          'urgence',
        ])) {
      return true;
    }
    if (requestedDomains.contains('children') &&
        _containsAny(value, const [
          'children',
          'child',
          'enfant',
          'fils',
          'fille',
          'ecole',
          'mineur',
        ])) {
      return true;
    }
    if (requestedDomains.contains('finance') &&
        _containsAny(value, const [
          'finance',
          'budget',
          'banque',
          'facture',
          'administr',
        ])) {
      return true;
    }
    return false;
  }

  int _dateRank(LifeMemoryFact memory) {
    return (memory.updatedAt ?? memory.createdAt)?.millisecondsSinceEpoch ?? 0;
  }

  Set<String> _keywords(String value) {
    const stopWords = {
      'avec',
      'dans',
      'pour',
      'mais',
      'cette',
      'comment',
      'quoi',
      'quel',
      'quelle',
      'mes',
      'mon',
      'une',
      'des',
      'les',
    };
    return _normalize(value)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length >= 4 && !stopWords.contains(word))
        .toSet();
  }

  bool _containsAny(String value, List<String> signals) {
    return signals.any(value.contains);
  }

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ç', 'c');
  }
}
