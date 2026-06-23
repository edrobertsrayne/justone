// test/domain/meta_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/urgency.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);

  Task recurringDue(DateTime dueAt, {DateTime? completedAt}) => Task(
        id: 'r', title: 'r', kind: TaskKind.recurring, intervalDays: 7,
        dueAt: dueAt, completedAt: completedAt, createdAt: DateTime(2026, 1, 1),
      );

  test('completed today shows "done today"', () {
    final t = recurringDue(now.add(const Duration(days: 7)),
        completedAt: DateTime(2026, 6, 23, 9));
    expect(metaOf(t, now), 'done today');
  });

  test('overdue labels', () {
    expect(metaOf(recurringDue(DateTime(2026, 6, 21)), now), '2 days overdue');
    expect(metaOf(recurringDue(DateTime(2026, 6, 22)), now), '1 day overdue');
  });

  test('upcoming labels', () {
    expect(metaOf(recurringDue(DateTime(2026, 6, 23, 20)), now), 'due today');
    expect(metaOf(recurringDue(DateTime(2026, 6, 24)), now), 'due tomorrow');
    expect(metaOf(recurringDue(DateTime(2026, 6, 26)), now), 'due in 3 days');
  });

  test('undated one-off shows "no deadline"', () {
    final t = Task(
      id: 'o', title: 'x', kind: TaskKind.oneOff,
      createdAt: DateTime(2026, 1, 1),
    );
    expect(metaOf(t, now), 'no deadline');
  });
}
