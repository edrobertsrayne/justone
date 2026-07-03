import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  test('user/tasks providers stream the overridden repository', () async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), streak: 7),
      tasks: [Task(id: 'a', title: 'A', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1))],
    );
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    // Keep subscriptions alive to ensure providers don't dispose prematurely
    addTearDown(container.listen(userProvider, (_, _) {}).close);
    addTearDown(container.listen(tasksProvider, (_, _) {}).close);

    expect((await container.read(userProvider.future)).streak, 7);
    expect((await container.read(tasksProvider.future)).single.id, 'a');
  });

  test('nowProvider can be overridden to a fixed instant', () {
    final fixed = DateTime(2026, 6, 23, 9);
    final container = ProviderContainer(overrides: [nowProvider.overrideWithValue(() => fixed)]);
    addTearDown(container.dispose);
    expect(container.read(nowProvider)(), fixed);
  });
}
