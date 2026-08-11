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

    test('recognizes natural French memory requests before their subject', () {
      const formulations = [
        'Souviens toi que je préfère les rdv le matin',
        'Souviens-toi que je préfère les rendez-vous le matin',
        'Rappelle toi que je préfère les rendez-vous le matin',
        'Retiens que je préfère les rendez-vous le matin',
        'Mémorise que je préfère les rendez-vous le matin',
        'Garde ça en mémoire : je préfère les rendez-vous le matin',
        'Note bien que je préfère les rendez-vous le matin',
        'N’oublie pas que je préfère les rendez-vous le matin',
      ];

      for (final text in formulations) {
        expect(
          MemoryPipelineService.shouldProcessMemory(text),
          isTrue,
          reason: text,
        );
      }
    });

    test('never treats natural French questions as memories', () {
      const questions = [
        'À quel moment de ma journée je préfère faire mes activités',
        'Quelle activité est-ce que je préfère',
        'Quels sont mes rendez-vous habituels',
        'Combien de temps je préfère prévoir',
        'Quand est-ce que je fais mes courses',
        'Peux-tu me dire ce que je préfère',
        'Dis-moi quand je préfère faire du sport',
      ];

      for (final question in questions) {
        expect(
          MemoryPipelineService.shouldProcessMemory(question),
          isFalse,
          reason: question,
        );
      }
    });

    test('preserves a preference importance score', () {
      const text = 'Je préfère les rendez-vous l’après-midi.';

      final memory = MemoryPipelineService.buildMemory(text);
      final payload = MemoryPipelineService.buildSavePayload(
        memory,
        fallbackText: text,
      );

      expect(payload.category, 'preference');
      expect(payload.importance, 2);
    });

    test('classifies preferences by meaning rather than by their topic', () {
      const formulations = [
        'Je préfère faire mes courses le matin.',
        'Je préfère faire du sport le soir.',
        'Je préfère mes rendez-vous médicaux l’après-midi.',
        'Je préfère voir ma famille le dimanche.',
      ];

      for (final text in formulations) {
        expect(
          MemoryPipelineService.buildMemory(text)['category'],
          'preference',
          reason: text,
        );
      }
    });

    test('classifies family birthdays as important dates', () {
      expect(
        MemoryPipelineService.buildMemory(
          "L'anniversaire de ma mère est le 12 mars.",
        )['category'],
        'important_date',
      );
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
