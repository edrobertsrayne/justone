import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/manage_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  Future<InMemoryRepository> pump(WidgetTester tester) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true),
      tasks: [Task(id: 't1', title: 'Water plants', kind: TaskKind.recurring, intervalDays: 7, dueAt: now, createdAt: now)],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: ManageScreen()),
    ));
    await tester.pump();
    return repo;
  }

  testWidgets('lists tasks with cadence meta', (tester) async {
    await pump(tester);
    expect(find.text('Water plants'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
  });

  testWidgets('delete asks to confirm then removes', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('delete-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this chore?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsNothing);
    final tasks = await repo.watchTasks().first;
    expect(tasks.firstWhere((t) => t.id == 't1').status, TaskStatus.removed);
  });
}
