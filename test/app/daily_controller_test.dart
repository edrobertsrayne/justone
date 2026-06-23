import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/daily_controller.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/app/toast_controller.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

UserState _user({int rerolls = 3, bool banked = false}) => UserState(
      timezone: 'UTC',
      lastActiveDate: DateTime(2026, 6, 23),
      rerolls: rerolls,
      bankedToday: banked,
      streak: 4,
    );
Task _t() => Task(id: 'x', title: 'X', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

({DailyController controller, InMemoryRepository repo, ProviderContainer container}) _harness(UserState u) {
  final repo = InMemoryRepository(user: u, tasks: [_t()]);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    nowProvider.overrideWithValue(() => DateTime(2026, 6, 23, 9)),
  ]);
  return (controller: container.read(dailyControllerProvider), repo: repo, container: container);
}

void main() {
  test('complete banks the streak with a toast on the first completion', () async {
    final h = _harness(_user(banked: false));
    addTearDown(h.container.dispose);
    await h.controller.complete(_user(banked: false), _t());
    expect(h.container.read(toastProvider), 'Day streak secured for today');
    expect((await h.repo.watchUser().first).bankedToday, isTrue);
  });

  test('complete after banking shows no streak toast', () async {
    final h = _harness(_user(banked: true));
    addTearDown(h.container.dispose);
    await h.controller.complete(_user(banked: true), _t());
    expect(h.container.read(toastProvider), isNull);
  });

  test('skip spends a reroll; the skip landing on zero toasts the last-skip warning', () async {
    final h = _harness(_user(rerolls: 1));
    addTearDown(h.container.dispose);
    await h.controller.skip(_user(rerolls: 1), _t());
    expect(h.container.read(toastProvider), 'That was your last skip for today');
    expect((await h.repo.watchUser().first).rerolls, 0);
  });

  test('skipDenied toasts and commits nothing', () async {
    final h = _harness(_user(rerolls: 0));
    addTearDown(h.container.dispose);
    h.controller.skipDenied();
    expect(h.container.read(toastProvider), "You're out of skips until tomorrow");
  });

  test('keepGoing dismisses the target and toasts the bonus message', () async {
    final h = _harness(_user());
    addTearDown(h.container.dispose);
    await h.controller.keepGoing(_user());
    expect(h.container.read(toastProvider), 'Bonus round — your streak is safe');
    expect((await h.repo.watchUser().first).targetDismissed, isTrue);
  });
}
