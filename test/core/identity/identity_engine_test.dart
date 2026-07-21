import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_candidate.dart';
import 'package:moms_ai/core/identity/entity_reference.dart';
import 'package:moms_ai/core/identity/entity_resolution.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/identity_engine.dart';
import 'package:moms_ai/core/identity/life_entity.dart';

void main() {
  group('EntityReference', () {
    test('validates explicit IDs and normalized text', () {
      expect(_idReference('entity-1').explicitEntityId, 'entity-1');
      expect(_textReference('  Person A  ').normalizedValue, 'person a');
      expect(
        () => _idReference(' '),
        throwsA(_domain('explicit_reference_requires_id')),
      );
      expect(
        () => _textReference('...'),
        throwsA(_domain('text_reference_requires_value')),
      );
    });

    test('requires a relation key and validates conversation target IDs', () {
      expect(
        () => _textReference('my child',
            kind: EntityReferenceKind.relationalExpression),
        throwsA(_domain('relational_reference_requires_key')),
      );
      expect(
        () => _textReference('them', conversationTargetEntityId: ' '),
        throwsA(_domain('invalid_conversation_target_id')),
      );
    });
  });

  group('IdentityEngine validation and explicit ID', () {
    test('rejects more than twenty candidates without truncation', () {
      final result = _resolve(
        _textReference('Person A'),
        List.generate(21, (index) => _candidate(id: 'entity-$index')),
      );

      expect(result.status, EntityResolutionStatus.invalid);
      expect(
          result.signals, contains(EntityMatchSignal.candidateLimitExceeded));
    });

    test('rejects duplicate candidate IDs', () {
      final result = _resolve(
        _textReference('Person A'),
        [_candidate(), _candidate(label: 'Person B')],
      );

      expect(result.status, EntityResolutionStatus.invalid);
      expect(result.signals, contains(EntityMatchSignal.duplicateEntityId));
    });

    test('resolves an exact ID with exact confidence and compatible type', () {
      final result = _resolve(
        _idReference('entity-1', expectedType: EntityType.person),
        [_candidate()],
      );

      expect(result.status, EntityResolutionStatus.resolved);
      expect(result.resolvedEntity?.id, 'entity-1');
      expect(result.confidence, EntityResolutionConfidence.exact);
      expect(
          result.signals,
          containsAll([
            EntityMatchSignal.exactId,
            EntityMatchSignal.expectedTypeMatched,
          ]));
    });

    test('does not use text fallback for a missing explicit ID', () {
      final result = _resolve(
        _idReference('entity-2'),
        [_candidate(label: 'entity-2')],
      );

      expect(result.status, EntityResolutionStatus.notFound);
      expect(result.reasonCodes, ['explicit_id_not_found']);
    });

    test('rejects an explicit ID with incompatible type', () {
      final result = _resolve(
        _idReference('entity-1', expectedType: EntityType.place),
        [_candidate()],
      );

      expect(result.status, EntityResolutionStatus.invalid);
      expect(result.signals, contains(EntityMatchSignal.typeMismatch));
    });

    test('excludes deleted and inactive explicit entities', () {
      final deleted = _resolve(
        _idReference('entity-1'),
        [_candidate(status: EntityStatus.deleted)],
      );
      final inactive = _resolve(
        _idReference('entity-1'),
        [_candidate(status: EntityStatus.inactive)],
      );

      expect(deleted.status, EntityResolutionStatus.notFound);
      expect(deleted.signals, contains(EntityMatchSignal.deletedEntityIgnored));
      expect(inactive.status, EntityResolutionStatus.notFound);
    });
  });

  group('conversation and relation resolution', () {
    test('resolves one explicit conversation target for a pronoun', () {
      final result = _resolve(
        _textReference('them', kind: EntityReferenceKind.pronoun),
        [_candidate(explicitTarget: true), _candidate(id: 'entity-2')],
      );

      expect(result.status, EntityResolutionStatus.resolved);
      expect(result.resolvedEntity?.id, 'entity-1');
      expect(result.confidence, EntityResolutionConfidence.strong);
      expect(result.signals,
          contains(EntityMatchSignal.explicitConversationTarget));
    });

    test('requires context for a pronoun and never chooses list order', () {
      final result = _resolve(
        _textReference('them', kind: EntityReferenceKind.pronoun),
        [_candidate(id: 'entity-2'), _candidate(id: 'entity-1')],
      );

      expect(result.status, EntityResolutionStatus.needsConfirmation);
      expect(result.resolvedEntity, isNull);
      expect(result.signals, contains(EntityMatchSignal.missingContext));
    });

    test('handles absent, incompatible and multiple explicit targets safely',
        () {
      final absent = _resolve(
        _textReference('them',
            kind: EntityReferenceKind.pronoun,
            conversationTargetEntityId: 'entity-3'),
        [_candidate()],
      );
      final incompatible = _resolve(
        _textReference('them',
            kind: EntityReferenceKind.pronoun,
            expectedType: EntityType.place,
            conversationTargetEntityId: 'entity-1'),
        [_candidate()],
      );
      final multiple = _resolve(
        _textReference('them', kind: EntityReferenceKind.pronoun),
        [
          _candidate(explicitTarget: true),
          _candidate(id: 'entity-2', explicitTarget: true),
        ],
      );

      expect(absent.status, EntityResolutionStatus.needsConfirmation);
      expect(incompatible.status, EntityResolutionStatus.notFound);
      expect(multiple.status, EntityResolutionStatus.ambiguous);
    });

    test('resolves only one matching verified relation', () {
      final reference = _textReference(
        'my child',
        kind: EntityReferenceKind.relationalExpression,
        relationKey: 'child',
      );
      final unique = _resolve(reference, [
        _candidate(relationKey: 'child', relationVerified: true),
        _candidate(id: 'entity-2', relationKey: 'child'),
      ]);
      final none = _resolve(reference, [_candidate(relationKey: 'child')]);
      final many = _resolve(reference, [
        _candidate(relationKey: 'child', relationVerified: true),
        _candidate(
            id: 'entity-2', relationKey: 'child', relationVerified: true),
      ]);

      expect(unique.status, EntityResolutionStatus.resolved);
      expect(unique.signals, contains(EntityMatchSignal.verifiedRelation));
      expect(none.status, EntityResolutionStatus.notFound);
      expect(many.status, EntityResolutionStatus.ambiguous);
    });

    test('filters verified relations by expected type', () {
      final result = _resolve(
        _textReference(
          'my workplace',
          kind: EntityReferenceKind.relationalExpression,
          relationKey: 'workplace',
          expectedType: EntityType.place,
        ),
        [_candidate(relationKey: 'workplace', relationVerified: true)],
      );

      expect(result.status, EntityResolutionStatus.notFound);
    });
  });

  group('exact alias and canonical label resolution', () {
    test('resolves a unique active exact alias across accents and apostrophes',
        () {
      final result = _resolve(
        _textReference("L'Ecole"),
        [
          _candidate(aliases: [_alias('L’École')])
        ],
      );

      expect(result.status, EntityResolutionStatus.resolved);
      expect(result.signals, contains(EntityMatchSignal.exactAlias));
      expect(result.confidence, EntityResolutionConfidence.strong);
    });

    test('keeps duplicate exact aliases ambiguous regardless of order', () {
      final first =
          _candidate(id: 'entity-1', aliases: [_alias('Shared Alias')]);
      final second =
          _candidate(id: 'entity-2', aliases: [_alias('Shared Alias')]);

      final forward = _resolve(_textReference('shared alias'), [first, second]);
      final reverse = _resolve(_textReference('shared alias'), [second, first]);

      expect(forward.status, EntityResolutionStatus.ambiguous);
      expect(forward.candidates.map((item) => item.entity.id),
          reverse.candidates.map((item) => item.entity.id));
    });

    test('ignores expired and removed aliases with explicit signals', () {
      final expired = _resolve(
        _textReference('Old Alias'),
        [
          _candidate(aliases: [
            _alias('Old Alias',
                kind: EntityAliasKind.temporary,
                validUntil: _date.subtract(const Duration(days: 1))),
          ])
        ],
      );
      final removed = _resolve(
        _textReference('Removed Alias'),
        [
          _candidate(aliases: [
            _alias('Removed Alias', removedAt: _date),
          ])
        ],
      );

      expect(expired.status, EntityResolutionStatus.notFound);
      expect(expired.signals, contains(EntityMatchSignal.expiredAliasIgnored));
      expect(removed.signals, contains(EntityMatchSignal.inactiveAliasIgnored));
    });

    test('ignores aliases with an incompatible expected type', () {
      final result = _resolve(
        _textReference('Alias A', expectedType: EntityType.place),
        [
          _candidate(aliases: [_alias('Alias A')])
        ],
      );

      expect(result.status, EntityResolutionStatus.notFound);
      expect(result.signals, contains(EntityMatchSignal.typeMismatch));
    });

    test('returns ambiguity for alias versus another canonical label', () {
      final result = _resolve(_textReference('Shared Label'), [
        _candidate(label: 'Person A', aliases: [_alias('Shared Label')]),
        _candidate(id: 'entity-2', label: 'Shared Label'),
      ]);

      expect(result.status, EntityResolutionStatus.ambiguous);
      expect(
          result.signals,
          containsAll([
            EntityMatchSignal.exactAlias,
            EntityMatchSignal.exactCanonicalLabel,
          ]));
    });

    test('resolves one canonical label and preserves ambiguity for duplicates',
        () {
      final unique = _resolve(_textReference('person a'), [_candidate()]);
      final ambiguous = _resolve(_textReference('Person A'), [
        _candidate(),
        _candidate(id: 'entity-2'),
      ]);

      expect(unique.status, EntityResolutionStatus.resolved);
      expect(unique.signals, contains(EntityMatchSignal.exactCanonicalLabel));
      expect(ambiguous.status, EntityResolutionStatus.ambiguous);
    });

    test('ignores inactive labels and does not depend on candidate order', () {
      final inactive = _resolve(
        _textReference('Person A'),
        [_candidate(status: EntityStatus.inactive)],
      );
      final first = _resolve(_textReference('Person B'), [
        _candidate(id: 'entity-2', label: 'Person B'),
        _candidate(id: 'entity-1'),
      ]);
      final second = _resolve(_textReference('Person B'), [
        _candidate(id: 'entity-1'),
        _candidate(id: 'entity-2', label: 'Person B'),
      ]);

      expect(inactive.status, EntityResolutionStatus.notFound);
      expect(
          inactive.signals, contains(EntityMatchSignal.inactiveEntityIgnored));
      expect(first.resolvedEntity?.id, second.resolvedEntity?.id);
    });
  });

  group('merged entities', () {
    test('redirects an exact merged ID one level to an active target', () {
      final result = _resolve(_idReference('entity-1'), [
        _candidate(status: EntityStatus.merged, mergedIntoEntityId: 'entity-2'),
        _candidate(id: 'entity-2'),
      ]);

      expect(result.status, EntityResolutionStatus.resolved);
      expect(result.resolvedEntity?.id, 'entity-2');
      expect(result.confidence, EntityResolutionConfidence.strong);
      expect(result.signals, contains(EntityMatchSignal.mergedRedirect));
    });

    test('requires confirmation when the merge target is absent', () {
      final result = _resolve(
        _idReference('entity-1'),
        [
          _candidate(
              status: EntityStatus.merged, mergedIntoEntityId: 'entity-2')
        ],
      );

      expect(result.status, EntityResolutionStatus.needsConfirmation);
    });

    test('detects a merge cycle and refuses deeper chains', () {
      final cycle = _resolve(_idReference('entity-1'), [
        _candidate(status: EntityStatus.merged, mergedIntoEntityId: 'entity-2'),
        _candidate(
          id: 'entity-2',
          status: EntityStatus.merged,
          mergedIntoEntityId: 'entity-1',
        ),
      ]);
      final chain = _resolve(_idReference('entity-1'), [
        _candidate(status: EntityStatus.merged, mergedIntoEntityId: 'entity-2'),
        _candidate(
          id: 'entity-2',
          status: EntityStatus.merged,
          mergedIntoEntityId: 'entity-3',
        ),
        _candidate(id: 'entity-3'),
      ]);

      expect(cycle.status, EntityResolutionStatus.invalid);
      expect(cycle.reasonCodes, ['merge_cycle_detected']);
      expect(chain.status, EntityResolutionStatus.needsConfirmation);
      expect(chain.reasonCodes, ['merge_depth_exceeded']);
    });

    test('does not redirect to deleted or incompatible targets', () {
      final deleted = _resolve(_idReference('entity-1'), [
        _candidate(status: EntityStatus.merged, mergedIntoEntityId: 'entity-2'),
        _candidate(id: 'entity-2', status: EntityStatus.deleted),
      ]);
      final wrongType = _resolve(
        _idReference('entity-1', expectedType: EntityType.person),
        [
          _candidate(
              status: EntityStatus.merged, mergedIntoEntityId: 'entity-2'),
          _candidate(id: 'entity-2', type: EntityType.place),
        ],
      );

      expect(deleted.status, EntityResolutionStatus.needsConfirmation);
      expect(deleted.signals, contains(EntityMatchSignal.deletedEntityIgnored));
      expect(wrongType.status, EntityResolutionStatus.needsConfirmation);
      expect(wrongType.signals, contains(EntityMatchSignal.typeMismatch));
    });
  });

  group('EntityResolution invariants and immutability', () {
    test('factories enforce coherent status and confidence', () {
      expect(
        () => EntityResolution.resolved(
          entity: _candidate().entity,
          confidence: EntityResolutionConfidence.insufficient,
          signals: const [],
          reasonCode: 'test',
        ),
        throwsA(_domain('resolved_requires_sufficient_confidence')),
      );
      expect(
        () => EntityResolution.ambiguous(
          candidates: [_candidate()],
          signals: const [],
          reasonCode: 'test',
        ),
        throwsA(_domain('ambiguous_requires_candidates')),
      );
      final invalid = EntityResolution.invalid(
        signals: const [],
        reasonCode: 'invalid_input',
      );
      expect(invalid.confidence, EntityResolutionConfidence.insufficient);
    });

    test('defensively freezes candidate, signal and reason collections', () {
      final candidates = [_candidate(), _candidate(id: 'entity-2')];
      final signals = [EntityMatchSignal.multipleCandidates];
      final result = EntityResolution.ambiguous(
        candidates: candidates,
        signals: signals,
        reasonCode: 'multiple_candidates',
      );
      candidates.clear();
      signals.clear();

      expect(result.candidates, hasLength(2));
      expect(result.signals, [EntityMatchSignal.multipleCandidates]);
      expect(() => result.candidates.clear(), throwsUnsupportedError);
      expect(() => result.reasonCodes.add('other'), throwsUnsupportedError);
    });

    test('is deterministic and does not mutate candidate inputs', () {
      final candidates = [
        _candidate(id: 'entity-2', label: 'Person B'),
        _candidate(id: 'entity-1'),
      ];
      final originalOrder = candidates.map((item) => item.entity.id).toList();
      final first = _resolve(_textReference('Person B'), candidates);
      final second = _resolve(_textReference('Person B'), candidates);

      expect(first.status, second.status);
      expect(first.resolvedEntity?.id, second.resolvedEntity?.id);
      expect(first.signals, second.signals);
      expect(candidates.map((item) => item.entity.id), originalOrder);
    });
  });
}

final _date = DateTime.utc(2026, 1, 10);
const _source = EntitySource(type: EntitySourceType.user);
const _engine = IdentityEngine();

EntityResolution _resolve(
  EntityReference reference,
  List<EntityCandidate> candidates,
) =>
    _engine.resolve(
      reference: reference,
      candidates: candidates,
      referenceDate: _date,
    );

EntityReference _idReference(String id, {EntityType? expectedType}) =>
    EntityReference.byId(
      entityId: id,
      expectedType: expectedType,
      source: _source,
    );

EntityReference _textReference(
  String value, {
  EntityReferenceKind kind = EntityReferenceKind.canonicalLabel,
  EntityType? expectedType,
  String? relationKey,
  String? conversationTargetEntityId,
}) =>
    EntityReference.text(
      value: value,
      kind: kind,
      expectedType: expectedType,
      relationKey: relationKey,
      conversationTargetEntityId: conversationTargetEntityId,
      source: _source,
    );

EntityAlias _alias(
  String value, {
  EntityAliasKind kind = EntityAliasKind.explicit,
  DateTime? validUntil,
  DateTime? removedAt,
}) =>
    EntityAlias.fromValue(
      value: value,
      kind: kind,
      source: _source,
      createdAt: _date.subtract(const Duration(days: 10)),
      validUntil: validUntil,
      removedAt: removedAt,
    );

EntityCandidate _candidate({
  String id = 'entity-1',
  String label = 'Person A',
  EntityType type = EntityType.person,
  List<EntityAlias> aliases = const [],
  EntityStatus status = EntityStatus.active,
  String? mergedIntoEntityId,
  String? relationKey,
  bool relationVerified = false,
  bool explicitTarget = false,
}) =>
    EntityCandidate(
      entity: LifeEntity.fromLabel(
        id: id,
        type: type,
        canonicalLabel: label,
        aliases: aliases,
        status: status,
        source: _source,
        createdAt: _date.subtract(const Duration(days: 20)),
        updatedAt: _date.subtract(const Duration(days: 10)),
        mergedIntoEntityId: mergedIntoEntityId,
      ),
      relationSignals: relationKey == null
          ? const []
          : [
              EntityRelationSignal(
                relationKey: relationKey,
                isVerified: relationVerified,
                source: _source,
              ),
            ],
      isExplicitConversationTarget: explicitTarget,
    );

Matcher _domain(String code) =>
    isA<EntityDomainException>().having((error) => error.code, 'code', code);
