import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';

void main() {
  group('EntityAlias', () {
    test('preserves display text and computes deterministic normalization', () {
      final alias = _alias('  Primary Place  ');

      expect(alias.value, 'Primary Place');
      expect(alias.normalizedValue, 'primary place');
      expect(alias.isActiveAt(_date), isTrue);
    });

    test('honors temporary validity and removal boundaries', () {
      final temporary = _alias(
        'Temporary Place',
        kind: EntityAliasKind.temporary,
        validFrom: _date,
        validUntil: _date.add(const Duration(days: 2)),
      );
      final removed = _alias(
        'Old Place',
        removedAt: _date.add(const Duration(days: 1)),
      );

      expect(temporary.isActiveAt(_date), isTrue);
      expect(temporary.isActiveAt(_date.add(const Duration(days: 3))), isFalse);
      expect(removed.isActiveAt(_date), isTrue);
      expect(removed.isActiveAt(_date.add(const Duration(days: 1))), isFalse);
    });

    test('rejects empty, incoherent and invalid dated aliases', () {
      expect(() => _alias('...'), throwsA(_domain('empty_alias_value')));
      expect(
        () => EntityAlias(
          value: 'Place',
          normalizedValue: 'other',
          kind: EntityAliasKind.explicit,
          source: _source,
          createdAt: _date,
        ),
        throwsA(_domain('incoherent_alias_normalization')),
      );
      expect(
        () => _alias('Place',
            validFrom: _date,
            validUntil: _date.subtract(const Duration(days: 1))),
        throwsA(_domain('invalid_alias_validity_range')),
      );
      expect(
        () => _alias('Place', kind: EntityAliasKind.temporary),
        throwsA(_domain('temporary_alias_requires_end_date')),
      );
      expect(
        () =>
            _alias('Place', removedAt: _date.subtract(const Duration(days: 1))),
        throwsA(_domain('invalid_alias_removal_date')),
      );
    });
  });

  group('LifeEntity', () {
    test('builds active, deleted and merged domain entities', () {
      expect(_entity().isNormallyResolvable, isTrue);
      expect(
          _entity(status: EntityStatus.deleted).isNormallyResolvable, isFalse);
      expect(
        _entity(status: EntityStatus.merged, mergedIntoEntityId: 'entity-2')
            .isNormallyResolvable,
        isFalse,
      );
    });

    test('validates identity, label, normalization and dates consistently', () {
      expect(() => _entity(id: ' '), throwsA(_domain('invalid_entity_id')));
      expect(() => _entity(label: '...'),
          throwsA(_domain('empty_canonical_label')));
      expect(
        () => LifeEntity(
          id: 'entity-1',
          type: EntityType.person,
          canonicalLabel: 'Person A',
          normalizedLabel: 'other',
          status: EntityStatus.active,
          source: _source,
          createdAt: _date,
          updatedAt: _date,
        ),
        throwsA(_domain('incoherent_entity_normalization')),
      );
      expect(
        () => _entity(updatedAt: _date.subtract(const Duration(days: 1))),
        throwsA(_domain('invalid_entity_dates')),
      );
      expect(() => _entity(schemaVersion: 0),
          throwsA(_domain('invalid_entity_schema_version')));
    });

    test('validates merge invariants', () {
      expect(
        () => _entity(status: EntityStatus.merged),
        throwsA(_domain('merged_entity_requires_target')),
      );
      expect(
        () => _entity(status: EntityStatus.merged, mergedIntoEntityId: ' '),
        throwsA(_domain('invalid_merge_target_id')),
      );
      expect(
        () => _entity(
            status: EntityStatus.merged, mergedIntoEntityId: 'entity-1'),
        throwsA(_domain('entity_cannot_merge_into_itself')),
      );
      expect(
        () => _entity(mergedIntoEntityId: 'entity-2'),
        throwsA(_domain('merge_target_requires_merged_status')),
      );
    });

    test('rejects duplicate active aliases after normalization', () {
      expect(
        () => _entity(aliases: [_alias('École'), _alias('ecole')]),
        throwsA(_domain('duplicate_active_alias')),
      );
    });

    test('defensively freezes aliases and nested metadata', () {
      final aliases = [_alias('Alias A')];
      final nested = <String, Object?>{
        'list': <Object?>['value'],
        'map': <String, Object?>{'key': 'value'},
      };
      final entity = _entity(aliases: aliases, metadata: nested);
      aliases.add(_alias('Alias B'));
      (nested['list']! as List<Object?>).add('changed');
      (nested['map']! as Map<String, Object?>)['other'] = 'changed';

      expect(entity.aliases, hasLength(1));
      expect(entity.metadata['list'], ['value']);
      expect(entity.metadata['map'], {'key': 'value'});
      expect(
          () => entity.aliases.add(_alias('Alias C')), throwsUnsupportedError);
      expect(
        () => (entity.metadata['list']! as List<Object?>).add('changed'),
        throwsUnsupportedError,
      );
    });
  });
}

final _date = DateTime.utc(2026, 1, 10);
const _source = EntitySource(type: EntitySourceType.user);

EntityAlias _alias(
  String value, {
  EntityAliasKind kind = EntityAliasKind.explicit,
  DateTime? validFrom,
  DateTime? validUntil,
  DateTime? removedAt,
}) =>
    EntityAlias.fromValue(
      value: value,
      kind: kind,
      source: _source,
      createdAt: _date,
      validFrom: validFrom,
      validUntil: validUntil,
      removedAt: removedAt,
    );

LifeEntity _entity({
  String id = 'entity-1',
  String label = 'Person A',
  EntityType type = EntityType.person,
  List<EntityAlias> aliases = const [],
  EntityStatus status = EntityStatus.active,
  DateTime? updatedAt,
  Map<String, Object?> metadata = const {},
  String? mergedIntoEntityId,
  int schemaVersion = 1,
}) =>
    LifeEntity.fromLabel(
      id: id,
      type: type,
      canonicalLabel: label,
      aliases: aliases,
      status: status,
      source: _source,
      createdAt: _date,
      updatedAt: updatedAt ?? _date,
      metadata: metadata,
      mergedIntoEntityId: mergedIntoEntityId,
      schemaVersion: schemaVersion,
    );

Matcher _domain(String code) =>
    isA<EntityDomainException>().having((error) => error.code, 'code', code);
