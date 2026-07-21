import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/life_context/life_context_memory_payload_builder.dart';
import 'package:moms_ai/services/life_context/life_context_memory_projection.dart';

void main() {
  const projection = HistoricalMemoryContextProjection();
  const builder = LifeContextMemoryPayloadBuilder();

  test('selects relevant memories and respects the limit', () {
    final context = projection.project([
      {
        'id': 'work',
        'text': 'Je travaille au bureau le lundi',
        'category': 'work',
        'importance': 2,
      },
      {
        'id': 'food',
        'text': 'Je préfère les pâtes',
        'category': 'preferences',
        'importance': 3,
      },
    ]);

    final payload = builder.build(
      context: context,
      message: 'Comment organiser mon travail au bureau ?',
      limit: 1,
    );

    expect(payload, hasLength(1));
    expect(payload.single['text'], 'Je travaille au bureau le lundi');
  });

  test('excludes sensitive memories unless their domain is requested', () {
    final context = projection.project([
      {
        'text': 'Mon enfant est allergique aux arachides',
        'category': 'children',
        'importance': 3,
      },
    ]);

    expect(
      builder.build(context: context, message: 'Organise ma journée'),
      isEmpty,
    );
    expect(
      builder.build(
        context: context,
        message: 'Quelle allergie concerne mon enfant ?',
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
        'source': 'chat',
        'createdAt': '2026-07-01T08:00:00.000Z',
      },
    ]);

    final payload = builder.build(
      context: context,
      message: 'Planifie un créneau lundi',
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
      ),
      isEmpty,
    );
  });
}
