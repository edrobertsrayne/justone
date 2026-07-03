import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/edits.dart';
import '../domain/task.dart';
import '../domain/user_state.dart';
import 'providers.dart';

/// Builds the onboarding batch seed (D23) and commits it in one WriteBatch.
class OnboardingController {
  OnboardingController({required this._repo, required this._now});

  final Repository _repo;
  final Clock _now;

  Future<void> finish(UserState user,
      {required int target, required List<String> titles}) {
    final now = _now();
    final seen = <String>{};
    final tasks = <Task>[];
    for (final raw in titles) {
      final title = raw.trim();
      if (title.isEmpty || !seen.add(title)) continue;
      tasks.add(Task(
        id: _repo.newTaskId(),
        title: title,
        kind: TaskKind.oneOff,
        createdAt: now,
      ));
    }
    return _repo.commit(
        seedOnboarding(user, target: target, tasks: tasks, now: now));
  }
}

final onboardingControllerProvider = Provider<OnboardingController>(
  (ref) => OnboardingController(
    repo: ref.watch(repositoryProvider),
    now: ref.watch(nowProvider),
  ),
);
