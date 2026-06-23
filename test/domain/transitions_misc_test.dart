// test/domain/transitions_misc_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/transitions.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);
  final user = UserState(timezone: 'UTC', lastActiveDate: now);
  final task = Task(
    id: 't', title: 't', kind: TaskKind.recurring, intervalDays: 7,
    dueAt: now, createdAt: DateTime(2026, 1, 1),
  );

  test('skip benches the task and decrements rerolls', () {
    final res = skip(user.copyWith(rerolls: 3), task);
    expect(res.changedTasks.single.status, TaskStatus.benched);
    expect(res.user.rerolls, 2);
  });

  test('remove marks the task removed and leaves the user unchanged', () {
    final res = remove(user, task);
    expect(res.changedTasks.single.status, TaskStatus.removed);
    expect(res.user, user);
  });

  test('keepGoing sets targetDismissed with no task change', () {
    final res = keepGoing(user);
    expect(res.user.targetDismissed, isTrue);
    expect(res.changedTasks, isEmpty);
  });
}
