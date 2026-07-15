import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/memory_pipeline_service.dart';

void main() {
  group('MemoryPipelineService', () {
    test('preserves a high importance score for an explicit memory', () {
      const text = 'Souviens-toi que mon fils va à l’école le lundi.';

      final memory = MemoryPipelineService.buildMemory(text);
      final payload = MemoryPipelineService.buildSavePayload(
        memory,
        fallbackText: text,
      );

      expect(payload.text, text);
      expect(payload.category, 'children');
      expect(payload.importance, 3);
    });

    test('preserves a preference importance score', () {
      const text = 'Je préfère les rendez-vous l’après-midi.';

      final memory = MemoryPipelineService.buildMemory(text);
      final payload = MemoryPipelineService.buildSavePayload(
        memory,
        fallbackText: text,
      );

      expect(payload.category, 'preferences');
      expect(payload.importance, 2);
    });

    test('uses safe fallbacks for incomplete memory data', () {
      final payload = MemoryPipelineService.buildSavePayload(
        {
          'text': '',
          'category': '',
          'importance': 'invalid',
        },
        fallbackText: 'Information de secours',
      );

      expect(payload.text, 'Information de secours');
      expect(payload.category, 'personal');
      expect(payload.importance, 0);
    });

    test('clamps an external importance value to the supported range', () {
      final payload = MemoryPipelineService.buildSavePayload(
        {
          'text': 'Préférence',
          'category': 'preferences',
          'importance': 99,
        },
        fallbackText: '',
      );

      expect(payload.importance, 3);
    });
  });
}
