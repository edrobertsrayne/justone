import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/task.dart';
import '../domain/transitions.dart' as domain;
import '../domain/user_state.dart';
import 'providers.dart';
import 'toast_controller.dart';

/// The action layer for the daily loop: reads a snapshot, calls the Phase-1
/// transition, fires any toast, and commits the result.
class DailyController {
  DailyController({required this._repo, required this._toast, required this._now});

  final Repository _repo;
  final ToastController _toast;
  final Clock _now;

  Future<void> complete(UserState user, Task task) {
    final banks = !user.bankedToday;
    final result = domain.complete(user, task, _now());
    if (banks) _toast.show('Day streak secured for today');
    return _repo.commit(result);
  }

  Future<void> skip(UserState user, Task task) {
    if (user.rerolls <= 0) {
      skipDenied();
      return Future<void>.value();
    }
    final result = domain.skip(user, task);
    if (result.user.rerolls == 0) _toast.show('That was your last skip for today');
    return _repo.commit(result);
  }

  void skipDenied() => _toast.show("You're out of skips until tomorrow");

  Future<void> remove(UserState user, Task task) => _repo.commit(domain.remove(user, task));

  Future<void> keepGoing(UserState user) {
    _toast.show('Bonus round — your streak is safe');
    return _repo.commit(domain.keepGoing(user));
  }
}

final dailyControllerProvider = Provider<DailyController>((ref) => DailyController(
      repo: ref.watch(repositoryProvider),
      toast: ref.watch(toastProvider.notifier),
      now: ref.watch(nowProvider),
    ));
