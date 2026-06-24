import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/app/settings_controller.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  UserState user() => UserState(timezone: 'UTC', target: 3, lastActiveDate: DateTime(2026, 6, 24), onboardingComplete: true);

  ({SettingsController c, InMemoryRepository repo, ProviderContainer container}) harness() {
    final repo = InMemoryRepository(user: user(), tasks: const []);
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    return (c: container.read(settingsControllerProvider), repo: repo, container: container);
  }

  test('setTarget clamps to 1..6', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.setTarget(user(), 9);
    expect((await h.repo.watchUser().first).target, 6);
  });

  test('setReminders sorts and stores both arrays', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.setReminders(user(), weekday: ['18:30', '08:00'], weekend: ['10:00']);
    final u = await h.repo.watchUser().first;
    expect(u.remindersWeekday, ['08:00', '18:30']);
    expect(u.remindersWeekend, ['10:00']);
  });
}
