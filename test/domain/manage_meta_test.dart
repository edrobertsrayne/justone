import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/urgency.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  Task rec(int n) => Task(id: 'r', title: 'r', kind: TaskKind.recurring, intervalDays: n, createdAt: now);

  test('recurring presets', () {
    expect(manageMeta(rec(1), now), 'Daily');
    expect(manageMeta(rec(3), now), 'Every 3 days');
    expect(manageMeta(rec(7), now), 'Weekly');
    expect(manageMeta(rec(14), now), 'Fortnightly');
    expect(manageMeta(rec(30), now), 'Monthly');
  });

  test('recurring custom decomposition', () {
    expect(manageMeta(rec(21), now), 'Every 3 weeks');
    expect(manageMeta(rec(60), now), 'Every 2 months');
    expect(manageMeta(rec(5), now), 'Every 5 days');
  });

  test('one-off defers to metaOf', () {
    final oneOff = Task(id: 'o', title: 'o', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 25), createdAt: now);
    expect(manageMeta(oneOff, now), 'due tomorrow');
  });
}
