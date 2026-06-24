import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/onboarding_controller.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  UserState fresh() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 20));

  ({OnboardingController c, InMemoryRepository repo, ProviderContainer container}) harness(UserState u) {
    final repo = InMemoryRepository(user: u, tasks: const []);
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      nowProvider.overrideWithValue(() => now),
    ]);
    return (c: container.read(onboardingControllerProvider), repo: repo, container: container);
  }

  test('finish seeds trimmed, de-duplicated tasks and flips onboardingComplete', () async {
    final h = harness(fresh());
    addTearDown(h.container.dispose);
    await h.c.finish(fresh(), target: 2, titles: ['Dishes', ' Dishes ', '', 'Laundry']);

    final user = await h.repo.watchUser().first;
    final tasks = await h.repo.watchTasks().first;
    expect(user.onboardingComplete, isTrue);
    expect(user.target, 2);
    expect(tasks.map((t) => t.title).toList(), ['Dishes', 'Laundry']);
    expect(tasks.every((t) => t.kind == TaskKind.oneOff && t.dueAt == null), isTrue);
    expect(tasks.map((t) => t.id).toSet().length, 2); // distinct ids
  });
}
