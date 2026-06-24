import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../data/firestore_repository.dart';
import '../data/repository.dart';
import '../domain/task.dart';
import '../domain/user_state.dart';

/// A source of "now" — overridable in tests so urgency/routing are deterministic.
typedef Clock = DateTime Function();

/// Firestore-backed repository scoped to the signed-in uid. Rebuilt (and the old
/// one disposed) when auth changes, so sign-out/account-switch swaps the data layer.
final repositoryProvider = Provider<Repository>((ref) {
  final uid = ref.watch(authProvider).value?.uid;
  final repo = FirestoreRepository(ref.watch(firestoreProvider), uid!);
  ref.onDispose(repo.dispose);
  return repo;
});

final userProvider = StreamProvider<UserState>((ref) => ref.watch(repositoryProvider).watchUser());

final tasksProvider =
    StreamProvider<List<Task>>((ref) => ref.watch(repositoryProvider).watchTasks());

final nowProvider = Provider<Clock>((ref) => DateTime.now);
