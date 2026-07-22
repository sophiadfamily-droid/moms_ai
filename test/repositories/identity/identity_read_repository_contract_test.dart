import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';

void main() {
  test('the complete repository is also a read repository', () {
    final IdentityRepository complete = FakeIdentityRepository();
    final IdentityReadRepository readOnly = complete;

    expect(readOnly, same(complete));
  });
}
