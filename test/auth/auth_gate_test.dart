import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/auth/auth_gate.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/bootstrap.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/ui/home_router.dart';
import 'package:justone/ui/settings_screen.dart';
import 'package:justone/ui/welcome_screen.dart';

import '../support/fake_messaging_service.dart';

void main() {
  testWidgets('shows the welcome screen when signed out', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [firebaseAuthProvider.overrideWithValue(MockFirebaseAuth())],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
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
        // NotificationScope now lives in the signed-in subtree; prevent the real
        // FirebaseMessagingService from being constructed (Firebase not initialised in tests).
        messagingServiceProvider.overrideWithValue(FakeMessagingService()),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeRouter), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('signing out dismisses routes pushed above the gate and returns to WelcomeScreen', (tester) async {
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
        bootstrapProvider.overrideWith((ref) async {}),
        messagingServiceProvider.overrideWithValue(FakeMessagingService()),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeRouter), findsOneWidget);

    // A screen pushed on top of the gate, as ManageScreen/SettingsScreen are.
    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('PUSHED'))),
        );
    await tester.pumpAndSettle();
    expect(find.text('PUSHED'), findsOneWidget);

    // Sign out exactly as the settings button does, via the Firebase layer.
    await auth.signOut();
    await tester.pumpAndSettle();

    expect(find.text('PUSHED'), findsNothing, reason: 'pushed route should be popped on sign-out');
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  // Faithful to production: the REAL repositoryProvider (which does `uid!`) runs
  // on a fake Firestore, so the sign-out flow exercises the null-uid rebuild.
  testWidgets('sign-out returns to WelcomeScreen with the real (uid!) repositoryProvider', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(
          UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
        ));
    await db.collection('users/u1/tasks').doc('a').set(taskToFirestore(
          Task(id: 'a', title: 'A', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 20), createdAt: DateTime(2026, 6, 1)),
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(db),
        nowProvider.overrideWithValue(() => DateTime(2026, 6, 24, 9)),
        bootstrapProvider.overrideWith((ref) async {}),
        messagingServiceProvider.overrideWithValue(FakeMessagingService()),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeRouter), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('PUSHED'))),
        );
    await tester.pumpAndSettle();
    expect(find.text('PUSHED'), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();

    expect(find.text('PUSHED'), findsNothing, reason: 'pushed route should be popped on sign-out');
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  // Most faithful reproduction: the ACTUAL SettingsScreen (which watches
  // userProvider) is pushed above the gate, then we sign out.
  testWidgets('sign-out from the real SettingsScreen returns to WelcomeScreen', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(
          UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
        ));
    await db.collection('users/u1/tasks').doc('a').set(taskToFirestore(
          Task(id: 'a', title: 'A', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 20), createdAt: DateTime(2026, 6, 1)),
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(db),
        nowProvider.overrideWithValue(() => DateTime(2026, 6, 24, 9)),
        bootstrapProvider.overrideWith((ref) async {}),
        messagingServiceProvider.overrideWithValue(FakeMessagingService()),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

    expect(find.byType(SettingsScreen), findsNothing, reason: 'settings route should be popped on sign-out');
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  // Regression: signing out then signing back in *within the same session* (now
  // possible since sign-out returns to WelcomeScreen instead of stranding the
  // user). The auth-scoped provider chain must not be flushed synchronously
  // during AuthGate's build with stale listeners, or Riverpod throws
  // "setState() called during build".
  testWidgets('re-login after sign-out does not throw setState-during-build', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(
          UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
        ));
    await db.collection('users/u1/tasks').doc('a').set(taskToFirestore(
          Task(id: 'a', title: 'A', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 20), createdAt: DateTime(2026, 6, 1)),
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(db),
        nowProvider.overrideWithValue(() => DateTime(2026, 6, 24, 9)),
        bootstrapProvider.overrideWith((ref) async {}),
        messagingServiceProvider.overrideWithValue(FakeMessagingService()),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeRouter), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    // Sign back in as the same user without restarting the app.
    await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: 'i', accessToken: 'a'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no setState()-during-build on re-login');
    expect(find.byType(HomeRouter), findsOneWidget);
  });
}
