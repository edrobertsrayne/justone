import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/auth_service.dart';
import 'package:justone/ui/welcome_screen.dart';

class _FakeAuth implements AuthService {
  _FakeAuth({this.error});
  final Object? error;
  int signInCalls = 0;
  @override
  Future<void> signInWithGoogle() async {
    signInCalls++;
    if (error != null) throw error!;
  }
  @override
  Future<void> signOut() async {}
}

void main() {
  Widget host(AuthService auth) => ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: WelcomeScreen()),
      );

  testWidgets('renders wordmark and Google CTA; tap calls sign-in', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(host(auth));
    expect(find.text('Just One'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(auth.signInCalls, 1);
  });

  testWidgets('a sign-in failure shows the error message', (tester) async {
    await tester.pumpWidget(host(_FakeAuth(error: StateError('boom'))));
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(find.textContaining('Sign-in failed'), findsOneWidget);
  });
}
