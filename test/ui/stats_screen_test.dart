import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/stats_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 25, 9);

  UserState user() => UserState(
        timezone: 'UTC',
        lastActiveDate: now,
        onboardingComplete: true,
        streak: 5,
        bestStreak: 12,
        targetMetDays: 9,
        lifetimeDone: 128,
      );

  // 3 active/benched (counted) + 1 archived + 1 removed (excluded) => poolCount 3.
  List<Task> tasks() => [
        Task(id: 'a', title: 'A', kind: TaskKind.recurring, intervalDays: 7, dueAt: now, createdAt: now),
        Task(id: 'b', title: 'B', kind: TaskKind.recurring, intervalDays: 7, dueAt: now, createdAt: now, status: TaskStatus.benched),
        Task(id: 'c', title: 'C', kind: TaskKind.oneOff, dueAt: now, createdAt: now),
        Task(id: 'd', title: 'D', kind: TaskKind.oneOff, dueAt: now, createdAt: now, status: TaskStatus.archived),
        Task(id: 'e', title: 'E', kind: TaskKind.oneOff, dueAt: now, createdAt: now, status: TaskStatus.removed),
      ];

  Future<void> pump(WidgetTester tester, {required InMemoryRepository repo}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: StatsScreen()),
    ));
    await tester.pump();
  }

  testWidgets('renders the streak hero and the four stat values', (tester) async {
    await pump(tester, repo: InMemoryRepository(user: user(), tasks: tasks()));
    expect(find.text('Current streak'.toUpperCase()), findsOneWidget); // overline
    expect(find.text('5'), findsOneWidget); // streak numeral
    expect(find.text('days showing up'), findsOneWidget);
    expect(find.text('Days at target'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Longest streak'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Chores completed'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('In your pool'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // poolCount excludes archived + removed
  });

  testWidgets('back button pops the route', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryRepository(user: user(), tasks: tasks())),
        nowProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const StatsScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Your stats'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stats-back')));
    await tester.pumpAndSettle();
    expect(find.text('Your stats'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('renders a paper fill while providers are loading', (tester) async {
    // No override -> repositoryProvider builds but hits null auth uid, so
    // userProvider/tasksProvider resolve to AsyncError. Either way .value is null;
    // guard renders paper fill, no exception.
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: StatsScreen()),
    ));
    await tester.pump();
    expect(find.text('Your stats'), findsNothing); // header not built yet
    expect(tester.takeException(), isNull);
  });
}
