import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/daily_reset_scope.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

ProviderContainer _containerWith(DateTime now, UserState user, List<Task> tasks) {
  final repo = InMemoryRepository(user: user, tasks: tasks);
  final c = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    nowProvider.overrideWithValue(() => now),
  ]);
  return c;
}

void main() {
  testWidgets('commits a reset when the local day has advanced', (tester) async {
    final container = _containerWith(
      DateTime(2026, 6, 24, 9),
      UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), doneToday: 2, bankedToday: true, streak: 5),
      [Task(id: 'b', title: 'B', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1), status: TaskStatus.benched)],
    );
    addTearDown(container.dispose);
    addTearDown(container.listen(userProvider, (_, __) {}).close);
    addTearDown(container.listen(tasksProvider, (_, __) {}).close);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DailyResetScope(child: SizedBox())),
    ));
    await tester.pumpAndSettle();

    final user = container.read(userProvider).requireValue;
    expect(user.doneToday, 0); // reset
    expect(user.lastActiveDate, DateTime(2026, 6, 24));
    final tasks = container.read(tasksProvider).requireValue;
    expect(tasks.single.status, TaskStatus.active); // un-benched
  });

  testWidgets('does nothing on the same local day', (tester) async {
    final container = _containerWith(
      DateTime(2026, 6, 24, 9),
      UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24), doneToday: 2),
      const [],
    );
    addTearDown(container.dispose);
    addTearDown(container.listen(userProvider, (_, __) {}).close);
    addTearDown(container.listen(tasksProvider, (_, __) {}).close);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DailyResetScope(child: SizedBox())),
    ));
    await tester.pumpAndSettle();

    expect(container.read(userProvider).requireValue.doneToday, 2); // untouched
  });
}
