import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/auth/auth_gate.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/bootstrap.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/home_router.dart';
import 'package:justone/ui/sign_in_screen.dart';

void main() {
  testWidgets('shows the sign-in screen when signed out', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [firebaseAuthProvider.overrideWithValue(MockFirebaseAuth())],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('shows the home router when signed in and bootstrapped', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
      tasks: [Task(id: 'a', title: 'A', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 20), createdAt: DateTime(2026, 6, 1))],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => DateTime(2026, 6, 24, 9)),
        bootstrapProvider.overrideWith((ref) async {}), // skip the flutter_timezone plugin call
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeRouter), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });
}
