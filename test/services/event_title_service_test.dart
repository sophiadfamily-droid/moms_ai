import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/event_title_service.dart';

void main() {
  group('EventTitleService', () {
    test('detects only closed generic Event titles', () {
      for (final title in <String>[
        'Rendez-vous',
        'rdv',
        'rendez vous',
        'appointment',
        'rendez-vous demain',
        'mon rendez-vous',
        'un rendez-vous',
      ]) {
        expect(EventTitleService.isGeneric(title), isTrue, reason: title);
      }
      for (final title in <String>[
        'rendez-vous dentiste',
        'consultation médecin',
        'rendez-vous banque',
        'entretien école',
        'contrôle technique',
        'rendez-vous mutuelle',
        'coiffeur',
        'pédiatre',
      ]) {
        expect(EventTitleService.isGeneric(title), isFalse, reason: title);
      }
    });

    test('builds a clean informative title from bounded motifs', () {
      expect(
          EventTitleService.titleFromMotif('dentiste'), 'Rendez-vous dentiste');
      expect(EventTitleService.titleFromMotif('banque'), 'Rendez-vous banque');
      expect(EventTitleService.titleFromMotif('contrôle technique'),
          'Contrôle technique');
      expect(EventTitleService.titleFromMotif('entretien école'),
          'Entretien école');
      expect(EventTitleService.titleFromMotif('rendez-vous mutuelle'),
          'Rendez-vous mutuelle');
    });

    test('rejects insufficient motifs and independent requests', () {
      for (final answer in <String>[
        'ça',
        'lui',
        'un truc',
        'je sais pas',
        'rendez-vous',
        'quelles sont mes priorités ?',
        'ajoute du lait aux courses',
        'annule mon rendez-vous de lundi',
      ]) {
        expect(EventTitleService.titleFromMotif(answer), isNull,
            reason: answer);
      }
    });
  });
}
