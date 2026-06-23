// test/domain/transitions_complete_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/transitions.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);
  final user = UserState(timezone: 'UTC', target: 3, lastActiveDate: now);

  Task oneOff() => Task(
        id: 'o', title: 'o', kind: TaskKind.oneOff,
        dueAt: now, createdAt: DateTime(2026, 1, 1),
      );
  Task recurring() => Task(
        id: 'r', title: 'r', kind: TaskKind.recurring, intervalDays: 5,
        dueAt: now, createdAt: DateTime(2026, 1, 1),
      );

  test('one-off is archived and counters increment', () {
    final res = complete(user, oneOff(), now);
    expect(res.changedTasks.single.status, TaskStatus.archived);
    expect(res.changedTasks.single.completedAt, now);
    expect(res.user.doneToday, 1);
    expect(res.user.lifetimeDone, 1);
  });

  test('recurring stays active with advanced dueAt', () {
    final res = complete(user, recurring(), now);
    final t = res.changedTasks.single;
    expect(t.status, TaskStatus.active);
    expect(t.completedAt, now);
    expect(t.dueAt, now.add(const Duration(days: 5)));
  });

  test('first completion of the day banks the streak', () {
    final res = complete(user, oneOff(), now);
    expect(res.user.bankedToday, isTrue);
    expect(res.user.streak, 1);
    expect(res.user.bestStreak, 1);
  });

  test('later completion same day does not re-bank', () {
    final banked = user.copyWith(bankedToday: true, streak: 4, bestStreak: 9, doneToday: 1);
    final res = complete(banked, oneOff(), now);
    expect(res.user.streak, 4);
    expect(res.user.bestStreak, 9);
    expect(res.user.doneToday, 2);
  });

  test('exact target hit bumps targetMetDays; non-exact does not', () {
    final atTwo = user.copyWith(doneToday: 2, bankedToday: true, streak: 1);
    expect(complete(atTwo, oneOff(), now).user.targetMetDays, 1); // 2 -> 3 == target
    final atThree = user.copyWith(doneToday: 3, bankedToday: true, streak: 1);
    expect(complete(atThree, oneOff(), now).user.targetMetDays, 0); // 3 -> 4, overshoot
  });
}
