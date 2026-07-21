import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/services/life_context/life_context_memory_projection.dart';

void main() {
  const projection = HistoricalMemoryContextProjection();

  group('HistoricalMemoryContextProjection', () {
    test('projects a complete historical memory without losing metadata', () {
      final createdAt = DateTime.utc(2026, 7, 1, 8);
      final updatedAt = DateTime.utc(2026, 7, 2, 9);
      final context = projection.project([
        {
          'id': 'memory-1',
          'text': 'Je préfère les rendez-vous l’après-midi.',
          'normalizedText': 'je préfère les rendez-vous l’après-midi.',
          'category': 'preferences',
          'importance': 2,
          'source': 'chat',
          'createdAt': createdAt,
          'updatedAt': updatedAt,
          'validFrom': '2026-07-01T00:00:00.000Z',
          'validUntil': '2026-12-31T00:00:00.000Z',
          'confirmationStatus': 'confirmed',
          'confidence': 0.8,
          'evidenceType': 'explicit',
          'historicalFlag': true,
        },
      ]);

      final memory = context.memories.single;
      expect(memory.id, 'memory-1');
      expect(memory.text, 'Je préfère les rendez-vous l’après-midi.');
      expect(memory.normalizedText, "je prefere les rendez-vous l'apres-midi.");
      expect(memory.semanticType, LifeMemorySemanticType.preference);
      expect(memory.category, 'preferences');
      expect(memory.importance, 2);
      expect(memory.sourceType, LifeContextSourceType.memory);
      expect(memory.sourceId, 'chat');
      expect(memory.createdAt, createdAt);
      expect(memory.updatedAt, updatedAt);
      expect(memory.validFrom, DateTime.parse('2026-07-01T00:00:00.000Z'));
      expect(memory.validUntil, DateTime.parse('2026-12-31T00:00:00.000Z'));
      expect(memory.confirmationStatus, MemoryConfirmationStatus.confirmed);
      expect(memory.confidence, 0.8);
      expect(memory.evidenceType, LifeContextEvidenceType.explicit);
      expect(memory.legacyData['historicalFlag'], true);
    });

    test('projects missing fields without inventing evidence', () {
      final memory = projection
          .project([
            {'text': 'Information historique'},
          ])
          .memories
          .single;

      expect(memory.id, '');
      expect(memory.normalizedText, 'information historique');
      expect(memory.category, '');
      expect(memory.semanticType, LifeMemorySemanticType.unknown);
      expect(memory.createdAt, isNull);
      expect(memory.updatedAt, isNull);
      expect(memory.validFrom, isNull);
      expect(memory.validUntil, isNull);
      expect(memory.confidence, isNull);
      expect(
        memory.confirmationStatus,
        MemoryConfirmationStatus.unconfirmed,
      );
      expect(memory.evidenceType, LifeContextEvidenceType.historical);
    });

    test('supports both historical preference category spellings', () {
      final memories = projection.project([
        {'text': 'A', 'category': 'preference'},
        {'text': 'B', 'category': 'preferences'},
      ]).memories;

      expect(
        memories.map((memory) => memory.semanticType),
        everyElement(LifeMemorySemanticType.preference),
      );
    });

    test('supports routine and constraint categories', () {
      final memories = projection.project([
        {'text': 'Routine', 'category': 'routine'},
        {'text': 'Contrainte', 'category': 'constraint'},
      ]).memories;

      expect(memories[0].semanticType, LifeMemorySemanticType.routine);
      expect(memories[1].semanticType, LifeMemorySemanticType.constraint);
    });

    test('keeps an unknown category unknown', () {
      final memory = projection
          .project([
            {'text': 'Texte', 'category': 'custom-domain'},
          ])
          .memories
          .single;

      expect(memory.semanticType, LifeMemorySemanticType.unknown);
    });

    test('only treats an explicitly described project as a goal', () {
      final memories = projection.project([
        {'text': 'Client projet facture', 'category': 'project'},
        {
          'text': 'Mon projet est de lancer une entreprise',
          'category': 'project',
        },
      ]).memories;

      expect(memories[0].semanticType, LifeMemorySemanticType.unknown);
      expect(memories[1].semanticType, LifeMemorySemanticType.goal);
    });

    test('marks health and child or school memories as sensitive', () {
      final memories = projection.project([
        {'text': 'Allergie connue', 'category': 'health'},
        {'text': 'École de mon enfant', 'category': 'children'},
      ]).memories;

      expect(
        memories,
        everyElement(
          isA<LifeMemoryFact>().having(
            (memory) => memory.sensitivity,
            'sensitivity',
            LifeContextSensitivity.sensitive,
          ),
        ),
      );
    });

    test('keeps ordinary memories standard', () {
      final memory = projection
          .project([
            {
              'text': 'Je préfère travailler le matin',
              'category': 'preferences'
            },
          ])
          .memories
          .single;

      expect(memory.sensitivity, LifeContextSensitivity.standard);
    });

    test('does not mutate the source and exposes immutable collections', () {
      final source = <String, dynamic>{
        'id': 'memory-1',
        'text': 'Texte',
        'category': 'unknown',
        'extra': 'préservé',
        'nested': {
          'items': ['a'],
        },
      };
      final before = Map<String, dynamic>.from(source);
      final context = projection.project([source]);

      expect(source, before);
      expect(
        () => context.memories.add(context.memories.single),
        throwsUnsupportedError,
      );
      expect(
        () => context.memories.single.legacyData['extra'] = 'modifié',
        throwsUnsupportedError,
      );
      final nested = context.memories.single.legacyData['nested'] as Map;
      final items = nested['items'] as List;
      expect(() => items.add('b'), throwsUnsupportedError);
    });

    test('is deterministic and preserves possible contradictions separately',
        () {
      final source = [
        {
          'id': 'first',
          'text': 'Je préfère le matin',
          'category': 'preference',
        },
        {
          'id': 'second',
          'text': 'Je préfère l’après-midi',
          'category': 'preference',
        },
      ];

      final first = projection.project(source);
      final second = projection.project(source);

      expect(first.toJson(), second.toJson());
      expect(first.memories, hasLength(2));
      expect(first.memories.map((memory) => memory.id), ['first', 'second']);
    });

    test('supports an empty historical list', () {
      expect(projection.project(const []).isEmpty, isTrue);
    });
  });
}
