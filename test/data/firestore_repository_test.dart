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
}
