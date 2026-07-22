import '../../core/identity/life_entity.dart';
import 'identity_read_repository.dart';

export 'identity_read_repository.dart';

abstract interface class IdentityRepository implements IdentityReadRepository {
  Future<void> save({
    required IdentityAccountScope scope,
    required LifeEntity entity,
  });

  Future<void> saveAll({
    required IdentityAccountScope scope,
    required List<LifeEntity> entities,
  });
}
