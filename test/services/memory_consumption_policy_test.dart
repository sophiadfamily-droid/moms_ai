import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/services/life_context/life_context_memory_projection.dart';
import 'package:moms_ai/services/memory_consumption_policy.dart';

void main() {
  const projection = HistoricalMemoryContextProjection();
  final referenceDate = DateTime.utc(2026, 7, 20, 12);

  bool consumable(Map<String, dynamic> document) {
    final memory = projection.project([document]).memories.single;
    return MemoryConsumptionPolicy.isConsumable(
      memory,
      referenceDate: referenceDate,
    );
  }

  Map<String, dynamic> modern({
    String lifecycleState = 'active',
    String confirmationStatus = 'confirmed',
    Object? expiresAt,
  }) =>
      {
        'schemaVersion': 1,
        'id': 'modern-id',
        'memoryId': 'modern-id',
        'accountScopeId': 'account-a',
        'text': 'Je préfère le matin',
        'normalizedText': 'je prefere le matin',
        'category': 'preference',
        'semanticType': 'preference',
        'provenance': 'memory',
        'lifecycleState': lifecycleState,
        'confirmationStatus': confirmationStatus,
        if (expiresAt != null) 'expiresAt': expiresAt,
      };

  Map<String, dynamic> legacyFirestoreDocument({
    String source = 'user',
    String text = 'Je préfère le matin',
    String category = 'preferences',
  }) {
    final timestamp = Timestamp.fromDate(DateTime.utc(2026, 7, 1, 8));
    return {
      'id': 'legacy-id',
      'text': text,
      'normalizedText': text.trim().toLowerCase(),
      'category': category,
      'importance': 2,
      'createdAt': timestamp,
      'updatedAt': timestamp,
      'source': source,
    };
  }

  test('keeps only an explicitly user-authored legacy memory consumable', () {
    expect(
      consumable({
        'id': 'legacy-user',
        'text': 'Je préfère le matin',
        'category': 'preference',
        'source': 'user',
      }),
      isTrue,
    );
    for (final source in ['ai', 'inferred', 'assistant', 'suggestion']) {
      expect(
        consumable({
          'id': source,
          'text': 'Peut-être le matin',
          'category': 'preference',
          'source': source,
        }),
        isFalse,
      );
    }
  });

  test('quarantines sensitive legacy data even with historical confirmation',
      () {
    expect(
      consumable({
        'id': 'legacy-sensitive',
        'text': 'Adresse privée',
        'category': 'address',
        'source': 'user',
      }),
      isFalse,
    );
    expect(
      consumable({
        'id': 'legacy-sensitive-confirmed',
        'text': 'Adresse privée',
        'category': 'address',
        'source': 'user',
        'confirmationStatus': 'confirmed',
        'lifecycleState': 'active',
        'evidenceType': 'explicit',
        'confirmedAt': DateTime.utc(2026, 7, 1),
      }),
      isFalse,
    );
  });

  test('quarantines the exact historical source chat Firestore shape', () {
    final document = legacyFirestoreDocument(source: 'chat');
    final before = Map<String, dynamic>.from(document);
    final memory = projection.project([document]).memories.single;

    expect(memory.consumptionTrust, MemoryConsumptionTrust.legacyQuarantined);
    expect(
      MemoryConsumptionPolicy.isConsumable(
        memory,
        referenceDate: referenceDate,
      ),
      isFalse,
    );
    expect(document, before);
  });

  test('rejects unknown and contradictory legacy markers', () {
    final invalidDocuments = [
      {
        ...legacyFirestoreDocument(),
        'lifecycleState': 'banana',
      },
      {
        ...legacyFirestoreDocument(),
        'lifecycleState': 'proposed',
        'confirmationStatus': 'confirmed',
      },
      {
        ...legacyFirestoreDocument(),
        'lifecycleState': 'active',
        'confirmationStatus': 'confirmed',
        'evidenceType': 'derived',
      },
      {
        ...legacyFirestoreDocument(),
        'lifecycleState': 'rejected',
        'active': true,
      },
      {
        ...legacyFirestoreDocument(),
        'lifecycleState': 'active',
        'lifecycleStatus': 'confirmed',
      },
      {
        ...legacyFirestoreDocument(),
        'lifecycleState': 1,
      },
    ];

    expect(invalidDocuments.map(consumable), everyElement(isFalse));
  });

  test('accepts a complete coherent set of legacy markers', () {
    expect(
      consumable({
        ...legacyFirestoreDocument(),
        'lifecycleState': 'active',
        'lifecycleStatus': 'active',
        'status': 'active',
        'confirmationStatus': 'confirmed',
        'evidenceType': 'explicit',
        'active': true,
        'confirmed': true,
        'confirmedAt': DateTime.utc(2026, 7, 1),
      }),
      isTrue,
    );
  });

  test('classifies persisted and lexical sensitive legacy data fail closed',
      () {
    final sensitiveDocuments = [
      {
        ...legacyFirestoreDocument(text: 'Valeur personnelle'),
        'sensitivity': 'sensitive',
      },
      {
        ...legacyFirestoreDocument(text: 'Mon mot de passe est secret'),
      },
      {
        ...legacyFirestoreDocument(
          text: 'Mon numéro de sécurité sociale est enregistré',
        ),
      },
      {
        ...legacyFirestoreDocument(text: 'Mon IBAN est enregistré'),
      },
      {
        ...legacyFirestoreDocument(text: 'Mon orientation sexuelle'),
      },
      {
        ...legacyFirestoreDocument(text: 'Ma religion'),
      },
    ];

    expect(sensitiveDocuments.map(consumable), everyElement(isFalse));
    final persisted =
        projection.project([sensitiveDocuments.first]).memories.single;
    expect(persisted.sensitivity, LifeContextSensitivity.sensitive);
  });

  test('rejects unknown or contradictory persisted sensitivity markers', () {
    expect(
      consumable({
        ...legacyFirestoreDocument(),
        'sensitivity': 'mystery',
      }),
      isFalse,
    );
    expect(
      consumable({
        ...legacyFirestoreDocument(),
        'sensitivity': 'standard',
        'sensitive': true,
      }),
      isFalse,
    );
  });

  test('never consumes credentials even from a confirmed modern document', () {
    expect(
      consumable({
        ...modern(),
        'text': 'Mon code secret est 1234',
        'normalizedText': 'mon code secret est 1234',
      }),
      isFalse,
    );
  });

  test('fails closed for incomplete or corrupt modern documents', () {
    expect(consumable({...modern()}..remove('confirmationStatus')), isFalse);
    expect(
      consumable(modern(expiresAt: 'not-a-date')),
      isFalse,
    );
    expect(consumable(modern()), isTrue);
  });

  test('expires before and exactly at the injected reference date', () {
    expect(
      consumable(
          modern(expiresAt: referenceDate.add(const Duration(seconds: 1)))),
      isTrue,
    );
    expect(consumable(modern(expiresAt: referenceDate)), isFalse);
    expect(
      consumable(
        modern(expiresAt: referenceDate.subtract(const Duration(seconds: 1))),
      ),
      isFalse,
    );
    expect(
      consumable({
        'id': 'legacy-expired',
        'text': 'Routine',
        'category': 'routine',
        'source': 'user',
        'validUntil': referenceDate,
      }),
      isFalse,
    );
  });

  test('excludes every non-consumable lifecycle state', () {
    for (final state in [
      'proposed',
      'rejected',
      'superseded',
      'obsolete',
      'archived',
      'deleted',
      'expired',
    ]) {
      expect(
        consumable(
          modern(
            lifecycleState: state,
            confirmationStatus:
                state == 'proposed' ? 'unconfirmed' : 'obsolete',
          ),
        ),
        isFalse,
        reason: state,
      );
    }
  });

  test('filters a mixed legacy and modern read deterministically', () {
    final context = projection.project([
      {
        'id': 'legacy-user',
        'text': 'Mémoire fiable',
        'category': 'fact',
        'source': 'user',
      },
      {
        'id': 'legacy-ai',
        'text': 'Déduction',
        'category': 'fact',
        'source': 'ai',
      },
      modern(),
      {...modern()}..remove('accountScopeId'),
    ]);

    expect(
      MemoryConsumptionPolicy.consumable(
        context.memories,
        referenceDate: referenceDate,
      ).map((memory) => memory.id),
      ['legacy-user', 'modern-id'],
    );
  });
}
