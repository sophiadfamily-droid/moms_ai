import 'package:moms_ai/core/identity/entity_id_generator.dart';

final class FakeEntityIdGenerator implements EntityIdGenerator {
  FakeEntityIdGenerator(Iterable<String> ids) : _ids = List.of(ids);

  final List<String> _ids;
  int _callCount = 0;

  int get callCount => _callCount;

  @override
  String generate() {
    if (_callCount >= _ids.length) {
      throw StateError('No configured entity ID remains.');
    }

    final id = _ids[_callCount];
    _callCount += 1;
    return id;
  }
}
