import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/data/firestore_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/transitions.dart';
import 'package:justone/domain/user_state.dart';

UserState _user() => UserState(timezone: 'UTC', streak: 3, lifetimeDone: 10, lastActiveDate: DateTime(2026, 6, 24));
Task _task() => Task(id: 't1', title: 'A', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

void main() {
  test('watchUser maps the user doc', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(_user()));
    final repo = FirestoreRepository(db, 'u1');
    expect((await repo.watchUser().first).streak, 3);
  });

  test('watchTasks maps docs and filters archived/removed', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users/u1/tasks').doc('t1').set(taskToFirestore(_task()));
    await db.collection('users/u1/tasks').doc('t2').set(
        taskToFirestore(_task().copyWith(id: 't2', status: TaskStatus.archived)));
    final repo = FirestoreRepository(db, 'u1');
    final tasks = await repo.watchTasks().first;
    expect(tasks.map((t) => t.id), ['t1']);
  });

  test('commit writes changed task + user in one batch', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(_user()));
    await db.collection('users/u1/tasks').doc('t1').set(taskToFirestore(_task()));
    final repo = FirestoreRepository(db, 'u1');
    await repo.commit(TransitionResult(
      user: _user().copyWith(doneToday: 1),
      changedTasks: [_task().copyWith(status: TaskStatus.archived, completedAt: DateTime(2026, 6, 24))],
    ));
    expect((await db.doc('users/u1').get()).data()!['doneToday'], 1);
    expect((await db.doc('users/u1/tasks/t1').get()).data()!['status'], 'archived');
  });

  test('lifetimeDone is written as a server-relative increment, not absolute', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(_user())); // lifetimeDone: 10
    final repo = FirestoreRepository(db, 'u1');
    final sub = repo.watchUser().listen((_) {});
    await Future<void>.delayed(Duration.zero); // primes _lastUser at lifetimeDone 10
    await sub.cancel(); // freeze the base at 10 so the concurrent bump below is not tracked
    // Simulate another device bumping the server value to 100.
    await db.doc('users/u1').set({'lifetimeDone': 100}, SetOptions(merge: true));
    // Our commit computes delta from base(10) -> new(11) == +1.
    await repo.commit(TransitionResult(user: _user().copyWith(lifetimeDone: 11), changedTasks: const []));
    // increment(1) applied on top of 100 -> 101 (absolute would have written 11).
    expect((await db.doc('users/u1').get()).data()!['lifetimeDone'], 101);
  });

  test('newTaskId returns distinct non-empty ids', () {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreRepository(db, 'u1');
    expect(repo.newTaskId(), isNotEmpty);
    expect(repo.newTaskId(), isNot(repo.newTaskId()));
  });

  test('upsertDevice writes a device doc keyed by token', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreRepository(db, 'u1');
    await repo.upsertDevice(token: 'tok-1', platform: 'android', now: DateTime(2026, 6, 26, 8));
    final snap = await db.doc('users/u1/devices/tok-1').get();
    expect(snap.data()!['token'], 'tok-1');
    expect(snap.data()!['platform'], 'android');
  });
}
