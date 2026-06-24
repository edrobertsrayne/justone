import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/routing.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/transitions.dart';
import 'package:justone/domain/user_state.dart';

UserState _user() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23));
Task _task(String id, {TaskStatus status = TaskStatus.active}) => Task(
      id: id,
      title: 'T$id',
      kind: TaskKind.oneOff,
      createdAt: DateTime(2026, 6, 1),
      status: status,
    );

void main() {
  test('watchUser/watchTasks replay the latest value to new subscribers', () async {
    final repo = InMemoryRepository(user: _user(), tasks: [_task('1')]);
    expect((await repo.watchUser().first).timezone, 'UTC');
    expect((await repo.watchTasks().first).single.id, '1');
  });

  test('commit replaces the user, merges changedTasks by id, and re-emits', () async {
    final repo = InMemoryRepository(user: _user(), tasks: [_task('1'), _task('2')]);
    final emitted = <List<Task>>[];
    final sub = repo.watchTasks().listen(emitted.add);
    await Future<void>.delayed(Duration.zero);

    final changed = _task('1', status: TaskStatus.archived);
    await repo.commit(TransitionResult(
      user: _user().copyWith(doneToday: 1),
      changedTasks: [changed],
    ));

    expect((await repo.watchUser().first).doneToday, 1);
    final latest = await repo.watchTasks().first;
    expect(latest.length, 2); // unchanged task retained
    expect(latest.firstWhere((t) => t.id == '1').status, TaskStatus.archived);
    expect(latest.firstWhere((t) => t.id == '2').status, TaskStatus.active);
    expect(emitted.length, greaterThanOrEqualTo(1)); // live subscriber got the update
    await sub.cancel();
  });

  test('commit appends a changedTask whose id is new', () async {
    final repo = InMemoryRepository(user: _user(), tasks: [_task('1')]);
    await repo.commit(TransitionResult(user: _user(), changedTasks: [_task('9')]));
    final latest = await repo.watchTasks().first;
    expect(latest.map((t) => t.id), containsAll(['1', '9']));
  });

  test('seeded() opens on the daily screen (at least one task is due)', () async {
    final repo = InMemoryRepository.seeded();
    final user = await repo.watchUser().first;
    final tasks = await repo.watchTasks().first;
    expect(routeHome(user, tasks, DateTime.now()), AppScreen.daily);
  });

  test('dispose closes the controllers so further commits throw', () async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23)),
      tasks: const [],
    );
    repo.watchUser().listen((_) {});
    repo.watchTasks().listen((_) {});
    repo.dispose();
    expect(
      () => repo.commit(TransitionResult(
        user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
        changedTasks: const [],
      )),
      throwsStateError,
    );
  });
}
