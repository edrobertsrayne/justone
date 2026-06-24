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

// --- UserState <-> Firestore doc ---

String _dateToString(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _dateFromString(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

Map<String, dynamic> userToFirestore(UserState u) => {
      'timezone': u.timezone,
      'target': u.target,
      'reminders': {'weekday': u.remindersWeekday, 'weekend': u.remindersWeekend},
      'onboardingComplete': u.onboardingComplete,
      'streak': u.streak,
      'bestStreak': u.bestStreak,
      'targetMetDays': u.targetMetDays,
      'lifetimeDone': u.lifetimeDone,
      'bankedToday': u.bankedToday,
      'targetDismissed': u.targetDismissed,
      'doneToday': u.doneToday,
      'rerolls': u.rerolls,
      'lastActiveDate': _dateToString(u.lastActiveDate),
    };

UserState userFromFirestore(Map<String, dynamic> data) {
  final reminders = (data['reminders'] as Map?) ?? const {};
  List<String> rem(String k) =>
      ((reminders[k] as List?) ?? const []).map((e) => e as String).toList();
  return UserState(
    timezone: data['timezone'] as String,
    target: (data['target'] as num).toInt(),
    remindersWeekday: rem('weekday'),
    remindersWeekend: rem('weekend'),
    onboardingComplete: data['onboardingComplete'] as bool? ?? false,
    streak: (data['streak'] as num?)?.toInt() ?? 0,
    bestStreak: (data['bestStreak'] as num?)?.toInt() ?? 0,
    targetMetDays: (data['targetMetDays'] as num?)?.toInt() ?? 0,
    lifetimeDone: (data['lifetimeDone'] as num?)?.toInt() ?? 0,
    bankedToday: data['bankedToday'] as bool? ?? false,
    targetDismissed: data['targetDismissed'] as bool? ?? false,
    doneToday: (data['doneToday'] as num?)?.toInt() ?? 0,
    rerolls: (data['rerolls'] as num?)?.toInt() ?? 3,
    lastActiveDate: _dateFromString(data['lastActiveDate'] as String),
  );
}
