import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/ui/settings_screen.dart';
import '../support/fake_messaging_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  Future<InMemoryRepository> pump(WidgetTester tester) async {
    final repo = InMemoryRepository(
      user: UserState(
        timezone: 'UTC', target: 3, lastActiveDate: now, onboardingComplete: true,
        remindersWeekday: const ['08:00', '18:30'], remindersWeekend: const ['10:00'],
      ),
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        messagingServiceProvider.overrideWithValue(FakeMessagingService(status: NotifPermission.granted)),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    return repo;
  }

  Future<InMemoryRepository> pumpWith(WidgetTester tester, FakeMessagingService fake) async {
    final repo = InMemoryRepository(
      user: UserState(
        timezone: 'UTC', target: 3, lastActiveDate: now, onboardingComplete: true,
        remindersWeekday: const ['08:00', '18:30'], remindersWeekend: const ['10:00'],
      ),
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        messagingServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('bumping the target writes it', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('target-inc')));
    await tester.pump();
    expect((await repo.watchUser().first).target, 4);
  });

  testWidgets('removing a weekday reminder writes the shorter array', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remove-reminder-0')));
    await tester.pump();
    expect((await repo.watchUser().first).remindersWeekday, const ['18:30']);
  });

  testWidgets('shows the re-enable card when notifications are not granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.denied, grantOnRequest: true);
    addTearDown(fake.dispose);
    final repo = await pumpWith(tester, fake);
    expect(find.byKey(const ValueKey('reenable-reminders')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reenable-reminders')));
    await tester.pumpAndSettle();
    expect(fake.requestCount, 1);
    expect(repo.deviceUpserts, isNotEmpty);
    expect(find.byKey(const ValueKey('reenable-reminders')), findsNothing); // refreshed -> granted -> gone
  });

  testWidgets('hides the re-enable card when granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.granted);
    addTearDown(fake.dispose);
    await pumpWith(tester, fake);
    expect(find.byKey(const ValueKey('reenable-reminders')), findsNothing);
  });
}
