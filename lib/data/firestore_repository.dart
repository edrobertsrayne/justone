import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/task.dart';
import '../domain/transitions.dart';
import '../domain/user_state.dart';
import 'firestore_mappers.dart';
import 'repository.dart';

/// Firestore-backed [Repository] for a single signed-in user (Phase 3).
class FirestoreRepository implements Repository {
  FirestoreRepository(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  /// Last user value emitted from [watchUser]; the base for D9 increment deltas.
  UserState? _lastUser;

  DocumentReference<Map<String, dynamic>> get _userRef => _db.doc('users/$_uid');
  CollectionReference<Map<String, dynamic>> get _tasksRef => _db.collection('users/$_uid/tasks');

  @override
  Stream<UserState> watchUser() => _userRef.snapshots().where((s) => s.data() != null).map((snap) {
        final user = userFromFirestore(snap.data()!);
        _lastUser = user;
        return user;
      });

  @override
  Stream<List<Task>> watchTasks() => _tasksRef.snapshots().map((q) => q.docs
      .map((d) => taskFromFirestore(d.id, d.data()))
      .where((t) => t.status == TaskStatus.active || t.status == TaskStatus.benched)
      .toList());

  @override
  Future<void> commit(TransitionResult result) async {
    final batch = _db.batch();
    for (final task in result.changedTasks) {
      batch.set(_tasksRef.doc(task.id), taskToFirestore(task));
    }
    // All user fields are absolute last-write-wins (D9) except the two additive
    // lifetime tallies, which use server-relative increments to survive the rare
    // two-devices-offline-same-day race.
    final base = _lastUser;
    final data = userToFirestore(result.user)
      ..remove('lifetimeDone')
      ..remove('targetMetDays');
    batch.set(_userRef, data, SetOptions(merge: true));
    batch.set(
      _userRef,
      {
        'lifetimeDone': FieldValue.increment(result.user.lifetimeDone - (base?.lifetimeDone ?? 0)),
        'targetMetDays': FieldValue.increment(result.user.targetMetDays - (base?.targetMetDays ?? 0)),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  @override
  void dispose() {
    // No-op: watchUser/watchTasks return Firestore snapshot streams directly; the
    // listening StreamProviders cancel their subscriptions when repositoryProvider is
    // disposed (sign-out / account-switch). Present to satisfy the Repository seam,
    // which InMemoryRepository needs to close its StreamControllers.
  }

  @override
  String newTaskId() => _tasksRef.doc().id;
}
