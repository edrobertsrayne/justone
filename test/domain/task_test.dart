// test/domain/task_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';

void main() {
  final base = Task(
    id: 't1',
    title: 'Water plants',
    kind: TaskKind.recurring,
    intervalDays: 3,
    dueAt: DateTime(2026, 6, 23),
    createdAt: DateTime(2026, 6, 20),
  );

  test('defaults status to active', () {
    expect(base.status, TaskStatus.active);
  });

  test('copyWith changes only named fields and keeps value equality', () {
    final benched = base.copyWith(status: TaskStatus.benched);
    expect(benched.status, TaskStatus.benched);
    expect(benched.title, 'Water plants');
    expect(benched, base.copyWith(status: TaskStatus.benched));
    expect(benched == base, isFalse);
  });

  test('recurring task requires a positive intervalDays', () {
    expect(
      () => Task(
        id: 'x', title: 'bad', kind: TaskKind.recurring,
        createdAt: DateTime(2026, 6, 20),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('one-off task must not have intervalDays', () {
    expect(
      () => Task(
        id: 'x', title: 'bad', kind: TaskKind.oneOff, intervalDays: 5,
        createdAt: DateTime(2026, 6, 20),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
