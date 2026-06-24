import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/home_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  testWidgets('fresh user sees onboarding, completes it, lands on daily', (tester) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now), // onboardingComplete:false
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: HomeRouter()),
    ));
    await tester.pump();

    // Step 1: target
    expect(find.text('How much is enough?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();

    // Step 2: add chores via a suggestion chip
    expect(find.text("What's on your plate?"), findsOneWidget);
    await tester.tap(find.text('Dishes'));
    await tester.pump();
    await tester.tap(find.text('Start Just One'));
    await tester.pump(); // commit
    await tester.pump(); // stream re-emit -> re-route

    expect(find.byType(DailyScreen), findsOneWidget);
  });
}
