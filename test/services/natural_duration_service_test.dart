import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/natural_duration_service.dart';

void main() {
  group('NaturalDurationService contextual units', () {
    test('parses explicit duration expressions', () {
      expect(NaturalDurationService.parseMinutes('1h'), 60);
      expect(NaturalDurationService.parseMinutes('une heure'), 60);
      expect(NaturalDurationService.parseMinutes('45 min'), 45);
    });

    test('extracts a duration embedded in a slot-search request', () {
      expect(
        NaturalDurationService.parseMinutes(
          'Propose-moi un créneau d’une heure pour le dentiste',
        ),
        60,
      );
      expect(
        NaturalDurationService.parseMinutes(
          'Trouve-moi un créneau de 45 minutes pour le médecin',
        ),
        45,
      );
      expect(
        NaturalDurationService.parseMinutes(
          'Cherche un horaire de 1 h 30 pour le garage',
        ),
        90,
      );
      expect(
        NaturalDurationService.parseMinutes(
          'Trouve un moment pour un rendez-vous qui dure deux heures',
        ),
        120,
      );
    });

    test('does not confuse a start time or a time range with a duration', () {
      expect(
        NaturalDurationService.parseMinutes(
          'Propose-moi un créneau pour le dentiste à 15 heures',
        ),
        0,
      );
      expect(
        NaturalDurationService.parseMinutes(
          'Trouve-moi un créneau pour le dentiste de 15 heures à 16 heures',
        ),
        0,
      );
    });

    test('uses minutes for a bare number under an explicit field contract', () {
      for (final field in NaturalDurationExpectedField.values) {
        expect(
          NaturalDurationService.parseMinutes('5', expectedField: field),
          5,
          reason: field.name,
        );
        expect(
          NaturalDurationService.parseMinutes('10', expectedField: field),
          10,
          reason: field.name,
        );
      }
      expect(
        NaturalDurationService.parseMinutes(
          '30',
          expectedField: NaturalDurationExpectedField.duration,
        ),
        30,
      );
    });

    test('keeps explicit hours under travel and margin contracts', () {
      for (final field in <NaturalDurationExpectedField>[
        NaturalDurationExpectedField.travelGo,
        NaturalDurationExpectedField.travelBack,
        NaturalDurationExpectedField.margin,
      ]) {
        expect(
          NaturalDurationService.parseMinutes('1h', expectedField: field),
          60,
          reason: field.name,
        );
      }
    });
  });
}
