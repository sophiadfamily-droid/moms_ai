import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/natural_duration_service.dart';

void main() {
  group('NaturalDurationService contextual units', () {
    test('parses explicit duration expressions', () {
      expect(NaturalDurationService.parseMinutes('1h'), 60);
      expect(NaturalDurationService.parseMinutes('une heure'), 60);
      expect(NaturalDurationService.parseMinutes('45 min'), 45);
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
