import 'package:uuid/uuid.dart';

import 'entity_id_generator.dart';

final class UuidV7EntityIdGenerator implements EntityIdGenerator {
  const UuidV7EntityIdGenerator();

  static const Uuid _uuid = Uuid();

  @override
  String generate() => _uuid.v7();
}
