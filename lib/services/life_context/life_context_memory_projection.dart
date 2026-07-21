import '../../models/life_context/life_context_provenance.dart';
import '../../models/life_context/memory_context.dart';

abstract interface class LifeContextMemoryProjection {
  MemoryContext project(Iterable<Map<String, dynamic>> documents);
}

final class HistoricalMemoryContextProjection
    implements LifeContextMemoryProjection {
  const HistoricalMemoryContextProjection();

  @override
  MemoryContext project(Iterable<Map<String, dynamic>> documents) {
    return MemoryContext(
      memories: documents.map(_projectMemory).toList(),
    );
  }

  LifeMemoryFact _projectMemory(Map<String, dynamic> document) {
    final snapshot = Map<String, dynamic>.from(document);
    final text = snapshot['text']?.toString() ?? '';
    final normalizedText = _normalizeText(
      snapshot['normalizedText']?.toString() ?? text,
    );
    final category = snapshot['category']?.toString().trim() ?? '';
    final sourceId = _nullableText(snapshot['sourceId']) ??
        _nullableText(snapshot['source']);

    return LifeMemoryFact(
      id: snapshot['id']?.toString() ?? '',
      text: text,
      normalizedText: normalizedText,
      semanticType: _semanticType(category, text),
      category: category,
      importance: _boundedImportance(snapshot['importance']),
      sourceType: LifeContextSourceType.memory,
      sourceId: sourceId,
      createdAt: _dateTime(snapshot['createdAt'] ?? snapshot['createdAtIso']),
      updatedAt: _dateTime(snapshot['updatedAt']),
      validFrom: _dateTime(snapshot['validFrom']),
      validUntil: _dateTime(snapshot['validUntil']),
      confirmationStatus: _confirmationStatus(
        snapshot['confirmationStatus'],
      ),
      confidence: _confidence(snapshot['confidence']),
      sensitivity: _sensitivity(category, text),
      evidenceType: _evidenceType(snapshot['evidenceType']),
      legacyData: _unknownFields(snapshot),
    );
  }

  LifeMemorySemanticType _semanticType(String category, String text) {
    final normalizedCategory = _normalizeCategory(category);

    switch (normalizedCategory) {
      case 'preference':
      case 'preferences':
        return LifeMemorySemanticType.preference;
      case 'routine':
        return LifeMemorySemanticType.routine;
      case 'constraint':
      case 'constraints':
        return LifeMemorySemanticType.constraint;
      case 'goal':
      case 'goals':
        return LifeMemorySemanticType.goal;
      case 'decision':
        return LifeMemorySemanticType.decision;
      case 'temporary':
        return LifeMemorySemanticType.temporary;
      case 'relationship':
        return LifeMemorySemanticType.relationship;
      case 'project':
      case 'projects':
        return _isExplicitGoalProject(text)
            ? LifeMemorySemanticType.goal
            : LifeMemorySemanticType.unknown;
      case 'fact':
        return LifeMemorySemanticType.fact;
      default:
        return LifeMemorySemanticType.unknown;
    }
  }

  bool _isExplicitGoalProject(String text) {
    final normalized = _normalizeText(text);
    return normalized.startsWith('mon projet ') ||
        normalized.startsWith('notre projet ') ||
        normalized.contains('objectif du projet') ||
        normalized.contains('objectif de mon projet');
  }

  LifeContextSensitivity _sensitivity(String category, String text) {
    final value = '${_normalizeCategory(category)} ${_normalizeText(text)}';
    const sensitiveSignals = [
      'health',
      'sante',
      'medical',
      'allerg',
      'doctor',
      'medecin',
      'children',
      'child',
      'enfant',
      'ecole',
      'mineur',
      'emergency',
      'urgence',
      'finance',
      'budget',
      'banque',
      'administration',
      'administratif',
      'photo',
      'adresse',
      'telephone',
    ];

    return sensitiveSignals.any(value.contains)
        ? LifeContextSensitivity.sensitive
        : LifeContextSensitivity.standard;
  }

  MemoryConfirmationStatus _confirmationStatus(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return MemoryConfirmationStatus.values.firstWhere(
      (status) => status.name == normalized,
      orElse: () => MemoryConfirmationStatus.unconfirmed,
    );
  }

  LifeContextEvidenceType _evidenceType(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return LifeContextEvidenceType.values.firstWhere(
      (type) => type.name == normalized,
      orElse: () => LifeContextEvidenceType.historical,
    );
  }

  double? _confidence(dynamic value) {
    if (value == null) return null;
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value.toString().trim());
    if (parsed == null || parsed < 0 || parsed > 1) return null;
    return parsed;
  }

  int _boundedImportance(dynamic value) {
    final parsed = int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed.clamp(0, 3);
  }

  DateTime? _dateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    try {
      final converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Historical values are not guaranteed to be Firestore timestamps.
    }
    return DateTime.tryParse(value.toString().trim());
  }

  String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _normalizeCategory(String value) {
    return _normalizeText(value).replaceAll(' ', '_');
  }

  String _normalizeText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('’', "'")
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ç', 'c');
  }

  Map<String, Object?> _unknownFields(Map<String, dynamic> source) {
    const knownFields = {
      'id',
      'text',
      'normalizedText',
      'category',
      'importance',
      'source',
      'sourceId',
      'createdAt',
      'createdAtIso',
      'updatedAt',
      'validFrom',
      'validUntil',
      'confirmationStatus',
      'confidence',
      'evidenceType',
    };
    return Map.unmodifiable(
      Map<String, Object?>.fromEntries(
        source.entries
            .where((entry) => !knownFields.contains(entry.key))
            .map((entry) => MapEntry(entry.key, entry.value)),
      ),
    );
  }
}
