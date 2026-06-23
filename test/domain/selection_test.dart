import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/selection.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);

  Task r(String id, {required int overdueDays, TaskStatus status = TaskStatus.active}) =>
      Task(
        id: id, title: id, kind: TaskKind.recurring, intervalDays: 7,
        dueAt: now.subtract(Duration(days: overdueDays)),
        createdAt: DateTime(2026, 1, 1), status: status,
      );

  test('returns null when no active tasks', () {
    expect(selectTask([r('a', overdueDays: 3, status: TaskStatus.benched)], now), isNull);
  });

  test('picks the highest-urgency active task', () {
    final picked = selectTask([
      r('low', overdueDays: -2),
      r('high', overdueDays: 5),
      r('mid', overdueDays: 1),
    ], now);
    expect(picked!.id, 'high');
  });

  test('ignores benched/archived/removed', () {
    final picked = selectTask([
      r('benched', overdueDays: 10, status: TaskStatus.benched),
      r('active', overdueDays: 2),
    ], now);
    expect(picked!.id, 'active');
  });

  test('isDue tracks the 0.04 threshold', () {
    expect(isDue(r('due', overdueDays: 0), now), isTrue);
    expect(isDue(r('faroff', overdueDays: -21), now), isFalse); // r=-3 -> ~0.04
  });
}
