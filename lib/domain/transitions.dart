import 'dart:math' as math;

import 'task.dart';
import 'user_state.dart';

/// The intended writes from a pure transition. Phase 3 commits [user] and
/// [changedTasks] together in one Firestore WriteBatch (D11).
class TransitionResult {
  final UserState user;
  final List<Task> changedTasks;
  const TransitionResult({required this.user, required this.changedTasks});
}

/// Complete a task (swipe-right Done). HANDOFF §4.
TransitionResult complete(UserState state, Task task, DateTime now) {
  final Task updated;
  if (task.kind == TaskKind.oneOff) {
    updated = task.copyWith(status: TaskStatus.archived, completedAt: now);
  } else {
    updated = task.copyWith(
      completedAt: now,
      dueAt: now.add(Duration(days: task.intervalDays!)),
    );
  }

  var user = state.copyWith(
    doneToday: state.doneToday + 1,
    lifetimeDone: state.lifetimeDone + 1,
  );

  if (!state.bankedToday) {
    final newStreak = state.streak + 1;
    user = user.copyWith(
      bankedToday: true,
      streak: newStreak,
      bestStreak: math.max(state.bestStreak, newStreak),
    );
  }

  if (user.doneToday == user.target) {
    user = user.copyWith(targetMetDays: user.targetMetDays + 1);
  }

  return TransitionResult(user: user, changedTasks: [updated]);
}
