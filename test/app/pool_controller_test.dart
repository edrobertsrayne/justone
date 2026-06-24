import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/pool_controller.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/app/toast_controller.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/edits.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  UserState user() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24), onboardingComplete: true);
  Task seed() => Task(id: 't1', title: 'Old', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

  ({PoolController c, InMemoryRepository repo, ProviderContainer container}) harness() {
    final repo = InMemoryRepository(user: user(), tasks: [seed()]);
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      nowProvider.overrideWithValue(() => now),
    ]);
    return (c: container.read(poolControllerProvider), repo: repo, container: container);
  }

  test('add creates a recurring task with the mapped fields', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.add(user(), title: 'Water plants', deadline: DeadlineChoice.today, repeat: RepeatChoice.weekly);
    final tasks = await h.repo.watchTasks().first;
    final added = tasks.firstWhere((t) => t.title == 'Water plants');
    expect(added.kind, TaskKind.recurring);
    expect(added.intervalDays, 7);
    expect(added.dueAt, DateTime(2026, 6, 24));
  });

  test('edit preserves id/createdAt/status and updates fields', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.edit(user(), seed(), title: 'New title', deadline: DeadlineChoice.tomorrow, repeat: RepeatChoice.oneOff);
    final tasks = await h.repo.watchTasks().first;
    final edited = tasks.firstWhere((t) => t.id == 't1');
    expect(edited.title, 'New title');
    expect(edited.dueAt, DateTime(2026, 6, 25));
    expect(edited.createdAt, DateTime(2026, 6, 1));
  });

  test('remove archives via status:removed and toasts', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.remove(user(), seed());
    final tasks = await h.repo.watchTasks().first;
    final removed = tasks.firstWhere((t) => t.id == 't1');
    expect(removed.status, TaskStatus.removed); // archived, not deleted from the list
    expect(h.container.read(toastProvider), 'Deleted "Old"');
  });
}
