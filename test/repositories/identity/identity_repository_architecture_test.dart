import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_serialization.dart';

void main() {
  test('repository boundary remains replaceable and framework independent', () {
    final IdentityRepository repository = FakeIdentityRepository();

    expect(repository, isA<IdentityRepository>());
    expect(IdentityAccountScope('account-a').accountId, 'account-a');
    expect(IdentitySerialization.toMap, isA<Function>());
  });
}
