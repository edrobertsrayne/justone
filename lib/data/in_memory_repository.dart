import 'dart:async';

import '../domain/task.dart';
import '../domain/transitions.dart';
import '../domain/user_state.dart';
import 'repository.dart';

/// In-memory fake repository (Phase 2). Streams replay the latest value to each
/// new subscriber, then deliver live updates — adequate for a single-isolate fake.
class InMemoryRepository implements Repository {
  InMemoryRepository({required UserState user, required List<Task> tasks})
      : _user = user,
        _tasks = List<Task>.of(tasks);

  UserState _user;
  List<Task> _tasks;
  int _idSeq = 0;
  final _userCtrl = StreamController<UserState>.broadcast();
  final _tasksCtrl = StreamController<List<Task>>.broadcast();

  @override
  Stream<UserState> watchUser() async* {
    yield _user;
    yield* _userCtrl.stream;
  }

  @override
  Stream<List<Task>> watchTasks() async* {
    yield List<Task>.unmodifiable(_tasks);
    yield* _tasksCtrl.stream;
  }

  @override
  Future<void> commit(TransitionResult result) async {
    _user = result.user;
    final updated = List<Task>.of(_tasks);
    for (final changed in result.changedTasks) {
      final i = updated.indexWhere((t) => t.id == changed.id);
      if (i >= 0) {
        updated[i] = changed;
      } else {
        updated.add(changed);
      }
    }
    _tasks = updated;
    _userCtrl.add(_user);
    _tasksCtrl.add(List<Task>.unmodifiable(_tasks));
  }

  @override
  void dispose() {
    _userCtrl.close();
    _tasksCtrl.close();
  }

  @override
  String newTaskId() => 'gen-${_idSeq++}';

  /// A realistic pool for running the app by hand. At least one task is due so
  /// the app opens on `daily`. Tests construct [InMemoryRepository] directly.
  factory InMemoryRepository.seeded() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime day(int offset) => today.add(Duration(days: offset));
    final tasks = <Task>[
      Task(id: 't1', title: 'Reply to the landlord', kind: TaskKind.oneOff, dueAt: day(-2), createdAt: day(-5)),
      Task(id: 't2', title: 'Water the plants', kind: TaskKind.recurring, intervalDays: 3, dueAt: day(0), createdAt: day(-10)),
      Task(id: 't3', title: 'Take out the recycling', kind: TaskKind.recurring, intervalDays: 7, dueAt: day(0), createdAt: day(-14)),
      Task(id: 't4', title: 'Back up the laptop', kind: TaskKind.oneOff, createdAt: day(-3)),
      Task(id: 't5', title: 'Descale the kettle', kind: TaskKind.oneOff, dueAt: day(6), createdAt: day(-1)),
    ];
    final user = UserState(
      timezone: 'UTC',
      target: 3,
      rerolls: 3,
      streak: 4,
      bestStreak: 4,
      onboardingComplete: true,
      lastActiveDate: today,
    );
    return InMemoryRepository(user: user, tasks: tasks);
  }
}
