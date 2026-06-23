// test/domain/transitions_reset_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/transitions.dart';

void main() {
  Task benched() => Task(
        id: 'b', title: 'b', kind: TaskKind.recurring, intervalDays: 7,
        dueAt: DateTime(2026, 6, 20), createdAt: DateTime(2026, 1, 1),
        status: TaskStatus.benched,
      );

  final yesterday = DateTime(2026, 6, 22);
  final today = DateTime(2026, 6, 23, 9);

  UserState active({required DateTime last, bool banked = true, int streak = 5}) =>
      UserState(
        timezone: 'UTC', lastActiveDate: last, bankedToday: banked,
        streak: streak, doneToday: 2, rerolls: 1, targetDismissed: true,
      );

  test('same local date is a no-op', () {
    final state = active(last: DateTime(2026, 6, 23, 1));
    final res = dailyReset(state, [benched()], today);
    expect(res.user, state);
    expect(res.changedTasks, isEmpty);
  });

  test('rollover resets counters and un-benches tasks', () {
    final res = dailyReset(active(last: yesterday), [benched()], today);
    expect(res.user.doneToday, 0);
    expect(res.user.rerolls, 3);
    expect(res.user.bankedToday, isFalse);
    expect(res.user.targetDismissed, isFalse);
    expect(res.user.lastActiveDate, today);
    expect(res.changedTasks.single.status, TaskStatus.active);
  });

  test('consecutive banked day keeps the streak', () {
    final res = dailyReset(active(last: yesterday, banked: true), const [], today);
    expect(res.user.streak, 5);
  });

  test('left day unbanked breaks the streak (gap 1)', () {
    final res = dailyReset(active(last: yesterday, banked: false), const [], today);
    expect(res.user.streak, 0);
  });

  test('multi-day gap breaks the streak even if last day was banked', () {
    final res = dailyReset(
      active(last: DateTime(2026, 6, 20), banked: true), const [], today);
    expect(res.user.streak, 0);
  });
}
