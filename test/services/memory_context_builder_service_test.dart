import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/services/memory_context_builder_service.dart';

class FakeFirestoreTimestamp {
  final DateTime value;

  const FakeFirestoreTimestamp(this.value);

  DateTime toDate() => value;
}

void main() {
  group('MemoryContextBuilderService', () {
    test('preserves a DateTime as an ISO creation date', () {
      final result = MemoryContextBuilderService.buildRelevantMemoryPayload(
        memories: [
          {
            'text': 'Routine importante',
            'category': 'routine',
            'importance': 3,
            'createdAt': DateTime(2026, 7, 16, 10, 30),
          },
        ],
      );

      expect(result, hasLength(1));
      expect(
        result.first['createdAtIso'],
        '2026-07-16T10:30:00.000',
      );
    });

    test('supports a Firestore-like timestamp exposing toDate', () {
      final result = MemoryContextBuilderService.buildRelevantMemoryPayload(
        memories: [
          {
            'text': 'Mémoire Firestore',
            'category': 'personal',
            'importance': 2,
            'createdAt': FakeFirestoreTimestamp(
              DateTime(2026, 7, 15, 18, 45),
            ),
          },
        ],
      );

      expect(result.first['createdAtIso'], '2026-07-15T18:45:00.000');
    });

    test('supports an ISO date stored as text', () {
      final result = MemoryContextBuilderService.buildRelevantMemoryPayload(
        memories: const [
          {
            'text': 'Ancienne mémoire',
            'category': 'personal',
            'importance': 1,
            'createdAt': '2026-07-14T08:15:00.000',
          },
        ],
      );

      expect(result.first['createdAtIso'], '2026-07-14T08:15:00.000');
    });

    test('omits the creation date when the value is invalid', () {
      final result = MemoryContextBuilderService.buildRelevantMemoryPayload(
        memories: const [
          {
            'text': 'Mémoire sans date valide',
            'category': 'personal',
            'importance': 1,
            'createdAt': 'date-invalide',
          },
        ],
      );

      expect(result.first.containsKey('createdAtIso'), false);
    });

    test('keeps importance ordering and creation metadata', () {
      final result = MemoryContextBuilderService.buildRelevantMemoryPayload(
        memories: [
          {
            'text': 'Importance faible',
            'category': 'personal',
            'importance': 1,
            'createdAt': DateTime(2026, 7, 16, 12),
          },
          {
            'text': 'Importance forte',
            'category': 'routine',
            'importance': 3,
            'createdAt': DateTime(2026, 7, 15, 12),
          },
        ],
      );

      expect(result.first['text'], 'Importance forte');
      expect(result.first['importance'], 3);
      expect(result.first['createdAtIso'], '2026-07-15T12:00:00.000');
    });
  });
}
