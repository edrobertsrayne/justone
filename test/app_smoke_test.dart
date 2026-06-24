import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/bootstrap.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/main.dart';
import 'package:justone/ui/home_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-in app boots into the daily loop via Firestore', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(
      UserState(timezone: 'UTC', target: 3, lastActiveDate: DateTime(2026, 6, 24)),
    ));
    await db.collection('users/u1/tasks').doc('t1').set(taskToFirestore(
      Task(id: 't1', title: 'Reply to landlord', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 22), createdAt: DateTime(2026, 6, 1)),
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(db),
        nowProvider.overrideWithValue(() => DateTime(2026, 6, 24, 9)),
        bootstrapProvider.overrideWith((ref) async {}),
      ],
      child: const JustOneApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(HomeRouter), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget); // due task -> daily screen
  });
}
