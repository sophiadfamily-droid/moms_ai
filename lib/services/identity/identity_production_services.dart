import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/identity/identity_engine.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../repositories/identity/firestore_identity_read_repository.dart';
import '../../repositories/identity/firestore_identity_write_repository.dart';
import '../../repositories/identity/identity_read_repository.dart';
import 'identity_application_service.dart';
import 'identity_creation_service.dart';

final class IdentityProductionServices {
  final IdentityAccountScope scope;
  final IdentityApplicationService applicationService;
  final IdentityCreationService creationService;

  IdentityProductionServices._({
    required this.scope,
    required this.applicationService,
    required this.creationService,
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
      ),
    );
  }
}
