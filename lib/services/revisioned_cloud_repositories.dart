import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import 'cloud_profile_service.dart';
import 'cloud_shopping_service.dart';
import 'cloud_task_service.dart';
import 'revisioned_domain_sync_service.dart';

final class FirestoreRevisionedTaskRepository
    implements RevisionedTaskCloudRepository {
  const FirestoreRevisionedTaskRepository();

  @override
  Future<List<RevisionedTask>> load({int limit = 100}) =>
      CloudTaskService.getRevisioned(limit: limit);

  @override
  Future<RevisionedCloudWriteResult<RevisionedTask>> create(
    TaskMutation mutation,
    String accountScopeId,
  ) =>
      CloudTaskService.createRevisioned(
        accountScopeId: accountScopeId,
        task: mutation.task,
        mutationId: mutation.mutationId,
      );

  @override
  Future<RevisionedCloudWriteResult<RevisionedTask>> update(
    TaskMutation mutation,
    String accountScopeId,
  ) =>
      CloudTaskService.updateRevisioned(
        accountScopeId: accountScopeId,
        task: mutation.task,
        expectedRevision: mutation.expectedRevision,
        mutationId: mutation.mutationId,
        tombstone: mutation.type == TaskMutationType.deleteTask ||
            mutation.type == TaskMutationType.archiveTask,
      );
}

final class FirestoreRevisionedShoppingRepository
    implements RevisionedShoppingCloudRepository {
  const FirestoreRevisionedShoppingRepository();

  @override
  Future<List<RevisionedShoppingItem>> load({int limit = 100}) =>
      CloudShoppingService.getRevisioned(limit: limit);

  @override
  Future<RevisionedCloudWriteResult<RevisionedShoppingItem>> create(
    ShoppingMutation mutation,
    String accountScopeId,
  ) =>
      CloudShoppingService.createRevisioned(
        accountScopeId: accountScopeId,
        item: mutation.item,
        mutationId: mutation.mutationId,
      );

  @override
  Future<RevisionedCloudWriteResult<RevisionedShoppingItem>> update(
    ShoppingMutation mutation,
    String accountScopeId,
  ) =>
      CloudShoppingService.updateRevisioned(
        accountScopeId: accountScopeId,
        item: mutation.item,
        expectedRevision: mutation.expectedRevision,
        mutationId: mutation.mutationId,
        tombstone: mutation.type == ShoppingMutationType.removeItem ||
            mutation.type == ShoppingMutationType.clearList,
        clearGeneration: mutation.clearGeneration,
      );
}

final class FirestoreRevisionedProfileRepository
    implements RevisionedProfileCloudRepository {
  const FirestoreRevisionedProfileRepository();

  @override
  Future<RevisionedProfileState?> load() => CloudProfileService.getRevisioned();

  @override
  Future<RevisionedCloudWriteResult<RevisionedProfileState>> create(
    ProfileMutation mutation,
    String accountScopeId,
  ) =>
      CloudProfileService.createRevisioned(
        accountScopeId: accountScopeId,
        profile: mutation.profile,
        mutationId: mutation.mutationId,
      );

  @override
  Future<RevisionedCloudWriteResult<RevisionedProfileState>> update(
    ProfileMutation mutation,
    String accountScopeId,
  ) =>
      CloudProfileService.updateRevisioned(
        accountScopeId: accountScopeId,
        profile: mutation.profile,
        changedFields: mutation.changedFields,
        expectedRevision: mutation.expectedRevision,
        mutationId: mutation.mutationId,
      );
}
