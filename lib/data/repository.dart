import '../domain/task.dart';
import '../domain/transitions.dart';
import '../domain/user_state.dart';

/// The data seam. Phase 2 backs this with [InMemoryRepository]; Phase 3 swaps in
/// a Firestore-backed implementation behind the same three methods.
abstract class Repository {
  Stream<UserState> watchUser();
  Stream<List<Task>> watchTasks();

  /// Apply a pure [TransitionResult]: replace the user, merge changed tasks by
  /// id, then re-emit both streams.
  Future<void> commit(TransitionResult result);

  /// Release resources (Firestore listeners / stream controllers). Called when
  /// the repository is replaced (e.g. sign-out) or the app shuts down.
  void dispose();

  /// Allocate a new, unique task id. Firestore uses a client-side auto-id;
  /// the in-memory fake uses a counter.
  String newTaskId();

  /// Upsert this device's FCM token into `users/{uid}/devices/{token}` (D4).
  /// Doc id is the token itself; dead tokens are pruned server-side.
  Future<void> upsertDevice({
    required String token,
    required String platform,
    required DateTime now,
  });
}
