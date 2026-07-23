import '../../models/human/human_model.dart';
import '../../models/human/human_model_persistence.dart';

abstract interface class HumanModelCloudRepository {
  Future<RevisionedHumanModel?> read(String accountScopeId);

  Future<HumanModelWriteResult> createIfAbsent({
    required HumanModel model,
    required String mutationId,
    required String creationSource,
  });

  Future<HumanModelWriteResult> update({
    required HumanModel model,
    required int expectedRevision,
    required String mutationId,
  });
}
