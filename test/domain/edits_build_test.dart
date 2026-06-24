import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/edits.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);

  test('builds a recurring task with deadline + custom repeat, trimming title', () {
    final t = buildTask(
      id: 'a', title: '  Water the plants ',
      deadline: DeadlineChoice.tomorrow,
      repeat: RepeatChoice.custom, customN: 2, customUnit: CustomUnit.weeks,
      createdAt: DateTime(2026, 6, 1), now: now,
    );
    expect(t.id, 'a');
    expect(t.title, 'Water the plants');
    expect(t.kind, TaskKind.recurring);
    expect(t.intervalDays, 14);
    expect(t.dueAt, DateTime(2026, 6, 25));
    expect(t.status, TaskStatus.active);
  });

  test('one-off, no deadline preserves passed-in status/createdAt/completedAt (edit)', () {
    final t = buildTask(
      id: 'b', title: 'Back up laptop',
      deadline: DeadlineChoice.none, repeat: RepeatChoice.oneOff,
      createdAt: DateTime(2026, 5, 1), now: now,
      status: TaskStatus.benched, completedAt: DateTime(2026, 6, 20),
    );
    expect(t.kind, TaskKind.oneOff);
    expect(t.intervalDays, isNull);
    expect(t.dueAt, isNull);
    expect(t.createdAt, DateTime(2026, 5, 1));
    expect(t.status, TaskStatus.benched);
    expect(t.completedAt, DateTime(2026, 6, 20));
  });
}
