import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/task.dart';
import '../domain/user_state.dart';

// --- Task <-> Firestore doc ---

const _kindToString = {TaskKind.oneOff: 'one-off', TaskKind.recurring: 'recurring'};
const _statusToString = {
  TaskStatus.active: 'active',
  TaskStatus.benched: 'benched',
  TaskStatus.archived: 'archived',
  TaskStatus.removed: 'removed',
};

Map<String, dynamic> taskToFirestore(Task t) => {
      'title': t.title,
      'kind': _kindToString[t.kind],
      'intervalDays': t.intervalDays,
      'dueAt': t.dueAt == null ? null : Timestamp.fromDate(t.dueAt!),
      'createdAt': Timestamp.fromDate(t.createdAt),
      'completedAt': t.completedAt == null ? null : Timestamp.fromDate(t.completedAt!),
      'status': _statusToString[t.status],
    };

Task taskFromFirestore(String id, Map<String, dynamic> data) {
  final kind = switch (data['kind']) {
    'one-off' => TaskKind.oneOff,
    'recurring' => TaskKind.recurring,
    final other => throw FormatException('task $id: bad kind "$other"'),
  };
  final status = switch (data['status']) {
    'active' => TaskStatus.active,
    'benched' => TaskStatus.benched,
    'archived' => TaskStatus.archived,
    'removed' => TaskStatus.removed,
    final other => throw FormatException('task $id: bad status "$other"'),
  };
  final intervalDays = (data['intervalDays'] as num?)?.toInt();
  // Defensive invariant checks — asserts are stripped in release (Phase-1 carry-over).
  if (kind == TaskKind.recurring && (intervalDays == null || intervalDays <= 0)) {
    throw FormatException('task $id: recurring needs positive intervalDays, got $intervalDays');
  }
  if (kind == TaskKind.oneOff && intervalDays != null) {
    throw FormatException('task $id: one-off must not carry intervalDays');
  }
  DateTime? ts(Object? v) => v == null ? null : (v as Timestamp).toDate();
  return Task(
    id: id,
    title: data['title'] as String,
    kind: kind,
    intervalDays: intervalDays,
    dueAt: ts(data['dueAt']),
    createdAt: (data['createdAt'] as Timestamp).toDate(),
    completedAt: ts(data['completedAt']),
    status: status,
  );
}
