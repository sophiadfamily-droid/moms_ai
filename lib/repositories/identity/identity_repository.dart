import 'identity_read_repository.dart';
import 'identity_write_repository.dart';

export 'identity_read_repository.dart';
export 'identity_write_repository.dart';

abstract interface class IdentityRepository
    implements IdentityReadRepository, IdentityWriteRepository {}
