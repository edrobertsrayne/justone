import 'task.dart';
import 'urgency.dart';

bool isDue(Task task, DateTime now) => urgencyOf(task, now) > dueThreshold;

/// The single task to serve: highest urgency among active tasks.
Task? selectTask(Iterable<Task> tasks, DateTime now) {
  final active =
      tasks.where((t) => t.status == TaskStatus.active).toList();
  if (active.isEmpty) return null;
  active.sort((a, b) {
    final byUrg = urgencyOf(b, now).compareTo(urgencyOf(a, now)); // desc
    if (byUrg != 0) return byUrg;
    final ad = a.dueAt, bd = b.dueAt;
    if (ad != null && bd != null && ad.compareTo(bd) != 0) {
      return ad.compareTo(bd); // earlier due first
    }
    if (ad == null && bd != null) return 1; // nulls last
    if (ad != null && bd == null) return -1;
    return a.createdAt.compareTo(b.createdAt); // earlier created first
  });
  return active.first;
}
