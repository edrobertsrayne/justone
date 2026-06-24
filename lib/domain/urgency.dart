import 'dart:math' as math;

import 'task.dart';

// Tunable urgency constants (single source — see plan Global Constraints).
const double _floor = 0.04;
const double _span = 0.94;
const double _steepness = 2.0;
const int _oneOffHorizonDays = 7;
const double _undatedBaseline = 0.35;

/// A task is "due" (surfaces; counts against `cleared`) when its urgency
/// exceeds this. Must sit strictly above [_floor] — the sigmoid only
/// approaches the floor, so a 0.04 cutoff would never be crossed. 0.30 ≈ the
/// urgency reached ~half an interval before due. Public: shared by selection.
const double dueThreshold = 0.30;

/// Calendar-day difference `b - a` (future positive). Uses UTC anchors on the
/// civil date components so DST never makes a day 23h/25h and skews the count.
int daysBetweenLocalDates(DateTime a, DateTime b) {
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x));

/// Urgency in [0,1]. A sigmoid in normalised lateness; undated one-offs get a
/// constant low-band baseline so they keep surfacing below any dated task.
double urgencyOf(Task task, DateTime now) {
  final due = task.dueAt;
  if (due == null) return _undatedBaseline; // only one-offs are undated
  final d = now.difference(due).inHours / 24.0; // fractional days late
  final n = task.kind == TaskKind.recurring
      ? task.intervalDays!
      : _oneOffHorizonDays;
  final r = d / n;
  final u = _floor + _span * _sigmoid(_steepness * r);
  return u.clamp(0.0, 1.0);
}

/// Daily-card label derived from the same inputs as [urgencyOf] (never stored).
String metaOf(Task task, DateTime now) {
  final completed = task.completedAt;
  if (completed != null && daysBetweenLocalDates(completed, now) == 0) {
    return 'done today';
  }
  final due = task.dueAt;
  if (due == null) return 'no deadline';
  final days = daysBetweenLocalDates(now, due); // >0 future, <0 past
  if (days < 0) {
    final n = -days;
    return n == 1 ? '1 day overdue' : '$n days overdue';
  }
  if (days == 0) return 'due today';
  if (days == 1) return 'due tomorrow';
  return 'due in $days days';
}

/// Manage-list label (the daily card stays meta-free). Recurring -> recurrence
/// cadence; one-off -> the due/overdue label from [metaOf].
String manageMeta(Task task, DateTime now) {
  if (task.kind == TaskKind.oneOff) return metaOf(task, now);
  final n = task.intervalDays!;
  return switch (n) {
    1 => 'Daily',
    7 => 'Weekly',
    14 => 'Fortnightly',
    30 => 'Monthly',
    _ when n % 30 == 0 => 'Every ${n ~/ 30} months',
    _ when n % 7 == 0 => 'Every ${n ~/ 7} weeks',
    _ => 'Every $n days',
  };
}
