// test/domain/edits_builders_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/edits.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  UserState base() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 20));

  test('seedOnboarding flips onboardingComplete, sets target + lastActiveDate, carries tasks', () {
    final tasks = [Task(id: 'a', title: 'Dishes', kind: TaskKind.oneOff, createdAt: now)];
    final r = seedOnboarding(base(), target: 4, tasks: tasks, now: now);
    expect(r.user.onboardingComplete, isTrue);
    expect(r.user.target, 4);
    expect(r.user.lastActiveDate, DateTime(2026, 6, 24));
    expect(r.changedTasks, tasks);
  });

  test('saveTask returns the task and an unchanged user', () {
    final u = base();
    final t = Task(id: 'x', title: 'X', kind: TaskKind.oneOff, createdAt: now);
    final r = saveTask(u, t);
    expect(r.user, u);
    expect(r.changedTasks, [t]);
  });

  test('updateSettings writes only the provided fields', () {
    final r = updateSettings(base(), target: 5, weekday: const ['08:00'], weekend: const []);
    expect(r.user.target, 5);
    expect(r.user.remindersWeekday, const ['08:00']);
    expect(r.user.remindersWeekend, const []);
    expect(r.changedTasks, isEmpty);
  });
}
