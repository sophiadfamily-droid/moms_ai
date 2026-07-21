final class ConversationContextPrivacyFilter {
  const ConversationContextPrivacyFilter();

  Map<String, dynamic> filterProfile({
    required Map<String, dynamic> profile,
    required String message,
  }) {
    final filtered = _withoutPhotoPaths(profile);
    final relevance = _relevance(message);

    if (!relevance.health) {
      for (final key in const [
        'allergies',
        'medicalNotes',
        'bloodType',
        'doctorName',
        'emergencyContactName',
        'emergencyContactPhone',
      ]) {
        filtered.remove(key);
      }
    }

    if (!relevance.children) {
      filtered.remove('children');
      filtered.remove('childcareInfo');
    } else if (!relevance.health && filtered['children'] is List) {
      filtered['children'] = (filtered['children'] as List).map((child) {
        if (child is! Map) return child;
        final clean = Map<String, dynamic>.from(child);
        for (final key in const [
          'allergies',
          'doctor',
          'medicalNotes',
        ]) {
          clean.remove(key);
        }
        return clean;
      }).toList();
    }

    if (!relevance.finance) filtered.remove('budgetNotes');
    if (!relevance.administration) filtered.remove('adminNotes');
    filtered.remove('personalNotes');
    return filtered;
  }

  Map<String, dynamic> filterStructuredProfile({
    required Map<String, dynamic> profileContext,
    required String message,
  }) {
    final filtered = _withoutPhotoPaths(profileContext);
    final relevance = _relevance(message);
    if (!relevance.health) filtered.remove('health');
    if (!relevance.children) filtered.remove('children');

    final family = filtered['family'];
    if (!relevance.children && family is Map) {
      final clean = Map<String, dynamic>.from(family);
      clean.remove('childrenCount');
      clean.remove('childcareInfo');
      filtered['family'] = clean;
    }

    final planningReasoning = filtered['planningReasoning'];
    if (planningReasoning is List) {
      filtered['planningReasoning'] = planningReasoning.where((item) {
        if (item is! Map) return true;
        final sourceType = item['sourceType']?.toString() ?? '';
        return relevance.children || !sourceType.startsWith('child_');
      }).map((item) {
        if (item is! Map) return item;
        final clean = Map<String, dynamic>.from(item);
        clean.remove('source');
        return clean;
      }).toList();
    }

    final lifeContext = filtered['lifeContext'];
    if (lifeContext is Map) {
      final clean = Map<String, dynamic>.from(lifeContext);
      clean.remove('personalNotes');
      if (!relevance.finance) clean.remove('budgetNotes');
      if (!relevance.administration) clean.remove('adminNotes');
      filtered['lifeContext'] = clean;
    }
    return filtered;
  }

  Map<String, dynamic> _withoutPhotoPaths(Map<String, dynamic> source) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      if (entry.key.toLowerCase().contains('photopath')) continue;
      final value = entry.value;
      if (value is Map) {
        result[entry.key] = _withoutPhotoPaths(
          Map<String, dynamic>.from(value),
        );
      } else if (value is List) {
        result[entry.key] = value.map((item) {
          return item is Map
              ? _withoutPhotoPaths(Map<String, dynamic>.from(item))
              : item;
        }).toList();
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  _ConversationDataRelevance _relevance(String message) {
    final value = _normalize(message);
    return _ConversationDataRelevance(
      health: _containsAny(value, const [
        'sante',
        'medical',
        'medecin',
        'allerg',
        'traitement',
        'urgence',
      ]),
      children: _containsAny(value, const [
        'enfant',
        'fils',
        'fille',
        'ecole',
        'creche',
      ]),
      finance: _containsAny(value, const [
        'budget',
        'finance',
        'banque',
        'facture',
        'argent',
      ]),
      administration: _containsAny(value, const [
        'administr',
        'dossier',
        'document',
        'declaration',
      ]),
    );
  }

  bool _containsAny(String value, List<String> signals) {
    return signals.any(value.contains);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ç', 'c');
  }
}

final class _ConversationDataRelevance {
  final bool health;
  final bool children;
  final bool finance;
  final bool administration;

  const _ConversationDataRelevance({
    required this.health,
    required this.children,
    required this.finance,
    required this.administration,
  });
}
