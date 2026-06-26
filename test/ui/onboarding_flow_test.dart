import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/home_router.dart';

import '../support/fake_messaging_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  Future<(InMemoryRepository, FakeMessagingService)> pumpToRationale(
    WidgetTester tester, {
    required bool grantOnRequest,
  }) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now), // onboardingComplete:false
      tasks: const [],
    );
    final fake = FakeMessagingService(status: NotifPermission.notDetermined, grantOnRequest: grantOnRequest, token: 'tok-1');
    addTearDown(fake.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        messagingServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: HomeRouter()),
    ));
    await tester.pump();
    await tester.tap(find.text('Continue')); // step 0 -> 1
    await tester.pump();
    await tester.tap(find.text('Dishes')); // pick a chore
    await tester.pump();
    await tester.tap(find.text('Start Just One')); // step 1 -> 2 (rationale)
    await tester.pump();
    return (repo, fake);
  }

  // DailyScreen animates (halo), so pumpAndSettle would hang — pump a bounded
  // number of finite frames to flush the async permission + commit + re-route.
  Future<void> settleBounded(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('"Turn on reminders" prompts, registers, lands on daily', (tester) async {
    final (repo, fake) = await pumpToRationale(tester, grantOnRequest: true);
    expect(find.text('Turn on reminders'), findsOneWidget);
    await tester.tap(find.text('Turn on reminders'));
    await settleBounded(tester);
    expect(fake.requestCount, 1);
    expect(repo.deviceUpserts.single.token, 'tok-1');
    expect(find.byType(DailyScreen), findsOneWidget);
  });

  testWidgets('"Not now" skips the prompt and still lands on daily', (tester) async {
    final (repo, fake) = await pumpToRationale(tester, grantOnRequest: true);
    await tester.tap(find.text('Not now'));
    await settleBounded(tester);
    expect(fake.requestCount, 0);
    expect(repo.deviceUpserts, isEmpty);
    expect(find.byType(DailyScreen), findsOneWidget);
  });
}
