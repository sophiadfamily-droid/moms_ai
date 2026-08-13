import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/conversation_epistemic_models.dart';
import 'package:moms_ai/models/conversation_session_models.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/human/human_model_persistence.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/human/human_model_cloud_repository.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/conversation_session_controller.dart';
import 'package:moms_ai/services/human/human_model_edit_service.dart';
import 'package:moms_ai/services/human/human_model_local_repository.dart';
import 'package:moms_ai/services/human/human_model_service.dart';
import 'package:moms_ai/services/human/recurring_responsibility_conversation_service.dart';
import 'package:moms_ai/services/routine_conversation_service.dart';
import 'package:moms_ai/services/routine_repository.dart';

import '../../fakes/fake_entity_id_generator.dart';

const _evidence = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);

void main() {
  group('responsabilité récurrente explicite', () {
    test('demande une confirmation unique puis écrit le modèle canonique',
        () async {
      final fixture = await _Fixture.create();

      final proposal = await fixture.service.process(
        'Je dépose Kassim tous les lundis de 8h20 à 8h40',
      );

      expect(
        proposal.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(proposal.message, contains('Kassim'));
      expect(proposal.message, contains('lundi'));
      expect((await fixture.model).responsibilities, isEmpty);

      final saved = await fixture.service.process('oui');

      expect(
        saved.type,
        RecurringResponsibilityConversationResultType.saved,
      );
      final responsibility = (await fixture.model).responsibilities.single;
      expect(responsibility.responsiblePersonId, 'person-main');
      expect(responsibility.subjectPersonId, 'person-kassim');
      expect(responsibility.type, HumanResponsibilityTypes.transport);
      expect(
        responsibility.recurringPlanningConsequence?.type,
        HumanPlanningConsequenceTypes.transport,
      );
      expect(
        responsibility.recurringPlanningConsequence?.weekdays,
        [DateTime.monday],
      );
      expect(
        responsibility.recurringPlanningConsequence?.startTime,
        '08:20',
      );
      expect(
        responsibility.recurringPlanningConsequence?.endTime,
        '08:40',
      );
    });

    test('ne demande que les horaires manquants et comprend les mots',
        () async {
      final fixture = await _Fixture.create();

      final clarification = await fixture.service.process(
        'Je récupère Kassim tous les mardis',
      );
      expect(
        clarification.type,
        RecurringResponsibilityConversationResultType.clarification,
      );
      expect(clarification.message, contains('quelle heure'));

      final proposal = await fixture.service.process(
        'de huit heures trente à neuf heures',
      );
      expect(
        proposal.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(proposal.message, contains('8 h 30'));
      expect(proposal.message, contains('9 h'));

      await fixture.service.process('oui');
      final recurring = (await fixture.model)
          .responsibilities
          .single
          .recurringPlanningConsequence!;
      expect(recurring.weekdays, [DateTime.tuesday]);
      expect(recurring.startTime, '08:30');
      expect(recurring.endTime, '09:00');
    });

    test('une relation ambiguë déclenche une seule question utile', () async {
      final fixture = await _Fixture.create(withSecondChild: true);

      final clarification = await fixture.service.process(
        'Je dépose mon enfant tous les lundis de 8h20 à 8h40',
      );
      expect(clarification.message, contains('Kassim ou Léa'));

      final proposal = await fixture.service.process('Léa');
      expect(
        proposal.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(proposal.message, contains('Léa'));
      await fixture.service.process('oui');

      expect(
        (await fixture.model).responsibilities.single.subjectPersonId,
        'person-lea',
      );
    });

    test('fonctionne aussi pour une personne sans rôle familial codé',
        () async {
      final fixture = await _Fixture.create();

      final proposal = await fixture.service.process(
        'J’accompagne Alex chaque jeudi de 14 heures à 15 heures',
      );
      expect(
        proposal.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      await fixture.service.process('oui');

      final responsibility = (await fixture.model).responsibilities.single;
      expect(responsibility.subjectPersonId, 'person-alex');
      expect(responsibility.type, HumanResponsibilityTypes.accompaniment);
    });

    test('une déclaration explicite reste comprise hors du rôle enfant',
        () async {
      final fixture = await _Fixture.create();

      final proposal = await fixture.service.process(
        'Je récupère Alex chaque jeudi de 14 heures à 15 heures',
      );

      expect(
        proposal.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(proposal.message, contains('Alex'));
      await fixture.service.process('oui');

      final responsibility = (await fixture.model).responsibilities.single;
      expect(responsibility.subjectPersonId, 'person-alex');
      expect(responsibility.type, HumanResponsibilityTypes.transport);
      expect(
        responsibility.recurringPlanningConsequence?.weekdays,
        [DateTime.thursday],
      );
      expect(
        responsibility.recurringPlanningConsequence?.startTime,
        '14:00',
      );
      expect(
        responsibility.recurringPlanningConsequence?.endTime,
        '15:00',
      );
    });

    test('une réponse négative annule sans écriture', () async {
      final fixture = await _Fixture.create();
      await fixture.service.process(
        'Je dépose Kassim tous les lundis de 8h20 à 8h40',
      );

      final result = await fixture.service.process('non');

      expect(
        result.type,
        RecurringResponsibilityConversationResultType.cancelled,
      );
      expect(fixture.service.hasPending, isFalse);
      expect((await fixture.model).responsibilities, isEmpty);
    });

    test('la même responsabilité ne peut pas être dupliquée', () async {
      final fixture = await _Fixture.create();
      const message = 'Je dépose Kassim tous les lundis de 8h20 à 8h40';
      await fixture.service.process(message);
      await fixture.service.process('oui');

      await fixture.service.process(message);
      final duplicate = await fixture.service.process('oui');

      expect(duplicate.message, contains('déjà pris en compte'));
      expect((await fixture.model).responsibilities, hasLength(1));
      expect(fixture.cloud.updateCount, 1);
    });

    test('hors ligne annonce clairement la sauvegarde locale', () async {
      final fixture = await _Fixture.create();
      fixture.cloud.unavailable = true;
      await fixture.service.process(
        'Je dépose Kassim tous les lundis de 8h20 à 8h40',
      );

      final result = await fixture.service.process('oui');

      expect(
        result.type,
        RecurringResponsibilityConversationResultType.saved,
      );
      expect(result.message, contains('sur ce téléphone'));
      expect((await fixture.model).responsibilities, hasLength(1));
    });
  });

  group('frontière anti-inférence', () {
    for (final message in [
      'Kassim va à l’école tous les lundis de 8h à 9h',
      'Ma sœur récupère Alex tous les mardis de 17h à 18h',
      'Peut-être que je déposerai Kassim lundi de 8h à 9h',
      'Est-ce que je dépose Kassim tous les lundis de 8h à 9h ?',
    ]) {
      test('ignore « $message »', () async {
        final fixture = await _Fixture.create();

        final result = await fixture.service.process(message);

        expect(
          result.type,
          RecurringResponsibilityConversationResultType.notResponsibility,
        );
        expect((await fixture.model).responsibilities, isEmpty);
      });
    }
  });

  group('question unique dérivée des horaires scolaires', () {
    test('les horaires déclenchent une question mais aucun blocage avant oui',
        () async {
      final fixture = await _Fixture.create();

      final proposal = await fixture.service.proposeSchoolDropoff(
        _schoolProfile(travelMinutes: '10'),
      );

      expect(
        proposal.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(proposal.message, contains('Avant de vérifier ce créneau'));
      expect(proposal.message, contains('toi qui déposes Kassim'));
      expect((await fixture.model).responsibilities, isEmpty);

      final saved = await fixture.service.process('oui');

      expect(saved.type, RecurringResponsibilityConversationResultType.saved);
      final responsibility = (await fixture.model).responsibilities.single;
      expect(responsibility.status, HumanRecordStatus.active);
      expect(
        responsibility.evidence.confirmation,
        HumanConfirmationStatus.confirmed,
      );
      expect(responsibility.subjectPersonId, 'person-kassim');
      expect(
        responsibility.recurringPlanningConsequence?.weekdays,
        [DateTime.monday, DateTime.tuesday],
      );
      expect(
        responsibility.recurringPlanningConsequence?.startTime,
        '08:20',
      );
      expect(
        responsibility.recurringPlanningConsequence?.endTime,
        '08:40',
      );
    });

    test('un oui persiste et empêche la question de revenir', () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      await fixture.service.proposeSchoolDropoff(profile);
      await fixture.service.process('oui');

      final restarted = RecurringResponsibilityConversationService(
        currentAccountScopeId: () => 'account-a',
        loadEditor: () async => fixture.editor,
      );
      final repeated = await restarted.proposeSchoolDropoff(profile);

      expect(
        repeated.type,
        RecurringResponsibilityConversationResultType.notResponsibility,
      );
      expect((await fixture.model).responsibilities, hasLength(1));
    });

    test('un non est retenu sans créer de créneau bloquant', () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      await fixture.service.proposeSchoolDropoff(profile);

      final rejected = await fixture.service.process('non');

      expect(
        rejected.type,
        RecurringResponsibilityConversationResultType.cancelled,
      );
      expect((await fixture.model).responsibilities, isEmpty);
      final kassim = (await fixture.model)
          .persons
          .singleWhere((person) => person.id == 'person-kassim');
      expect(kassim.customFields['schoolDropoffProposalRejected'], isTrue);

      final restarted = RecurringResponsibilityConversationService(
        currentAccountScopeId: () => 'account-a',
        loadEditor: () async => fixture.editor,
      );
      expect(
        (await restarted.proposeSchoolDropoff(profile)).type,
        RecurringResponsibilityConversationResultType.notResponsibility,
      );
    });

    test('sans durée de trajet l’heure d’entrée reste un repère bloquant',
        () async {
      final fixture = await _Fixture.create();
      await fixture.service.proposeSchoolDropoff(_schoolProfile());

      await fixture.service.process('oui');

      final responsibility = (await fixture.model).responsibilities.single;
      expect(responsibility.status, HumanRecordStatus.active);
      expect(responsibility.customType, 'Déposer Kassim à l’école');
      expect(
        responsibility.recurringPlanningConsequence?.weekdays,
        [DateTime.monday, DateTime.tuesday],
      );
      expect(
        responsibility.recurringPlanningConsequence?.startTime,
        '08:30',
      );
      expect(
        responsibility.recurringPlanningConsequence?.endTime,
        '08:31',
      );
    });

    test('complète une ancienne réponse oui sans reposer la question',
        () async {
      final fixture = await _Fixture.create();
      final legacy = fixture.editor.newResponsibility(
        accountScopeId: 'account-a',
        responsiblePersonId: 'person-main',
        subjectPersonId: 'person-kassim',
        type: HumanResponsibilityTypes.transport,
        scope: 'schoolDropoff:person-kassim:general',
      );
      await fixture.editor.commit(
        accountScopeId: 'account-a',
        transform: (current) => current.copyWith(
          responsibilities: [legacy],
        ),
      );
      final restarted = RecurringResponsibilityConversationService(
        currentAccountScopeId: () => 'account-a',
        loadEditor: () async => fixture.editor,
      );

      final result = await restarted.proposeSchoolDropoff(_schoolProfile());

      expect(
        result.type,
        RecurringResponsibilityConversationResultType.notResponsibility,
      );
      final migrated = (await fixture.model).responsibilities.single;
      expect(migrated.id, legacy.id);
      expect(migrated.customType, 'Déposer Kassim à l’école');
      expect(migrated.scope, 'schoolDropoff:person-kassim:1,2:08:30:0');
      expect(migrated.recurringPlanningConsequence?.startTime, '08:30');
      expect(migrated.recurringPlanningConsequence?.endTime, '08:31');
    });

    test('une journée coupée ne crée que le premier dépôt de chaque jour',
        () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      final child = profile.children.single;
      final splitProfile = profile.copyWith(
        children: [
          child.copyWith(
            schoolTimeRanges: [
              ...child.schoolTimeRanges,
              TimeRangeModel(
                startTime: '13:30',
                endTime: '16:30',
                travelMinutes: '10',
                notes: '__DAYS__:Lundi|Mardi__',
              ),
            ],
          ),
        ],
      );
      await fixture.service.proposeSchoolDropoff(splitProfile);
      await fixture.service.process('oui');

      final consequences = (await fixture.model)
          .responsibilities
          .map((item) => item.recurringPlanningConsequence)
          .whereType<HumanRecurringPlanningConsequence>()
          .toList();
      expect(consequences, hasLength(1));
      expect(consequences.single.startTime, '08:20');
      expect(consequences.single.endTime, '08:40');
    });

    test('attend une demande de planning qui touche réellement le trajet',
        () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      final now = DateTime(2026, 8, 10, 7);

      final unrelated =
          await fixture.service.proposeSchoolDropoffForPlanningRequest(
        profile,
        'Dentiste aujourd’hui à 14h',
        now: now,
      );
      final relevant =
          await fixture.service.proposeSchoolDropoffForPlanningRequest(
        profile,
        'Dentiste aujourd’hui à 8h30',
        now: now,
      );

      expect(
        unrelated.type,
        RecurringResponsibilityConversationResultType.notResponsibility,
      );
      expect(relevant.type,
          RecurringResponsibilityConversationResultType.confirmation);
      expect(relevant.message, startsWith('Avant de vérifier ce créneau'));
      expect((await fixture.model).responsibilities, isEmpty);
    });

    test('la sortie déclenche sa propre question et protège la transition',
        () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');

      final proposal =
          await fixture.service.proposeSchoolTransitionForPlanningRequest(
        profile,
        'Dentiste aujourd’hui à 11h50',
        now: DateTime(2026, 8, 10, 7),
      );

      expect(
        proposal.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(proposal.message, contains('récupères Kassim'));
      expect(proposal.message, contains('sortie de l’école'));
      expect((await fixture.model).responsibilities, isEmpty);

      await fixture.service.process('oui');

      final responsibility = (await fixture.model).responsibilities.single;
      expect(responsibility.customType, contains('Récupérer Kassim'));
      expect(responsibility.scope, startsWith('schoolPickup:person-kassim:'));
      expect(
        responsibility.recurringPlanningConsequence?.startTime,
        '11:40',
      );
      expect(
        responsibility.recurringPlanningConsequence?.endTime,
        '12:00',
      );
    });

    test('la question automatique utilise la personne du profil, jamais Kassim',
        () async {
      final fixture = await _Fixture.create(withSecondChild: true);
      final profile = _schoolProfile(
        humanPersonId: 'person-lea',
        firstName: 'Léa',
        travelMinutes: '10',
      );

      final proposal =
          await fixture.service.proposeSchoolTransitionForPlanningRequest(
        profile,
        'Dentiste aujourd’hui à 11h50',
        now: DateTime(2026, 8, 10, 7),
      );

      expect(proposal.message, contains('récupères Léa'));
      expect(proposal.message, isNot(contains('Kassim')));
      await fixture.service.process('oui');
      expect(
        (await fixture.model).responsibilities.single.subjectPersonId,
        'person-lea',
      );
    });

    test("le planning d'un adulte ne déclenche aucune déduction de transport",
        () async {
      final fixture = await _Fixture.create();
      final partnerProfile = UserProfile(
        humanPersonId: 'person-main',
        partnerHumanPersonId: 'person-alex',
        firstName: 'Sophia',
        familyStatus: 'Je vis en couple',
        workStatus: '',
        partnerName: 'Alex',
        wantsNotifications: false,
        children: const [],
        partnerWorkSchedule: 'Lundi de 8 h à 17 h',
      );

      final result =
          await fixture.service.proposeSchoolTransitionForPlanningRequest(
        partnerProfile,
        'Dentiste aujourd’hui à 8h30',
        now: DateTime(2026, 8, 10, 7),
      );

      expect(
        result.type,
        RecurringResponsibilityConversationResultType.notResponsibility,
      );
      expect(fixture.service.hasPending, isFalse);
      expect((await fixture.model).responsibilities, isEmpty);
    });

    test('une réponse sur le dépôt ne répond pas à la place de la sortie',
        () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      await fixture.service.proposeSchoolDropoff(profile);
      await fixture.service.process('oui');

      final pickup =
          await fixture.service.proposeSchoolTransitionForPlanningRequest(
        profile,
        'Dentiste aujourd’hui à 11h50',
        now: DateTime(2026, 8, 10, 7),
      );

      expect(
        pickup.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(pickup.message, contains('récupères Kassim'));
      expect((await fixture.model).responsibilities, hasLength(1));
    });

    test('une récupération déjà donnée explicitement évite toute redemande',
        () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      await fixture.service.process(
        'Je récupère Kassim tous les lundis de 11h40 à 12h',
      );
      await fixture.service.process('oui');

      final result =
          await fixture.service.proposeSchoolTransitionForPlanningRequest(
        profile,
        'Dentiste aujourd’hui à 11h50',
        now: DateTime(2026, 8, 10, 7),
      );

      expect(
        result.type,
        RecurringResponsibilityConversationResultType.notResponsibility,
      );
      expect((await fixture.model).responsibilities, hasLength(1));
    });

    test('un non sur la sortie est retenu sans masquer la question du dépôt',
        () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      await fixture.service.proposeSchoolPickup(profile);
      await fixture.service.process('non');

      final kassim = (await fixture.model)
          .persons
          .singleWhere((person) => person.id == 'person-kassim');
      expect(kassim.customFields['schoolPickupProposalRejected'], isTrue);
      expect(
        (await fixture.service.proposeSchoolPickup(profile)).type,
        RecurringResponsibilityConversationResultType.notResponsibility,
      );

      final dropoff =
          await fixture.service.proposeSchoolTransitionForPlanningRequest(
        profile,
        'Dentiste aujourd’hui à 8h30',
        now: DateTime(2026, 8, 10, 7),
      );
      expect(
        dropoff.type,
        RecurringResponsibilityConversationResultType.confirmation,
      );
      expect(dropoff.message, contains('déposes Kassim'));
    });

    test('une journée coupée utilise la dernière sortie de chaque jour',
        () async {
      final fixture = await _Fixture.create();
      final profile = _schoolProfile(travelMinutes: '10');
      final child = profile.children.single;
      final splitProfile = profile.copyWith(
        children: [
          child.copyWith(
            schoolTimeRanges: [
              ...child.schoolTimeRanges,
              TimeRangeModel(
                startTime: '13:30',
                endTime: '16:30',
                travelMinutes: '10',
                notes: '__DAYS__:Lundi|Mardi__',
              ),
            ],
          ),
        ],
      );

      await fixture.service.proposeSchoolPickup(splitProfile);
      await fixture.service.process('oui');

      final consequence = (await fixture.model)
          .responsibilities
          .single
          .recurringPlanningConsequence!;
      expect(consequence.startTime, '16:20');
      expect(consequence.endTime, '16:40');
    });

    test('le coordinateur ouvre la question puis applique la réponse',
        () async {
      final fixture = await _Fixture.create();
      final coordinator = ConversationCoordinator(
        backend: _ForbiddenBackend(),
        contextProvider: _ForbiddenContext(),
        recurringResponsibilityConversationService: fixture.service,
        clock: () => DateTime(2026, 8, 10, 7),
      );

      final proposal =
          await coordinator.beginContextualResponsibilityClarification(
        _schoolProfile(travelMinutes: '10'),
        'Dentiste aujourd’hui à 8h30',
      );
      expect(proposal?.message, contains('déposes Kassim'));
      expect((await fixture.model).responsibilities, isEmpty);

      final saved = await coordinator.send(
        input: ConversationInput(message: 'oui', profile: _schoolProfile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      expect(saved?.reply, contains('désormais'));
      expect((await fixture.model).responsibilities, hasLength(1));
    });

    test('la session reste silencieuse à l’ouverture puis reprend la demande',
        () async {
      final fixture = await _Fixture.create();
      final coordinator = ConversationCoordinator(
        backend: _ForbiddenBackend(),
        contextProvider: _ForbiddenContext(),
        recurringResponsibilityConversationService: fixture.service,
        clock: () => DateTime(2026, 8, 10, 7),
      );
      var id = 0;
      final localRequests = <String>[];
      final controller = ConversationSessionController(
        profile: _schoolProfile(travelMinutes: '10'),
        coordinator: coordinator,
        resolveLocalRequest: (message, _) async {
          localRequests.add(message);
          return const ConversationOutcome(
            reply: 'Je prépare ce rendez-vous. Il me manque juste la durée.',
            responseKind: ConversationResponseKind.clarificationRequired,
          );
        },
        messageStore: _MessageStore(),
        accountScopeId: 'account-a',
        clock: () => DateTime(2026, 8, 10, 7),
        idGenerator: () => 'message-${++id}',
      );

      expect(controller.state.phase, ConversationSessionPhase.ready);
      expect(controller.state.messages, isEmpty);
      expect(fixture.service.hasPending, isFalse);

      await controller.submitText('Dentiste aujourd’hui à 8h30');

      expect(
        controller.state.phase,
        ConversationSessionPhase.awaitingConfirmation,
      );
      expect(controller.state.hasPendingAction, isTrue);
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.last.text, contains('déposes Kassim'));
      expect(localRequests, isEmpty);

      await controller.submitText('oui');

      expect(
        controller.state.phase,
        ConversationSessionPhase.awaitingClarification,
      );
      expect(controller.state.hasPendingAction, isTrue);
      expect((await fixture.model).responsibilities, hasLength(1));
      expect(localRequests, ['Dentiste aujourd’hui à 8h30']);
      expect(
        controller.state.messages
            .where((message) => message.role == ConversationMessageRole.user)
            .map((message) => message.text),
        ['Dentiste aujourd’hui à 8h30', 'oui'],
      );
      expect(controller.state.messages.last.text, contains('durée'));
      controller.dispose();
    });
  });

  test('le coordinateur traite la responsabilité avant les routines', () async {
    final fixture = await _Fixture.create();
    final routines = _RoutineRepository();
    final coordinator = ConversationCoordinator(
      backend: _ForbiddenBackend(),
      contextProvider: _ForbiddenContext(),
      recurringResponsibilityConversationService: fixture.service,
      routineConversationService: RoutineConversationService(
        repository: routines,
        currentAccountScopeId: () => 'account-a',
      ),
    );

    final proposal = await coordinator.send(
      input: ConversationInput(
        message: 'Je dépose Kassim tous les lundis de 8h20 à 8h40',
        profile: _profile(),
      ),
      executeAction: (_) async => const ConversationActionOutcome(),
    );

    expect(proposal?.reply, contains('ton organisation'));
    expect(routines.proposalCreations, 0);
    expect((await fixture.model).responsibilities, isEmpty);

    await coordinator.send(
      input: ConversationInput(message: 'oui', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect((await fixture.model).responsibilities, hasLength(1));
    expect(routines.commits, 0);
  });
}

final class _Fixture {
  const _Fixture({
    required this.service,
    required this.editor,
    required this.cloud,
  });

  final RecurringResponsibilityConversationService service;
  final HumanModelEditService editor;
  final _Cloud cloud;

  Future<HumanModel> get model async => (await editor.load('account-a'))!.model;

  static Future<_Fixture> create({bool withSecondChild = false}) async {
    final model = _model(withSecondChild: withSecondChild);
    final local = HumanModelLocalRepository.withStore(_MemoryStore());
    final cloud = _Cloud(
      RevisionedHumanModel(
        model: model,
        modelRevision: 1,
        lastMutationId: 'initial',
        migrationVersion: 1,
        migrationStatus: HumanModelMigrationStatus.complete,
      ),
    );
    await local.saveState(
      HumanModelLocalState(
        model: model,
        knownCloudRevision: 1,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: 'initial',
        migrationStatus: HumanModelMigrationStatus.complete,
      ),
    );
    final editor = HumanModelEditService(
      humanModelService: HumanModelService(
        localRepository: local,
        cloudRepository: cloud,
      ),
      idGenerator: FakeEntityIdGenerator(
        List.generate(20, (index) => 'generated-$index'),
      ),
    );
    final service = RecurringResponsibilityConversationService(
      currentAccountScopeId: () => 'account-a',
      loadEditor: () async => editor,
    );
    return _Fixture(service: service, editor: editor, cloud: cloud);
  }
}

HumanModel _model({bool withSecondChild = false}) {
  final persons = [
    _person('person-main', 'Sophia'),
    _person('person-kassim', 'Kassim'),
    _person('person-alex', 'Alex'),
    if (withSecondChild) _person('person-lea', 'Léa'),
  ];
  return HumanModel(
    accountScopeId: 'account-a',
    primaryPersonId: 'person-main',
    persons: persons,
    relationships: [
      _relationship('relationship-kassim', 'person-kassim'),
      if (withSecondChild) _relationship('relationship-lea', 'person-lea'),
    ],
  );
}

HumanPerson _person(String id, String name) => HumanPerson(
      id: id,
      accountScopeId: 'account-a',
      displayName: name,
      evidence: _evidence,
    );

HumanRelationship _relationship(String id, String targetId) =>
    HumanRelationship(
      id: id,
      accountScopeId: 'account-a',
      sourcePersonId: 'person-main',
      targetPersonId: targetId,
      type: HumanRelationshipTypes.child,
      evidence: _evidence,
    );

final class _MemoryStore implements HumanModelKeyValueStore {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}

final class _Cloud implements HumanModelCloudRepository {
  _Cloud(this.current);

  RevisionedHumanModel? current;
  bool unavailable = false;
  int updateCount = 0;

  @override
  Future<RevisionedHumanModel?> read(String accountScopeId) async => current;

  @override
  Future<HumanModelWriteResult> createIfAbsent({
    required HumanModel model,
    required String mutationId,
    required String creationSource,
  }) async =>
      const HumanModelWriteResult.status(
        HumanModelWriteStatus.alreadyExists,
      );

  @override
  Future<HumanModelWriteResult> update({
    required HumanModel model,
    required int expectedRevision,
    required String mutationId,
  }) async {
    updateCount++;
    if (unavailable) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.unavailable,
      );
    }
    if (current?.modelRevision != expectedRevision) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.revisionConflict,
      );
    }
    current = RevisionedHumanModel(
      model: model,
      modelRevision: expectedRevision + 1,
      lastMutationId: mutationId,
      migrationVersion: 1,
      migrationStatus: HumanModelMigrationStatus.complete,
    );
    return HumanModelWriteResult.success(current!);
  }
}

final class _RoutineRepository implements RoutineRepository {
  int proposalCreations = 0;
  int commits = 0;

  @override
  Future<RoutineProposal?> createOrVerifyProposal(
    RoutineProposal proposal,
  ) async {
    proposalCreations++;
    return proposal;
  }

  @override
  Future<RoutineModel?> createOrVerify(RoutineModel routine) async => routine;

  @override
  Future<RoutineCommitResult> commitProposal(
    RoutineProposal proposal,
    DateTime committedAt,
  ) async {
    commits++;
    return const RoutineCommitResult(RoutineCommitCode.committed);
  }

  @override
  Future<RoutineProposal?> findActiveProposal(String accountScopeId) async =>
      null;

  @override
  Future<RoutineProposal?> findLatestProposal(String accountScopeId) async =>
      null;

  @override
  Future<RoutineProposal?> findProposal({
    required String accountScopeId,
    required String proposalId,
  }) async =>
      null;

  @override
  Future<List<RoutineModel>> listForAccount(String accountScopeId) async =>
      const [];

  @override
  Future<RoutineProposal?> updateProposal(RoutineProposal proposal) async =>
      proposal;
}

final class _ForbiddenBackend implements ChatBackendClient {
  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) =>
      throw StateError('The backend must not receive this local request.');
}

final class _ForbiddenContext implements ConversationContextProvider {
  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) =>
      throw StateError('No backend context should be built.');

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

final class _MessageStore implements ConversationMessageStore {
  @override
  Future<void> save({
    required String sessionId,
    required ConversationMessageRole role,
    required String text,
  }) async {}
}

UserProfile _profile() => UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );

UserProfile _schoolProfile({
  String humanPersonId = 'person-kassim',
  String firstName = 'Kassim',
  String travelMinutes = '',
}) =>
    UserProfile(
      firstName: 'Sophia',
      familyStatus: 'Nous sommes une famille avec enfants',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: [
        ChildProfile(
          humanPersonId: humanPersonId,
          firstName: firstName,
          age: '4',
          birthDate: '',
          gender: 'Garçon',
          school: 'École',
          notes: '',
          schoolTimeRanges: [
            TimeRangeModel(
              startTime: '08:30',
              endTime: '11:50',
              travelMinutes: travelMinutes,
              notes: '__DAYS__:Lundi|Mardi__',
            ),
          ],
        ),
      ],
    );
