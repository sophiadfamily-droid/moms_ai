import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/mental_load_anticipation.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/mental_load/mental_load_consultation_intent_detector.dart';
import 'package:moms_ai/services/mental_load/mental_load_consultation_service.dart';
import 'package:moms_ai/services/mental_load_anticipation_suggestion_service.dart';

void main() {
  group('mental-load consultation intent', () {
    const detector = MentalLoadConsultationIntentDetector();

    for (final message in [
      "Qu'est-ce que je dois anticiper ?",
      "Aide-moi à anticiper les prochains jours.",
      "Est-ce que j'ai quelque chose à préparer en avance ?",
      'Que dois-je penser à préparer ?',
      "Qu'est-ce que je devrais préparer cette semaine ?",
    ]) {
      test('reconnaît : $message', () {
        expect(detector.matches(message), isTrue);
      });
    }

    for (final message in [
      'Prépare mon rendez-vous de demain.',
      'Crée une tâche pour préparer ma valise.',
      'Organise ma semaine.',
      'Quelles sont mes priorités ?',
      'Rappelle-moi de préparer les valises.',
      'Je prépare le dîner.',
    ]) {
      test('refuse : $message', () {
        expect(detector.matches(message), isFalse);
      });
    }
  });

  group('mental-load consultation response', () {
    test('names proven links and limits the reply to three', () async {
      final response = await MentalLoadConsultationService(
        loadSuggestions: () async => [
          _suggestion('1', 'Préparer les passeports', 'Voyage à Rome'),
          _suggestion('2', 'Acheter un cadeau', "Anniversaire d'Emma"),
          _suggestion('3', 'Envoyer le dossier', 'Inscription scolaire'),
          _suggestion('4', 'Réserver le train', 'Week-end à Lyon'),
        ],
      ).respond();

      expect(response.suggestionCount, 3);
      expect(response.reply, contains('Voyage à Rome'));
      expect(response.reply, contains("Anniversaire d'Emma"));
      expect(response.reply, contains('Inscription scolaire'));
      expect(response.reply, isNot(contains('Week-end à Lyon')));
      expect(response.reply, isNot(contains('score')));
    });

    test('answers calmly when nothing is proven', () async {
      final response = await MentalLoadConsultationService(
        loadSuggestions: () async => [],
      ).respond();

      expect(response.suggestionCount, 0);
      expect(response.reply, contains('rien à préparer en avance'));
    });

    test('does not pretend there is nothing when loading fails', () async {
      final response = await MentalLoadConsultationService(
        loadSuggestions: () => Future.error(StateError('offline')),
      ).respond();

      expect(response.suggestionCount, 0);
      expect(response.reply, contains("n'arrive pas à vérifier"));
      expect(response.reply, isNot(contains('rien à préparer')));
    });

    test('coordinator bypasses backend and performs no action', () async {
      final backend = _Backend();
      final context = _Context();
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: context,
        mentalLoadConsultationService: MentalLoadConsultationService(
          loadSuggestions: () async => [
            _suggestion('1', 'Préparer les passeports', 'Voyage à Rome'),
          ],
        ),
      );
      var actionCalls = 0;

      final outcome = await coordinator.send(
        input: ConversationInput(
          message: "Qu'est-ce que je dois anticiper ?",
          profile: _profile(),
        ),
        executeAction: (_) async {
          actionCalls++;
          return const ConversationActionOutcome();
        },
      );

      expect(outcome?.reply, contains('Voyage à Rome'));
      expect(outcome?.request, isNull);
      expect(backend.calls, 0);
      expect(context.calls, 0);
      expect(actionCalls, 0);
      expect(coordinator.state.pendingAction, isNull);
    });
  });
}

MentalLoadAnticipationSuggestion _suggestion(
  String id,
  String preparation,
  String event,
) {
  final eventStart = DateTime.utc(2026, 9, 10, 10);
  return MentalLoadAnticipationSuggestion(
    anticipation: MentalLoadAnticipation(
      id: 'anticipation-$id',
      accountScopeId: 'account',
      reason: MentalLoadAnticipationReason.explicitPreparationBeforeEvent,
      priority: MentalLoadAnticipationPriority.important,
      preparationSourceId: 'task-$id',
      eventSourceId: 'event-$id',
      preparationDeadline: eventStart.subtract(const Duration(days: 1)),
      eventStart: eventStart,
      evidence: [
        DetectionEvidence(
          sourceType: DetectionEvidenceSource.dependencyRelationR2,
          domain: LifeContextDomain.task,
          sourceId: 'task-$id',
          revision: 1,
          freshness: LifeContextFreshness.current,
          availability: LifeContextAvailability.available,
          certainty: DetectionEvidenceLevel.confirmedStructured,
          confirmed: true,
        ),
      ],
    ),
    preparationLabel: preparation,
    eventLabel: event,
  );
}

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

UserProfile _profile() => UserProfile(
      firstName: 'Sophia',
      familyStatus: 'Famille',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );
