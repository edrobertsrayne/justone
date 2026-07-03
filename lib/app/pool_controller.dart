import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/edits.dart';
import '../domain/task.dart';
import '../domain/transitions.dart' as domain;
import '../domain/user_state.dart';
import 'providers.dart';
import 'toast_controller.dart';

/// Add/edit/remove pool tasks. Each builds a task (or reuses domain.remove),
/// then commits through the Repository seam.
class PoolController {
  PoolController({required this._repo, required this._toast, required this._now});

  final Repository _repo;
  final ToastController _toast;
  final Clock _now;

  Future<void> add(
    UserState user, {
    required String title,
    required DeadlineChoice deadline,
    DateTime? pickedDate,
    required RepeatChoice repeat,
    int customN = 2,
    CustomUnit customUnit = CustomUnit.weeks,
  }) {
    final now = _now();
    final task = buildTask(
      id: _repo.newTaskId(),
      title: title,
      deadline: deadline,
      pickedDate: pickedDate,
      repeat: repeat,
      customN: customN,
      customUnit: customUnit,
      createdAt: now,
      now: now,
    );
    return _repo.commit(saveTask(user, task));
  }

  Future<void> edit(
    UserState user,
    Task original, {
    required String title,
    required DeadlineChoice deadline,
    DateTime? pickedDate,
    required RepeatChoice repeat,
    int customN = 2,
    CustomUnit customUnit = CustomUnit.weeks,
  }) {
    final task = buildTask(
      id: original.id,
      title: title,
      deadline: deadline,
      pickedDate: pickedDate,
      repeat: repeat,
      customN: customN,
      customUnit: customUnit,
      createdAt: original.createdAt,
      now: _now(),
      status: original.status,
      completedAt: original.completedAt,
    );
    return _repo.commit(saveTask(user, task));
  }

  Future<void> remove(UserState user, Task task) {
    _toast.show('Deleted "${task.title}"');
    return _repo.commit(domain.remove(user, task));
  }
}

final poolControllerProvider = Provider<PoolController>(
  (ref) => PoolController(
    repo: ref.watch(repositoryProvider),
    toast: ref.watch(toastProvider.notifier),
    now: ref.watch(nowProvider),
  ),
);
