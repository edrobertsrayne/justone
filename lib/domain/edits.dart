import 'task.dart';
import 'transitions.dart';
import 'urgency.dart' show daysBetweenLocalDates;
import 'user_state.dart';

enum DeadlineChoice { none, today, tomorrow, thisWeek, nextWeek, pickDate }
enum RepeatChoice { oneOff, every3, weekly, fortnightly, monthly, custom }
enum CustomUnit { days, weeks, months }

/// Deadline chip -> dueAt (date-only, local). Day arithmetic via the
/// year/month/day constructor so DST never shifts the result off midnight.
DateTime? dueAtFor(DeadlineChoice choice, DateTime now, {DateTime? pickedDate}) {
  DateTime plus(int days) => DateTime(now.year, now.month, now.day + days);
  return switch (choice) {
    DeadlineChoice.none => null,
    DeadlineChoice.today => plus(0),
    DeadlineChoice.tomorrow => plus(1),
    DeadlineChoice.thisWeek => plus(7),
    DeadlineChoice.nextWeek => plus(14),
    DeadlineChoice.pickDate =>
      DateTime(pickedDate!.year, pickedDate!.month, pickedDate!.day),
  };
}

/// dueAt -> the chip that produced it (for edit pre-selection).
DeadlineChoice deadlineChoiceFor(DateTime? dueAt, DateTime now) {
  if (dueAt == null) return DeadlineChoice.none;
  return switch (daysBetweenLocalDates(now, dueAt)) {
    0 => DeadlineChoice.today,
    1 => DeadlineChoice.tomorrow,
    7 => DeadlineChoice.thisWeek,
    14 => DeadlineChoice.nextWeek,
    _ => DeadlineChoice.pickDate,
  };
}

int _unitDays(CustomUnit u) => switch (u) {
      CustomUnit.days => 1,
      CustomUnit.weeks => 7,
      CustomUnit.months => 30,
    };

/// Repeat chip -> (kind, intervalDays). month == 30 days (matches "Monthly").
({TaskKind kind, int? intervalDays}) repeatToFields(
  RepeatChoice choice, {
  int customN = 2,
  CustomUnit customUnit = CustomUnit.weeks,
}) {
  return switch (choice) {
    RepeatChoice.oneOff => (kind: TaskKind.oneOff, intervalDays: null),
    RepeatChoice.every3 => (kind: TaskKind.recurring, intervalDays: 3),
    RepeatChoice.weekly => (kind: TaskKind.recurring, intervalDays: 7),
    RepeatChoice.fortnightly => (kind: TaskKind.recurring, intervalDays: 14),
    RepeatChoice.monthly => (kind: TaskKind.recurring, intervalDays: 30),
    RepeatChoice.custom => (
        kind: TaskKind.recurring,
        intervalDays: customN.clamp(1, 99) * _unitDays(customUnit),
      ),
  };
}

/// (kind, intervalDays) -> chip selection. Presets win; otherwise Custom,
/// decomposed to the largest exact unit (months, then weeks, then days).
({RepeatChoice choice, int customN, CustomUnit customUnit}) repeatChoiceFor(
    TaskKind kind, int? intervalDays) {
  if (kind == TaskKind.oneOff || intervalDays == null) {
    return (choice: RepeatChoice.oneOff, customN: 2, customUnit: CustomUnit.weeks);
  }
  switch (intervalDays) {
    case 3:
      return (choice: RepeatChoice.every3, customN: 3, customUnit: CustomUnit.days);
    case 7:
      return (choice: RepeatChoice.weekly, customN: 1, customUnit: CustomUnit.weeks);
    case 14:
      return (choice: RepeatChoice.fortnightly, customN: 2, customUnit: CustomUnit.weeks);
    case 30:
      return (choice: RepeatChoice.monthly, customN: 1, customUnit: CustomUnit.months);
  }
  if (intervalDays % 30 == 0) {
    return (choice: RepeatChoice.custom, customN: intervalDays ~/ 30, customUnit: CustomUnit.months);
  }
  if (intervalDays % 7 == 0) {
    return (choice: RepeatChoice.custom, customN: intervalDays ~/ 7, customUnit: CustomUnit.weeks);
  }
  return (choice: RepeatChoice.custom, customN: intervalDays, customUnit: CustomUnit.days);
}

/// Assemble a new/edited Task from chip selections. Used by PoolController so
/// the chip->field mapping is unit-tested independently of the UI.
Task buildTask({
  required String id,
  required String title,
  required DeadlineChoice deadline,
  DateTime? pickedDate,
  required RepeatChoice repeat,
  int customN = 2,
  CustomUnit customUnit = CustomUnit.weeks,
  required DateTime createdAt,
  required DateTime now,
  TaskStatus status = TaskStatus.active,
  DateTime? completedAt,
}) {
  final r = repeatToFields(repeat, customN: customN, customUnit: customUnit);
  return Task(
    id: id,
    title: title.trim(),
    kind: r.kind,
    intervalDays: r.intervalDays,
    dueAt: dueAtFor(deadline, now, pickedDate: pickedDate),
    createdAt: createdAt,
    completedAt: completedAt,
    status: status,
  );
}

/// Onboarding batch seed (D23): N task docs + target + onboardingComplete +
/// lastActiveDate, committed in one WriteBatch. Reminders defaults are already
/// written at bootstrap, so they are not re-written here.
TransitionResult seedOnboarding(UserState state,
    {required int target, required List<Task> tasks, required DateTime now}) {
  return TransitionResult(
    user: state.copyWith(
      target: target,
      onboardingComplete: true,
      lastActiveDate: DateTime(now.year, now.month, now.day),
    ),
    changedTasks: tasks,
  );
}

/// Add or edit a single task. User is unchanged; commit re-merges it (D9 LWW).
TransitionResult saveTask(UserState state, Task task) =>
    TransitionResult(user: state, changedTasks: [task]);

/// Settings write — target and/or reminder arrays.
TransitionResult updateSettings(UserState state,
    {int? target, List<String>? weekday, List<String>? weekend}) {
  return TransitionResult(
    user: state.copyWith(
      target: target,
      remindersWeekday: weekday,
      remindersWeekend: weekend,
    ),
    changedTasks: const [],
  );
}
