import 'selection.dart';
import 'task.dart';
import 'user_state.dart';

enum AppScreen {
  welcome,
  onboardTarget,
  onboardAdd,
  daily,
  cleared,
  emptyPool,
  targetHit,
  add,
  manage,
  settings,
  stats,
}

/// Home-loop routing for a signed-in user (HANDOFF §4). A not-yet-onboarded
/// user is gated to onboarding first; `welcome` (signed-out) is handled upstream
/// by the AuthGate, and the onboarding wizard owns its own `onboardAdd` step.
AppScreen routeHome(UserState state, List<Task> tasks, DateTime now) {
  if (!state.onboardingComplete) return AppScreen.onboardTarget;
  final poolEmpty = !tasks.any((t) =>
      t.status == TaskStatus.active || t.status == TaskStatus.benched);
  if (poolEmpty) return AppScreen.emptyPool;

  if (state.doneToday >= state.target && !state.targetDismissed) {
    return AppScreen.targetHit;
  }

  final selected = selectTask(tasks, now);
  if (selected == null || !isDue(selected, now)) return AppScreen.cleared;

  return AppScreen.daily;
}
