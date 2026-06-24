import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

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

  test('round-trips a user with reminders and a date string', () {
    final u = UserState(
      timezone: 'Europe/London',
      target: 4,
      remindersWeekday: const ['08:00', '18:30'],
      remindersWeekend: const ['10:00'],
      onboardingComplete: true,
      streak: 5,
      bestStreak: 9,
      targetMetDays: 12,
      lifetimeDone: 40,
      bankedToday: true,
      doneToday: 2,
      rerolls: 1,
      lastActiveDate: DateTime(2026, 6, 24),
    );
    final doc = userToFirestore(u);
    expect(doc['lastActiveDate'], '2026-06-24');
    expect(doc['reminders'], {'weekday': ['08:00', '18:30'], 'weekend': ['10:00']});
    expect(userFromFirestore(doc), u);
  });

  test('userFromFirestore zero-pads and parses the date string', () {
    final u = userFromFirestore(userToFirestore(
      UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 1, 5)),
    ));
    expect(u.lastActiveDate, DateTime(2026, 1, 5));
  });
}
