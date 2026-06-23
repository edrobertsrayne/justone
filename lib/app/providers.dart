import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/in_memory_repository.dart';
import '../data/repository.dart';
import '../domain/task.dart';
import '../domain/user_state.dart';

/// A source of "now" — overridable in tests so urgency/routing are deterministic.
typedef Clock = DateTime Function();

final repositoryProvider = Provider<Repository>((ref) => InMemoryRepository.seeded());

final userProvider = StreamProvider<UserState>((ref) => ref.watch(repositoryProvider).watchUser());

final tasksProvider =
    StreamProvider<List<Task>>((ref) => ref.watch(repositoryProvider).watchTasks());

final nowProvider = Provider<Clock>((ref) => DateTime.now);
