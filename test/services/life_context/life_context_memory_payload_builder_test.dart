import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/life_context/life_context_memory_payload_builder.dart';
import 'package:moms_ai/services/life_context/life_context_memory_projection.dart';

void main() {
  const projection = HistoricalMemoryContextProjection();
  const builder = LifeContextMemoryPayloadBuilder();
  final referenceDate = DateTime.utc(2026, 7, 20);

  test('selects relevant memories and respects the limit', () {
    final context = projection.project([
      {
        'id': 'work',
        'text': 'Je travaille au bureau le lundi',
        'category': 'work',
        'importance': 2,
        'source': 'user',
      },
      {
        'id': 'food',
        'text': 'Je préfère les pâtes',
        'category': 'preferences',
        'importance': 3,
        'source': 'user',
      },
    ]);

    final payload = builder.build(
      context: context,
      message: 'Comment organiser mon travail au bureau ?',
      referenceDate: referenceDate,
      limit: 1,
    );

    expect(payload, hasLength(1));
    expect(payload.single['text'], 'Je travaille au bureau le lundi');
  });

  test('excludes sensitive memories unless their domain is requested', () {
    final context = projection.project([
      {
        'schemaVersion': 1,
        'id': 'confirmed-sensitive',
        'memoryId': 'confirmed-sensitive',
        'accountScopeId': 'account-a',
        'text': 'Mon enfant est allergique aux arachides',
        'normalizedText': 'mon enfant est allergique aux arachides',
        'category': 'children',
        'semanticType': 'fact',
        'provenance': 'memory',
        'importance': 3,
        'source': 'user',
        'confirmationStatus': 'confirmed',
        'lifecycleState': 'active',
        'evidenceType': 'explicit',
        'confirmedAt': referenceDate.subtract(const Duration(days: 1)),
      },
    ]);

    expect(
      builder.build(
        context: context,
        message: 'Organise ma journée',
        referenceDate: referenceDate,
      ),
      isEmpty,
    );
    expect(
      builder.build(
        context: context,
        message: 'Quelle allergie concerne mon enfant ?',
        referenceDate: referenceDate,
      ),
      hasLength(1),
    );
  });

  test('serializes only the established backend memory contract', () {
    final context = projection.project([
      {
        'id': 'secret-internal-id',
        'text': 'Routine du lundi',
        'category': 'routine',
        'importance': 3,
        'source': 'user',
        'createdAt': '2026-07-01T08:00:00.000Z',
      },
    ]);

    final payload = builder.build(
      context: context,
      message: 'Planifie un créneau lundi',
      referenceDate: referenceDate,
    );

    expect(payload.single.keys, {
      'text',
      'category',
      'importance',
      'createdAtIso',
    });
    expect(payload.single.containsKey('id'), isFalse);
    expect(payload.single.containsKey('source'), isFalse);
  });

  test('supports an empty context', () {
    expect(
      builder.build(
        context: projection.project(const []),
        message: 'Bonjour',
        referenceDate: referenceDate,
      ),
      isEmpty,
    );
  });

  test('does not send an expired memory to chat', () {
    final context = projection.project([
      {
        'id': 'expired',
        'text': 'Je travaille au bureau le lundi',
        'category': 'work',
        'source': 'user',
        'expiresAt': referenceDate,
      },
    ]);

    expect(
      builder.build(
        context: context,
        message: 'Comment organiser mon travail au bureau ?',
        referenceDate: referenceDate,
      ),
      isEmpty,
    );
  });

  test('does not send an ambiguous source chat memory to chat', () {
    final createdAt = DateTime.utc(2026, 7, 1, 8);
    final context = projection.project([
      {
        'id': 'legacy-chat',
        'text': 'Je préfère travailler le matin',
        'normalizedText': 'je préfère travailler le matin',
        'category': 'preferences',
        'importance': 2,
        'createdAt': createdAt,
        'updatedAt': createdAt,
        'source': 'chat',
      },
    ]);

    expect(
      builder.build(
        context: context,
        message: 'Quand est-ce que je préfère travailler ?',
        referenceDate: referenceDate,
      ),
      isEmpty,
    );
  });

  test('excludes explicit proposals but preserves historical fallback', () {
    final context = projection.project([
      {
        'id': 'proposal',
        'text': 'Routine proposée lundi',
        'category': 'routine',
        'source': 'user',
        'lifecycleState': 'proposed',
      },
      {
        'id': 'historical',
        'text': 'Routine historique lundi',
        'category': 'routine',
        'source': 'user',
      },
    ]);

    final result = const LifeContextMemoryPayloadBuilder().select(
      context: context,
      message: 'Planifie lundi selon ma routine',
      referenceDate: referenceDate,
    );

    expect(result.memories.map((memory) => memory.id), ['historical']);
  });
}
