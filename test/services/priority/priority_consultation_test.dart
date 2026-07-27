import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/conversation_session_models.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/conversation_session_controller.dart';
import 'package:moms_ai/services/priority/priority_consultation_intent_detector.dart';
import 'package:moms_ai/services/priority/priority_consultation_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 27, 9);

  group('priority consultation intent', () {
    const detector = PriorityConsultationIntentDetector();

    for (final message in [
      "Qu'est-ce que je dois faire en priorité aujourd'hui ?",
      'Quelles sont mes priorités ?',
      'Sur quoi je dois me concentrer maintenant ?',
      "Qu'est-ce qui est urgent ?",
      "Qu'est-ce que je dois faire en premier ?",
      "Est-ce que j'oublie quelque chose d'important ?",
      'Donne-moi mes trois priorités du jour.',
    ]) {
      test('reconnaît : $message', () {
        expect(detector.matches(message), isTrue);
      });
    }

    for (final message in [
      'Crée une tâche prioritaire.',
      'Mets cette tâche en priorité haute.',
      'Déplace mon rendez-vous.',
      'Préviens-moi de mes priorités.',
      'Organise toute ma semaine.',
      'Quelle est la définition du mot priorité ?',
      'Willy préfère travailler le matin.',
      'Priorité.',
    ]) {
      test('refuse : $message', () {
        expect(detector.matches(message), isFalse);
      });
    }
  });

  group('local deterministic priority consultation', () {
    test('renders zero, one and at most three ordered suggestions', () async {
      final zero = await _service(
        now,
        _projection(
          now,
          [_event(now, 'later', startAfter: const Duration(days: 8))],
        ),
      ).respond();
      expect(zero.suggestionCount, 0);
      expect(zero.reply, contains('rien de critique'));

      final one = await _service(
        now,
        _projection(now, [_event(now, 'one')]),
      ).respond();
      expect(one.suggestionCount, 1);
      expect(RegExp(r'^\d+\. ', multiLine: true).allMatches(one.reply),
          hasLength(1));
      expect(one.reply, isNot(contains('score')));

      final four = await _service(
        now,
        _projection(now, [
          _event(now, 'a', startAfter: const Duration(minutes: 15)),
          _event(now, 'b', startAfter: const Duration(minutes: 30)),
          _event(now, 'c', startAfter: const Duration(minutes: 45)),
          _event(now, 'd', startAfter: const Duration(minutes: 60)),
        ]),
      ).respond();
      expect(four.suggestionCount, 3);
      expect(
        RegExp(r'^\d+\. ', multiLine: true).allMatches(four.reply),
        hasLength(3),
      );
      expect(four.reply, isNot(contains('4. ')));
    });

    test('missing duration is explained without inventing a value', () async {
      final response = await _service(
        now,
        _projection(now, [
          _task(
            now,
            'urgent',
            dueAfter: const Duration(hours: 1),
            includeDuration: false,
          ),
        ]),
      ).respond();

      expect(response.suggestionCount, 1);
      expect(response.reply, contains('durée manque'));
      expect(response.reply, isNot(matches(RegExp(r'\b\d+ minutes?\b'))));
    });

    test('subject roles never alter the deterministic visible response',
        () async {
      final replies = <String>{};
      for (final subject in [
        'child-1',
        'dependent-adult-1',
        'grandparent-1',
        'nanny-1',
        'colleague-1',
        'unrelated-person-1',
      ]) {
        replies.add(
          (await _service(
            now,
            _projection(now, [_event(now, 'same', subjectId: subject)]),
          ).respond())
              .reply,
        );
      }
      expect(replies, hasLength(1));
    });

    test('coordinator bypasses backend and returns no action or memory',
        () async {
      final backend = _Backend();
      final context = _Context();
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: context,
        priorityConsultationService:
            _service(now, _projection(now, [_event(now, 'soon')])),
        clock: () => now,
      );
      var actionCalls = 0;

      final outcome = await coordinator.send(
        input: ConversationInput(
          message: 'Quelles sont mes priorités ?',
          profile: _profile(),
        ),
        executeAction: (_) async {
          actionCalls++;
          return const ConversationActionOutcome();
        },
      );

      expect(outcome?.reply, contains('1. '));
      expect(outcome?.request, isNull);
      expect(backend.calls, 0);
      expect(context.calls, 0);
      expect(actionCalls, 0);
      expect(coordinator.state.pendingAction, isNull);
    });

    test('classic chat still uses backend for non-consultation', () async {
      final backend = _Backend();
      final context = _Context();
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: context,
        priorityConsultationService:
            _service(now, _projection(now, [_event(now, 'soon')])),
        clock: () => now,
      );

      final outcome = await coordinator.send(
        input: ConversationInput(
          message: 'Quelle est la définition du mot priorité ?',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(outcome?.reply, 'Réponse backend');
      expect(backend.calls, 1);
      expect(context.calls, 1);
    });

    test(
        'session stores one local assistant response without retry side effect',
        () async {
      final backend = _Backend();
      final context = _Context();
      final store = _Store();
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: context,
        priorityConsultationService:
            _service(now, _projection(now, [_event(now, 'soon')])),
        clock: () => now,
      );
      var id = 0;
      final controller = ConversationSessionController(
        profile: _profile(),
        coordinator: coordinator,
        executeAction: (_, __, ___) async => const ConversationActionOutcome(),
        messageStore: store,
        clock: () => now,
        idGenerator: () => 'technical-${++id}',
      );

      await controller.submitText('Quelles sont mes priorités ?');
      await controller.retryLastRequest();

      expect(
        controller.state.messages
            .where((item) => item.role == ConversationMessageRole.assistant),
        hasLength(1),
      );
      expect(store.values, hasLength(2));
      expect(backend.calls, 0);
      expect(controller.state.retryAvailable, isFalse);
      controller.dispose();
    });
  });
}

PriorityConsultationService _service(
  DateTime now,
  LifeContextProjection projection,
) =>
    PriorityConsultationService(
      loadProjection: () async => projection,
      clock: () => now,
    );

LifeContextProjection _projection(
  DateTime now,
  List<LifeContextProjectionItem> items,
) =>
    LifeContextProjection(
      projectionId: 'projection',
      sourceSnapshotId: 'snapshot',
      accountScopeId: 'account',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: now,
      state: LifeContextProjectionState.complete,
      budgetRequested: 100,
      budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.event,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: items,
          budgetLimit: 100,
          budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );

LifeContextProjectionItem _event(
  DateTime now,
  String id, {
  Duration startAfter = const Duration(minutes: 30),
  String? subjectId,
}) {
  final start = now.add(startAfter);
  return _item(
    id: id,
    domain: LifeContextDomain.event,
    facts: {
      LifeContextProjectionFactKeys.status: 'active',
      LifeContextProjectionFactKeys.start: start.toIso8601String(),
      LifeContextProjectionFactKeys.end:
          start.add(const Duration(minutes: 30)).toIso8601String(),
      LifeContextProjectionFactKeys.durationMinutes: '30',
      if (subjectId != null)
        LifeContextProjectionFactKeys.subjectEntityId: subjectId,
    },
    validFrom: start,
    validUntil: start.add(const Duration(minutes: 30)),
  );
}

LifeContextProjectionItem _task(
  DateTime now,
  String id, {
  required Duration dueAfter,
  required bool includeDuration,
}) =>
    _item(
      id: id,
      domain: LifeContextDomain.task,
      facts: {
        LifeContextProjectionFactKeys.status: 'active',
        LifeContextProjectionFactKeys.dueDate:
            now.add(dueAfter).toIso8601String(),
        LifeContextProjectionFactKeys.urgency: '0.9',
        if (includeDuration)
          LifeContextProjectionFactKeys.durationMinutes: '30',
      },
    );

LifeContextProjectionItem _item({
  required String id,
  required LifeContextDomain domain,
  required Map<String, String> facts,
  DateTime? validFrom,
  DateTime? validUntil,
}) =>
    LifeContextProjectionItem(
      id: '${domain.name}:$id',
      domain: domain,
      type: domain.name,
      facts: [
        for (final entry in facts.entries)
          LifeContextProjectionFact(
            key: entry.key,
            value: entry.value,
            sensitivity: LifeContextSensitivityLevel.publicTechnical,
          ),
      ],
      confirmation: LifeContextConfirmation.confirmed,
      freshness: LifeContextFreshness.current,
      provenance: LifeContextProjectionProvenance(
        sourceDomain: domain,
        sourceId: id,
        sourceSnapshotId: 'snapshot',
        sourceKind: domain == LifeContextDomain.event
            ? LifeContextSourceKind.eventService
            : LifeContextSourceKind.taskService,
      ),
      validFrom: validFrom,
      validUntil: validUntil,
    );

final class _Backend implements ChatBackendClient {
  int calls = 0;

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    calls++;
    return const ChatBackendResponse(
      reply: 'Réponse backend',
      actions: [],
      memories: [],
    );
  }
}

final class _Context implements ConversationContextProvider {
  int calls = 0;

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    calls++;
    return ChatBackendRequest(message: message);
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

final class _Store implements ConversationMessageStore {
  final List<String> values = [];

  @override
  Future<void> save({
    required String sessionId,
    required ConversationMessageRole role,
    required String text,
  }) async {
    values.add('${role.name}:$text');
  }
}

UserProfile _profile() => UserProfile(
      firstName: '',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );
