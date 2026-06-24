import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/auth_service.dart';
import 'package:justone/ui/sign_in_screen.dart';

class _StubAuthService implements AuthService {
  _StubAuthService(this._onSignIn);
  final Future<void> Function() _onSignIn;
  int calls = 0;
  @override
  Future<void> signInWithGoogle() {
    calls++;
    return _onSignIn();
  }
  @override
  Future<void> signOut() async {}
}

Future<void> _pump(WidgetTester tester, AuthService service) => tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

void main() {
  testWidgets('tapping the button calls signInWithGoogle', (tester) async {
    final service = _StubAuthService(() async {});
    await _pump(tester, service);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
  });

  testWidgets('shows an error and retry on a non-cancel failure', (tester) async {
    final service = _StubAuthService(() async => throw Exception('network'));
    await _pump(tester, service);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('failed'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget); // still retryable
  });

  testWidgets('a user-cancelled sign-in shows no error', (tester) async {
    final service = _StubAuthService(
      () async => throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await _pump(tester, service);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('failed'), findsNothing);
  });
}
