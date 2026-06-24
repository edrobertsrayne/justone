import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/edits.dart';
import '../domain/user_state.dart';
import 'providers.dart';

/// Writes settings (daily target, reminder schedule per D17).
class SettingsController {
  SettingsController(this._repo);
  final Repository _repo;

  Future<void> setTarget(UserState user, int target) =>
      _repo.commit(updateSettings(user, target: target.clamp(1, 6)));

  Future<void> setReminders(UserState user,
      {required List<String> weekday, required List<String> weekend}) {
    List<String> norm(List<String> xs) => (List<String>.of(xs)..sort());
    return _repo.commit(updateSettings(user,
        weekday: norm(weekday), weekend: norm(weekend)));
  }
}

final settingsControllerProvider =
    Provider<SettingsController>((ref) => SettingsController(ref.watch(repositoryProvider)));
