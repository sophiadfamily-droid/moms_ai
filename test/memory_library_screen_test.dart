import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/models/memory_sync.dart';
import 'package:moms_ai/screens/memory_library_screen.dart';
import 'package:moms_ai/services/memory_library_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23);

  for (final size in const [
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(820, 1180),
    Size(1024, 1366),
  ]) {
    testWidgets('bibliothèque responsive ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryLibraryScreen(initialSnapshot: _snapshot(now)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mémoire'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Ce que Zelia sait de moi'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Ce que Zelia sait de moi'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('À vérifier'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('À vérifier'), findsOneWidget);
      expect(find.text('Explorer ma mémoire'), findsNothing);
      expect(find.text('Souvenirs actifs'), findsNothing);
      expect(find.text('Archives'), findsNothing);
      expect(find.text('Archiver'), findsNothing);
      expect(find.text('Restaurer'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('texte agrandi, pending et conflit restent lisibles',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: MaterialApp(
          home: MemoryLibraryScreen(initialSnapshot: _snapshot(now)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('autre appareil'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('En attente de synchronisation'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('En attente de synchronisation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('état vide est normal et non culpabilisant', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryLibraryScreen(
          initialSnapshot: MemoryLibrarySnapshot(
            memories: const [],
            pendingIds: const {},
            conflictIds: const {},
            conflicts: const [],
            syncStatus: MemorySyncStatus.synced,
            policy: _policy(now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Zélia n’a encore rien mémorisé ici.'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Zélia n’a encore rien mémorisé ici.'), findsOneWidget);
  });

  testWidgets('commande mémoire affichée comme une information naturelle',
      (tester) async {
    final snapshot = _snapshot(now);
    final memory = RevisionedMemory(
      memoryId: 'natural',
      accountScopeId: 'test-scope',
      memoryRevision: 1,
      lifecycleStatus: MemoryLifecycleState.active,
      confirmationStatus: MemoryConfirmationStatus.confirmed,
      provenance: LifeContextSourceType.memory,
      sensitivity: LifeContextSensitivity.standard,
      category: 'preferences',
      isHealth: false,
      text: 'Souviens-toi que je préfère les rendez-vous le matin',
      normalizedText: 'souviens toi que je prefere les rendez vous le matin',
      createdAt: now,
      updatedAt: now,
      lastMutationId: 'natural',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryLibraryScreen(
          initialSnapshot: MemoryLibrarySnapshot(
            memories: [memory],
            pendingIds: const {},
            conflictIds: const {},
            conflicts: const [],
            syncStatus: MemorySyncStatus.synced,
            policy: snapshot.policy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Je préfère les rendez-vous le matin.'), findsOneWidget);
    expect(find.text('Préférence'), findsOneWidget);
    expect(find.text('Habitudes'), findsNothing);
  });
}

MemoryLibrarySnapshot _snapshot(DateTime now) => MemoryLibrarySnapshot(
      memories: [
        _memory(now, 'active', MemoryLifecycleState.active),
        _memory(now, 'proposal', MemoryLifecycleState.proposed),
        _memory(now, 'archived', MemoryLifecycleState.archived),
      ],
      pendingIds: const {'active'},
      conflictIds: const {'proposal'},
      conflicts: [
        MemorySyncConflict(
          id: 'conflict',
          targetId: 'proposal',
          mutationId: 'mutation',
          expectedRevision: 1,
          remoteRevision: 2,
          type: MemoryConflictType.revisionConflict,
          createdAt: now,
        ),
      ],
      syncStatus: MemorySyncStatus.conflict,
      policy: _policy(now),
    );

MemoryPolicy _policy(DateTime now) => MemoryPolicy(
      accountScopeId: 'test-scope',
      generalMode: MemoryGeneralMode.askEveryTime,
      healthMode: MemoryHealthMode.disabled,
      healthConsentGranted: false,
      changedAt: now,
      changeSource: MemoryPolicyChangeSource.explicitUserSetting,
    );

RevisionedMemory _memory(
  DateTime now,
  String id,
  MemoryLifecycleState state,
) =>
    RevisionedMemory(
      memoryId: id,
      accountScopeId: 'test-scope',
      memoryRevision: 1,
      lifecycleStatus: state,
      confirmationStatus: state == MemoryLifecycleState.proposed
          ? MemoryConfirmationStatus.unconfirmed
          : MemoryConfirmationStatus.confirmed,
      provenance: LifeContextSourceType.memory,
      sensitivity: LifeContextSensitivity.standard,
      category: 'preference',
      isHealth: false,
      text: 'Souvenir visible',
      normalizedText: 'souvenir visible',
      createdAt: now,
      updatedAt: now,
      lastMutationId: id,
    );
