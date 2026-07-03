import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/auth/auth_providers.dart';

void main() {
  test('authProvider emits the signed-in user from FirebaseAuth', () async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final container = ProviderContainer(overrides: [firebaseAuthProvider.overrideWithValue(auth)]);
    addTearDown(container.dispose);
    addTearDown(container.listen(authProvider, (_, _) {}).close);
    expect((await container.read(authProvider.future))?.uid, 'u1');
  });

  test('authProvider emits null when signed out', () async {
    final auth = MockFirebaseAuth(); // signed out
    final container = ProviderContainer(overrides: [firebaseAuthProvider.overrideWithValue(auth)]);
    addTearDown(container.dispose);
    addTearDown(container.listen(authProvider, (_, _) {}).close);
    expect(await container.read(authProvider.future), isNull);
  });
}
