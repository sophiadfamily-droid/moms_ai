import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_snapshot.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/services/life_context/life_context_engine.dart';
import 'package:moms_ai/services/life_context/user_profile_life_context_mapper.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 7, 20, 12);

  group('LifeContextEngine', () {
    test('upgrades a legacy profile projection to schema version 3', () {
      final currentSnapshot = const UserProfileLifeContextMapper().map(
        profile: _profile(),
        generatedAt: generatedAt,
      );
      final legacySnapshot = LifeContextSnapshot(
        schemaVersion: 2,
        generatedAt: currentSnapshot.generatedAt,
        identity: currentSnapshot.identity,
        household: currentSnapshot.household,
        places: currentSnapshot.places,
        mobility: currentSnapshot.mobility,
        work: currentSnapshot.work,
        agenda: currentSnapshot.agenda,
        routines: currentSnapshot.routines,
        goals: currentSnapshot.goals,
        preferences: currentSnapshot.preferences,
        constraints: currentSnapshot.constraints,
        notes: currentSnapshot.notes,
      );
      final engine = LifeContextEngine(
        profileProjection: ({required profile, required generatedAt}) =>
            legacySnapshot,
      );

      final result = engine.buildSnapshot(
        profile: _profile(),
        generatedAt: DateTime.utc(2026, 7, 21),
        memories: const [
          {'id': 'memory-1', 'text': 'Routine historique'},
        ],
      );

      expect(result.schemaVersion, LifeContextSnapshot.currentSchemaVersion);
    });

    test('buildSnapshot delegates exactly once to the profile projection', () {
      final expected = const UserProfileLifeContextMapper().map(
        profile: _profile(),
        generatedAt: generatedAt,
      );
      UserProfile? receivedProfile;
      DateTime? receivedGeneratedAt;
      var calls = 0;
      final engine = LifeContextEngine(
        profileProjection: ({required profile, required generatedAt}) {
          calls++;
          receivedProfile = profile;
          receivedGeneratedAt = generatedAt;
          return expected;
        },
      );
      final profile = _profile();

      final result = engine.buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );

      expect(result, same(expected));
      expect(receivedProfile, same(profile));
      expect(receivedGeneratedAt, same(generatedAt));
      expect(calls, 1);
    });

    test('uses the existing mapper as its default profile projection', () {
      final profile = _profile();
      final engineResult = LifeContextEngine().buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );
      final mapperResult = const UserProfileLifeContextMapper().map(
        profile: profile,
        generatedAt: generatedAt,
      );

      expect(engineResult.toJson(), mapperResult.toJson());
    });

    test('has no changing state for identical inputs', () {
      final engine = LifeContextEngine();
      final profile = _profile();

      final first = engine.buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );
      final second = engine.buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );

      expect(first.toJson(), second.toJson());
    });

    test('preserves different injected generation timestamps', () {
      final engine = LifeContextEngine();
      final profile = _profile();
      final later = generatedAt.add(const Duration(minutes: 1));

      final first = engine.buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );
      final second = engine.buildSnapshot(
        profile: profile,
        generatedAt: later,
      );

      expect(first.generatedAt, same(generatedAt));
      expect(second.generatedAt, same(later));
      expect(first.toJson(), isNot(second.toJson()));
    });

    test('does not mutate the source profile or its lists', () {
      final workDays = <String>['Lundi', 'Mardi'];
      final children = <ChildProfile>[
        ChildProfile(
          firstName: 'Lina',
          age: '8',
          birthDate: '',
          gender: '',
          school: '',
          notes: '',
        ),
      ];
      final profile = _profile(workDays: workDays, children: children);
      final originalJson = profile.toJson();

      LifeContextEngine().buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );

      expect(profile.toJson(), originalJson);
      expect(identical(profile.workDays, workDays), isTrue);
      expect(identical(profile.children, children), isTrue);
    });

    test('composes profile and historical memory without overwriting profile',
        () {
      final snapshot = LifeContextEngine().buildSnapshot(
        profile: _profile(),
        generatedAt: generatedAt,
        memories: const [
          {
            'id': 'memory-name',
            'text': 'Je m’appelle une autre personne',
            'category': 'fact',
          },
        ],
      );

      expect(snapshot.identity.firstName?.value, 'Sophia');
      expect(snapshot.memory.memories, hasLength(1));
      expect(
        snapshot.memory.memories.single.semanticType,
        LifeMemorySemanticType.fact,
      );
      expect(snapshot.memory.memories.single.id, 'memory-name');
    });
  });
}

UserProfile _profile({
  List<String> workDays = const ['Lundi'],
  List<ChildProfile> children = const [],
}) {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: '',
    workStatus: 'Indépendante',
    partnerName: '',
    wantsNotifications: true,
    children: children,
    workDays: workDays,
    timeZone: 'Europe/Paris',
  );
}
