import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/identity/identity_engine.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../repositories/identity/firestore_identity_read_repository.dart';
import '../../repositories/identity/firestore_identity_write_repository.dart';
import '../../repositories/identity/identity_read_repository.dart';
import 'identity_application_service.dart';
import 'identity_creation_service.dart';
import 'event_participant_identity_validation_service.dart';
import '../action_ledger_repository.dart';
import '../action_ledger_service.dart';
import '../auth_service.dart';
import '../action_autonomy_policy_service.dart';

final class IdentityProductionServices {
  final IdentityAccountScope scope;
  final IdentityApplicationService applicationService;
  final IdentityCreationService creationService;
  final EventParticipantIdentityValidationService eventParticipantValidation;

  IdentityProductionServices._({
    required this.scope,
    required this.applicationService,
    required this.creationService,
    required this.eventParticipantValidation,
  });

  factory IdentityProductionServices.create({
    required FirebaseFirestore firestore,
    required String accountId,
  }) {
    final scope = IdentityAccountScope(accountId);
    final readRepository = FirestoreIdentityReadRepository(
      firestore: firestore,
    );
    final writeRepository = FirestoreIdentityWriteRepository(
      firestore: firestore,
    );
    return IdentityProductionServices._(
      scope: scope,
      applicationService: IdentityApplicationService(
        repository: readRepository,
        engine: const IdentityEngine(),
      ),
      creationService: IdentityCreationService(
        readRepository: readRepository,
        writeRepository: writeRepository,
        idGenerator: UuidV7EntityIdGenerator(),
        ledger: ActionLedgerService(
          local: const LocalActionLedgerRepository(),
          cloud: FirestoreActionLedgerRepository(
            firestore: firestore,
            currentUid: () => AuthService.currentUserId,
          ),
          currentScope: () => AuthService.currentUserId,
        ),
        policyLoader: () async => (await ActionAutonomyPolicyService.local(
          currentAccountScopeId: () => AuthService.currentUserId,
        ))
            .load(),
      ),
      eventParticipantValidation: EventParticipantIdentityValidationService(
        repository: readRepository,
      ),
    );
  }
}
