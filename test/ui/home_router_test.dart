import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/cleared_screen.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/empty_pool_screen.dart';
import 'package:justone/ui/home_router.dart';
import 'package:justone/ui/target_hit_screen.dart';

final _now = DateTime(2026, 6, 23, 9);
UserState _user({int target = 3, int done = 0, bool dismissed = false}) => UserState(
    timezone: 'UTC', lastActiveDate: _now, target: target, doneToday: done, targetDismissed: dismissed, onboardingComplete: true);
Task _due() => Task(id: 'd', title: 'Due now', kind: TaskKind.recurring, intervalDays: 3, dueAt: _now, createdAt: DateTime(2026, 6, 1));
Task _notDue() => Task(id: 'n', title: 'Later', kind: TaskKind.oneOff, dueAt: _now.add(const Duration(days: 40)), createdAt: DateTime(2026, 6, 1));

Future<void> _pump(WidgetTester tester, UserState user, List<Task> tasks) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(InMemoryRepository(user: user, tasks: tasks)),
      nowProvider.overrideWithValue(() => _now),
    ],
    child: const MaterialApp(home: HomeRouter()),
  ));
  await tester.pump(); // let the streams emit
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a due task routes to DailyScreen', (tester) async {
    await _pump(tester, _user(), [_due()]);
    expect(find.byType(DailyScreen), findsOneWidget);
  });

  testWidgets('no tasks routes to EmptyPoolScreen', (tester) async {
    await _pump(tester, _user(), []);
    expect(find.byType(EmptyPoolScreen), findsOneWidget);
  });

  testWidgets('tasks but none due routes to ClearedScreen', (tester) async {
    await _pump(tester, _user(), [_notDue()]);
    expect(find.byType(ClearedScreen), findsOneWidget);
  });

  testWidgets('target met (not dismissed) routes to TargetHitScreen', (tester) async {
    await _pump(tester, _user(target: 1, done: 1), [_due()]);
    expect(find.byType(TargetHitScreen), findsOneWidget);
  });
}
