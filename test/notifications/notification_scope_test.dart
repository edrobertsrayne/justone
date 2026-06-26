import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/notifications/notification_scope.dart';

import '../support/fake_messaging_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 26, 8);

  Future<InMemoryRepository> pump(WidgetTester tester, FakeMessagingService fake) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true),
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        messagingServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: NotificationScope(child: SizedBox())),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('registers the token on mount when granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.granted, token: 'tok-1');
    addTearDown(fake.dispose);
    final repo = await pump(tester, fake);
    expect(repo.deviceUpserts.single.token, 'tok-1');
  });

  testWidgets('does not register on mount when not granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.denied);
    addTearDown(fake.dispose);
    final repo = await pump(tester, fake);
    expect(repo.deviceUpserts, isEmpty);
  });

  testWidgets('upserts on a token refresh', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.granted, token: 'tok-1');
    addTearDown(fake.dispose);
    final repo = await pump(tester, fake);
    fake.emitRefresh('tok-2');
    await tester.pumpAndSettle();
    expect(repo.deviceUpserts.map((d) => d.token), contains('tok-2'));
  });
}
