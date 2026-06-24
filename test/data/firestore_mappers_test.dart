import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/domain/task.dart';

void main() {
  test('round-trips a recurring task', () {
    final t = Task(
      id: 't1',
      title: 'Water plants',
      kind: TaskKind.recurring,
      intervalDays: 3,
      dueAt: DateTime(2026, 6, 24),
      createdAt: DateTime(2026, 6, 1),
      status: TaskStatus.benched,
    );
    final doc = taskToFirestore(t);
    expect(doc['kind'], 'recurring');
    expect(doc['status'], 'benched');
    expect(doc['dueAt'], isA<Timestamp>());
    expect(taskFromFirestore('t1', doc), t);
  });

  test('round-trips a one-off task with null dates', () {
    final t = Task(id: 't2', title: 'Back up', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 3));
    final doc = taskToFirestore(t);
    expect(doc['kind'], 'one-off');
    expect(doc['intervalDays'], isNull);
    expect(doc['dueAt'], isNull);
    expect(taskFromFirestore('t2', doc), t);
  });

  test('throws on a bad kind string', () {
    expect(
      () => taskFromFirestore('x', {'title': 'a', 'kind': 'weekly', 'status': 'active', 'createdAt': Timestamp.fromDate(DateTime(2026))}),
      throwsFormatException,
    );
  });

  test('throws when recurring lacks a positive intervalDays', () {
    expect(
      () => taskFromFirestore('x', {'title': 'a', 'kind': 'recurring', 'status': 'active', 'intervalDays': 0, 'createdAt': Timestamp.fromDate(DateTime(2026))}),
      throwsFormatException,
    );
  });

  test('throws when a one-off carries intervalDays', () {
    expect(
      () => taskFromFirestore('x', {'title': 'a', 'kind': 'one-off', 'status': 'active', 'intervalDays': 5, 'createdAt': Timestamp.fromDate(DateTime(2026))}),
      throwsFormatException,
    );
  });
}
