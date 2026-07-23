import 'package:shared_preferences/shared_preferences.dart';

import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../models/human/human_model.dart';
import '../../models/user_profile.dart';
import 'human_model_local_repository.dart';
import 'legacy_user_profile_human_adapter.dart';

final class HumanProfileProjection {
  const HumanProfileProjection({
    required this.schemaVersion,
    required this.personCount,
    required this.currentHouseholdCount,
    required this.currentResponsibilityCount,
  });

  final int schemaVersion;
  final int personCount;
  final int currentHouseholdCount;
  final int currentResponsibilityCount;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'personCount': personCount,
        'currentHouseholdCount': currentHouseholdCount,
        'currentResponsibilityCount': currentResponsibilityCount,
      };
}

final class HumanModelService {
  HumanModelService({
    required HumanModelLocalRepository repository,
    LegacyUserProfileHumanAdapter legacyAdapter =
        const LegacyUserProfileHumanAdapter(),
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  })  : _repository = repository,
        _legacyAdapter = legacyAdapter,
        _idGenerator = idGenerator;

  final HumanModelLocalRepository _repository;
  final LegacyUserProfileHumanAdapter _legacyAdapter;
  final EntityIdGenerator _idGenerator;

  static Future<HumanModelService> createLocal() async {
    final preferences = await SharedPreferences.getInstance();
    return HumanModelService(
      repository: HumanModelLocalRepository(preferences),
    );
  }

  Future<HumanModel?> load(String accountScopeId) =>
      _repository.load(accountScopeId);

  Future<HumanModel> loadOrMigrate({
    required String accountScopeId,
    required UserProfile legacyProfile,
    Map<String, Object?>? legacyProfileJson,
  }) async {
    final existing = await _repository.load(accountScopeId);
    if (existing != null) return existing;

    final migrated = _legacyAdapter.migrate(
      profile: legacyProfile,
      legacyProfile: legacyProfileJson ?? legacyProfile.toJson(),
      accountScopeId: accountScopeId,
      idGenerator: _idGenerator,
    );
    migrated.validate();
    await _repository.save(migrated);

    final persisted = await _repository.load(accountScopeId);
    if (persisted == null) {
      throw const HumanModelException('human_model_storage_failure');
    }
    return persisted;
  }

  Future<void> save(HumanModel model) => _repository.save(model);

  HumanPerson? person(HumanModel model, String personId) =>
      model.personById(personId);

  List<HumanRelationship> activeRelationships(
    HumanModel model,
    DateTime at,
  ) =>
      model.activeRelationships(at);

  List<HumanHousehold> activeHouseholds(HumanModel model, DateTime at) =>
      model.activeHouseholds(at);

  List<HumanResponsibility> activeResponsibilities(
    HumanModel model,
    DateTime at,
  ) =>
      model.activeResponsibilities(at);

  HumanProfileProjection project(HumanModel model, DateTime at) {
    return HumanProfileProjection(
      schemaVersion: model.schemaVersion,
      personCount: model.persons.length,
      currentHouseholdCount: model.activeHouseholds(at).length,
      currentResponsibilityCount: model.activeResponsibilities(at).length,
    );
  }
}
