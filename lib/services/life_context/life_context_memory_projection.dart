import '../../models/life_context/life_context_provenance.dart';
import '../../models/life_context/memory_context.dart';
import '../../models/memory_lifecycle_state.dart';
import '../../models/memory_semantic_identity.dart';

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
    final schemaVersion = _schemaVersion(snapshot['schemaVersion']);
    final validUntilValue = snapshot['validUntil'];
    final expiresAtValue = snapshot['expiresAt'];
    final validUntil = _earliest(
      _dateTime(validUntilValue),
      _dateTime(expiresAtValue),
    );
    final hasInvalidExpiration =
        _isInvalidDate(validUntilValue) || _isInvalidDate(expiresAtValue);
    final sensitivityDecision = _sensitivity(snapshot, category, text);
    final sensitivity = sensitivityDecision.sensitivity;
    final confirmationStatus = _confirmationStatus(snapshot);
    final lifecycleState = _lifecycleState(snapshot);
    final consumptionTrust = _consumptionTrust(
      snapshot,
      schemaVersion: schemaVersion,
      sourceId: sourceId,
      sensitivity: sensitivity,
      confirmationStatus: confirmationStatus,
      lifecycleState: lifecycleState,
      hasInvalidExpiration: hasInvalidExpiration,
      hasInvalidSensitivity: sensitivityDecision.invalid,
      hasRestrictedSecret: sensitivityDecision.restrictedSecret,
    );

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
      validUntil: validUntil,
      schemaVersion: schemaVersion,
      consumptionTrust: consumptionTrust,
      hasInvalidExpiration: hasInvalidExpiration,
      hasRestrictedSecret: sensitivityDecision.restrictedSecret,
      confirmationStatus: confirmationStatus,
      lifecycleState: lifecycleState,
      lifecycleStateIsExplicit: _hasText(snapshot['lifecycleState']) ||
          _hasText(snapshot['lifecycleStatus']) ||
          _hasText(snapshot['status']),
      confidence: _confidence(snapshot['confidence']),
      sensitivity: sensitivity,
      evidenceType: _evidenceType(snapshot['evidenceType']),
      isExplicitHealth: _isExplicitHealth(category),
      lastConfirmedAt: _dateTime(snapshot['confirmedAt']),
      structuredDomain: _nullableText(snapshot['structuredDomain']),
      structuredReferenceId: _nullableText(snapshot['structuredReferenceId']),
      semanticIdentityRead:
          MemorySemanticIdentity.read(snapshot['semanticIdentity']),
      memoryRevision: snapshot['memoryRevision'] is int
          ? snapshot['memoryRevision'] as int
          : null,
      semanticValue: _nullableText(snapshot['semanticValue']),
      accountScopeId: _nullableText(snapshot['accountScopeId']),
      legacyData: _unknownFields(snapshot),
    );
  }

  MemoryConsumptionTrust _consumptionTrust(
    Map<String, dynamic> snapshot, {
    required int schemaVersion,
    required String? sourceId,
    required LifeContextSensitivity sensitivity,
    required MemoryConfirmationStatus confirmationStatus,
    required MemoryLifecycleState lifecycleState,
    required bool hasInvalidExpiration,
    required bool hasInvalidSensitivity,
    required bool hasRestrictedSecret,
  }) {
    if (schemaVersion >= 1) {
      return _isCompleteModern(
        snapshot,
        hasInvalidExpiration || hasInvalidSensitivity,
      )
          ? MemoryConsumptionTrust.modernValid
          : MemoryConsumptionTrust.invalidModern;
    }
    if (schemaVersion < 0 ||
        hasInvalidExpiration ||
        hasInvalidSensitivity ||
        hasRestrictedSecret ||
        !_legacyMarkersAreCoherent(snapshot) ||
        _hasNegativeLegacyMarker(snapshot) ||
        _isDisallowedLegacySource(sourceId)) {
      return MemoryConsumptionTrust.legacyQuarantined;
    }

    final explicitConfirmation =
        confirmationStatus == MemoryConfirmationStatus.confirmed &&
            const {
              MemoryLifecycleState.confirmed,
              MemoryLifecycleState.active,
            }.contains(lifecycleState) &&
            _evidenceType(snapshot['evidenceType']) ==
                LifeContextEvidenceType.explicit &&
            _dateTime(snapshot['confirmedAt']) != null;
    final directUserSource = _isDirectUserSource(sourceId);
    if (sensitivity == LifeContextSensitivity.sensitive &&
        !explicitConfirmation) {
      return MemoryConsumptionTrust.legacyQuarantined;
    }
    if (sensitivity == LifeContextSensitivity.sensitive) {
      return MemoryConsumptionTrust.legacyQuarantined;
    }
    return directUserSource || explicitConfirmation
        ? MemoryConsumptionTrust.legacyTrusted
        : MemoryConsumptionTrust.legacyQuarantined;
  }

  bool _legacyMarkersAreCoherent(Map<String, dynamic> snapshot) {
    const textFields = {
      'lifecycleState',
      'lifecycleStatus',
      'confirmationStatus',
      'evidenceType',
      'status',
    };
    for (final field in textFields) {
      if (!snapshot.containsKey(field)) continue;
      final value = snapshot[field];
      if (value is! String || value.trim().isEmpty) return false;
    }
    for (final field in const {'active', 'confirmed'}) {
      if (snapshot.containsKey(field) && snapshot[field] is! bool) return false;
    }

    final lifecycleValues = [
      if (snapshot.containsKey('lifecycleState'))
        _normalized(snapshot['lifecycleState']),
      if (snapshot.containsKey('lifecycleStatus'))
        _normalized(snapshot['lifecycleStatus']),
      if (snapshot.containsKey('status')) _normalized(snapshot['status']),
    ];
    if (lifecycleValues.any(
          (value) =>
              !MemoryLifecycleState.values.any((state) => state.name == value),
        ) ||
        lifecycleValues.toSet().length > 1) {
      return false;
    }

    final lifecycle = lifecycleValues.isEmpty ? null : lifecycleValues.first;
    final confirmation = snapshot.containsKey('confirmationStatus')
        ? _normalized(snapshot['confirmationStatus'])
        : null;
    final evidence = snapshot.containsKey('evidenceType')
        ? _normalized(snapshot['evidenceType'])
        : null;
    if (confirmation != null &&
        !MemoryConfirmationStatus.values
            .any((status) => status.name == confirmation)) {
      return false;
    }
    if (evidence != null &&
        !LifeContextEvidenceType.values.any((type) => type.name == evidence)) {
      return false;
    }

    if (confirmation == 'confirmed' &&
        lifecycle != null &&
        !const {'confirmed', 'active'}.contains(lifecycle)) {
      return false;
    }
    if (confirmation == 'confirmed' &&
        evidence != null &&
        evidence != 'explicit') {
      return false;
    }
    if (confirmation == 'rejected' &&
        lifecycle != null &&
        lifecycle != 'rejected') {
      return false;
    }
    if (confirmation == 'obsolete' &&
        lifecycle != null &&
        !const {
          'superseded',
          'obsolete',
          'archived',
          'deleted',
          'expired',
        }.contains(lifecycle)) {
      return false;
    }
    if (snapshot['active'] == true &&
        lifecycle != null &&
        !const {'confirmed', 'active'}.contains(lifecycle)) {
      return false;
    }
    if (snapshot['active'] == false &&
        const {'confirmed', 'active'}.contains(lifecycle)) {
      return false;
    }
    if (snapshot['confirmed'] == true &&
        confirmation != null &&
        confirmation != 'confirmed') {
      return false;
    }
    if (snapshot['confirmed'] == false && confirmation == 'confirmed') {
      return false;
    }
    if (_isDirectUserSource(
          _nullableText(snapshot['sourceId']) ??
              _nullableText(snapshot['source']),
        ) &&
        evidence == 'derived') {
      return false;
    }
    return true;
  }

  bool _isCompleteModern(
    Map<String, dynamic> snapshot,
    bool hasInvalidExpiration,
  ) {
    final lifecycle = _normalized(
      snapshot['lifecycleState'] ??
          snapshot['lifecycleStatus'] ??
          snapshot['status'],
    );
    final confirmation = _normalized(snapshot['confirmationStatus']);
    final semanticType = _normalized(snapshot['semanticType']);
    return !hasInvalidExpiration &&
        _hasText(snapshot['accountScopeId']) &&
        (_hasText(snapshot['id']) || _hasText(snapshot['memoryId'])) &&
        _hasText(snapshot['text']) &&
        _hasText(snapshot['normalizedText']) &&
        _hasText(snapshot['category']) &&
        _hasText(snapshot['provenance']) &&
        MemoryLifecycleState.values.any((value) => value.name == lifecycle) &&
        MemoryConfirmationStatus.values
            .any((value) => value.name == confirmation) &&
        LifeMemorySemanticType.values
            .any((value) => value.name == semanticType);
  }

  bool _hasNegativeLegacyMarker(Map<String, dynamic> snapshot) {
    final lifecycle = _normalized(
      snapshot['lifecycleState'] ??
          snapshot['lifecycleStatus'] ??
          snapshot['status'],
    );
    final confirmation = _normalized(snapshot['confirmationStatus']);
    return const {
          'proposed',
          'rejected',
          'superseded',
          'obsolete',
          'archived',
          'deleted',
          'expired',
        }.contains(lifecycle) ||
        const {'unconfirmed', 'inferred', 'rejected', 'obsolete'}
            .contains(confirmation) ||
        snapshot['active'] == false ||
        snapshot['confirmed'] == false ||
        snapshot['deleted'] == true ||
        snapshot['archived'] == true ||
        snapshot['obsolete'] == true ||
        snapshot['rejected'] == true ||
        snapshot['expired'] == true ||
        snapshot['tombstone'] == true;
  }

  bool _isDirectUserSource(String? source) => const {
        'user',
        'explicit_user',
        'user_explicit',
        'manual',
        'user_confirmed',
        'confirmed_user',
      }.contains(_normalized(source));

  bool _isDisallowedLegacySource(String? source) {
    final normalized = _normalized(source);
    return const {
      'assistant',
      'ai',
      'ia',
      'inferred',
      'inference',
      'suggestion',
      'suggested',
      'model',
      'openai',
      'generated',
    }.any(
      (signal) =>
          normalized == signal ||
          normalized.startsWith('${signal}_') ||
          normalized.endsWith('_$signal'),
    );
  }

  int _schemaVersion(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString().trim()) ?? -1;
  }

  bool _hasText(dynamic value) => value?.toString().trim().isNotEmpty == true;

  String _normalized(dynamic value) =>
      value?.toString().trim().toLowerCase() ?? '';

  bool _isInvalidDate(dynamic value) =>
      value != null && _dateTime(value) == null;

  DateTime? _earliest(DateTime? first, DateTime? second) {
    if (first == null) return second?.toUtc();
    if (second == null) return first.toUtc();
    final firstUtc = first.toUtc();
    final secondUtc = second.toUtc();
    return firstUtc.isBefore(secondUtc) ? firstUtc : secondUtc;
  }

  bool _isExplicitHealth(String category) {
    final normalized = _normalizeCategory(category);
    return normalized == 'health' ||
        normalized == 'medical' ||
        normalized == 'sante';
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

  ({
    LifeContextSensitivity sensitivity,
    bool invalid,
    bool restrictedSecret,
  }) _sensitivity(
    Map<String, dynamic> snapshot,
    String category,
    String text,
  ) {
    final value = '${_normalizeCategory(category)} ${_normalizeText(text)}';
    final persisted = _persistedSensitivity(snapshot);
    final restrictedSecret = _containsAny(value, const [
      'mot de passe',
      'password',
      'code secret',
      'code pin',
      'code confidentiel',
      'jeton d acces',
      "jeton d'acces",
      'access token',
      'token d acces',
      "token d'acces",
      'cle d acces',
      "cle d'acces",
      'api key',
      'cle api',
      'numero de carte',
      'carte bancaire',
      'cryptogramme',
      'cvv',
    ]);
    const sensitiveSignals = [
      'health',
      'sante',
      'medical',
      'psychiatr',
      'psycholog',
      'depression',
      'anxiet',
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
      'iban',
      'bic',
      'compte bancaire',
      'carte bancaire',
      'administration',
      'administratif',
      'securite sociale',
      'numero fiscal',
      'identifiant fiscal',
      'identifiant administratif',
      'identifiant de connexion',
      'login',
      'photo',
      'adresse',
      'domicile',
      'geolocalisation',
      'localisation privee',
      'telephone',
      'sexualite',
      'orientation sexuelle',
      'religion',
      'religieux',
      'politique',
      'parti politique',
      'syndicat',
      'juridique',
      'penal',
      'casier judiciaire',
      'condamnation',
    ];

    final lexicalSensitivity =
        restrictedSecret || sensitiveSignals.any(value.contains);
    return (
      sensitivity: persisted.sensitive || lexicalSensitivity
          ? LifeContextSensitivity.sensitive
          : LifeContextSensitivity.standard,
      invalid: persisted.invalid,
      restrictedSecret: restrictedSecret,
    );
  }

  ({bool sensitive, bool invalid}) _persistedSensitivity(
    Map<String, dynamic> snapshot,
  ) {
    final decisions = <bool>[];
    for (final field in const {
      'sensitivity',
      'sensitivityLevel',
      'privacyCategory',
    }) {
      if (!snapshot.containsKey(field)) continue;
      final value = snapshot[field];
      if (value is! String || value.trim().isEmpty) {
        return (sensitive: true, invalid: true);
      }
      final normalized = _normalized(value);
      if (const {'sensitive', 'private', 'confidential', 'restricted'}
          .contains(normalized)) {
        decisions.add(true);
      } else if (const {'standard', 'ordinary', 'public'}
          .contains(normalized)) {
        decisions.add(false);
      } else {
        return (sensitive: true, invalid: true);
      }
    }
    if (snapshot.containsKey('sensitive')) {
      final value = snapshot['sensitive'];
      if (value is! bool) return (sensitive: true, invalid: true);
      decisions.add(value);
    }
    if (decisions.toSet().length > 1) {
      return (sensitive: true, invalid: true);
    }
    return (
      sensitive: decisions.isNotEmpty && decisions.single,
      invalid: false,
    );
  }

  bool _containsAny(String value, Iterable<String> signals) =>
      signals.any(value.contains);

  MemoryConfirmationStatus _confirmationStatus(Map<String, dynamic> snapshot) {
    final normalized =
        snapshot['confirmationStatus']?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      final lifecycle = (snapshot['lifecycleState'] ??
                  snapshot['lifecycleStatus'] ??
                  snapshot['status'])
              ?.toString()
              .trim()
              .toLowerCase() ??
          '';
      return switch (lifecycle) {
        'confirmed' || 'active' => MemoryConfirmationStatus.confirmed,
        'rejected' => MemoryConfirmationStatus.rejected,
        'obsolete' ||
        'superseded' ||
        'expired' =>
          MemoryConfirmationStatus.obsolete,
        _ => MemoryConfirmationStatus.unconfirmed,
      };
    }
    return MemoryConfirmationStatus.values.firstWhere(
      (status) => status.name == normalized,
      orElse: () => MemoryConfirmationStatus.unconfirmed,
    );
  }

  MemoryLifecycleState _lifecycleState(Map<String, dynamic> snapshot) {
    final stored = (snapshot['lifecycleState'] ??
            snapshot['lifecycleStatus'] ??
            snapshot['status'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (stored != null && stored.isNotEmpty) {
      return MemoryLifecycleState.values.firstWhere(
        (state) => state.name.toLowerCase() == stored,
        orElse: () => MemoryLifecycleState.proposed,
      );
    }
    final confirmation = _confirmationStatus(snapshot);
    return switch (confirmation) {
      MemoryConfirmationStatus.confirmed => MemoryLifecycleState.confirmed,
      MemoryConfirmationStatus.rejected => MemoryLifecycleState.rejected,
      MemoryConfirmationStatus.obsolete => MemoryLifecycleState.obsolete,
      _ => MemoryLifecycleState.proposed,
    };
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
      'expiresAt',
      'confirmationStatus',
      'lifecycleState',
      'lifecycleStatus',
      'status',
      'active',
      'confirmed',
      'schemaVersion',
      'memoryId',
      'accountScopeId',
      'semanticType',
      'provenance',
      'sensitivity',
      'sensitivityLevel',
      'sensitive',
      'privacyCategory',
      'confidence',
      'evidenceType',
      'confirmedAt',
      'structuredDomain',
      'structuredReferenceId',
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
