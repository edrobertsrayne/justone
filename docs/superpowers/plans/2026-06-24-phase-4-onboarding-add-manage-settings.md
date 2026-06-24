# Phase 4 — Onboarding + Add / Manage / Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first-run onboarding wizard, the add/edit (enrich) flow, the manage-pool screen, the settings screen, and the designed welcome screen, with first-run routing gated on `onboardingComplete`.

**Architecture:** Every write is a pure domain function returning a `TransitionResult`, committed through the existing `Repository.commit` `WriteBatch` seam (Phases 1–3). The only new seam method is `Repository.newTaskId()` for ID allocation. Screens are derived from the pure `routeHome` (onboarding) or reached as `Navigator` pushes (manage/settings) / modal bottom sheets (add/enrich). UI is recreated idiomatically from the locked prototype.

**Tech Stack:** Flutter, Riverpod 3 (manual providers), Firebase Auth + Cloud Firestore (behind the `Repository`/`AuthService` seams), `flutter_test` + `fake_cloud_firestore` + `firebase_auth_mocks`.

## Global Constraints

- **No new runtime dependencies.** No `intl`, no `uuid`. Format dates/times by hand (zero-padded), as `firestore_mappers._dateToString` already does. Task IDs come from `Repository.newTaskId()`.
- **`Repository` is the only data seam.** No Firebase imports in `lib/` outside `lib/data/firestore_*.dart`, `lib/auth/`, `lib/main.dart`. Domain, UI, and controllers must not import `cloud_firestore`, `firebase_auth`, or `google_sign_in`.
- **Every write is `commit(TransitionResult)`** built by a pure function. No direct Firestore writes from controllers/UI.
- **`now` always via `nowProvider`** (the `Clock` typedef = `DateTime Function()`). Never `DateTime.now()` in domain/controllers/screens.
- **Firestore field names are canonical** per `backend-decisions.md`. `urg`/`meta`/`screen` are never persisted (D6); `dueAt` nullable timestamp; `lastActiveDate` a `'YYYY-MM-DD'` string; `reminders` = `{weekday:[...0–3], weekend:[...0–3]}` of `"HH:mm"` strings (D17).
- **Google Sign-In only, mandatory (D8).** Apple/email appear disabled in the welcome UI.
- **Restraint on the daily card** — no meta/badges there; per-task labels live only on manage.
- **Target clamps 1–6; reminder arrays clamp 0–3 per group, sorted ascending `"HH:mm"`.**
- **Keep files under ~1,000 lines.** Factor shared widgets out.
- **Tests are Dart-fakes-only** — `flutter test`, no device/emulator. Establish a listener before awaiting a `StreamProvider.future` in unit tests (see CLAUDE.md learning).
- **Every commit** uses a conventional message and ends with the trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Run the whole suite with `flutter test`. Run one file with `flutter test test/path/file.dart`.

---

## File Structure

**Create:**
- `lib/domain/edits.dart` — chip enums, deadline/repeat ↔ field maps, `buildTask`, and the pure write builders (`seedOnboarding`, `saveTask`, `updateSettings`).
- `lib/app/onboarding_controller.dart`, `lib/app/pool_controller.dart`, `lib/app/settings_controller.dart` — thin action layers.
- `lib/ui/widgets/target_stepper.dart` — shared 1–6 stepper (onboarding + settings).
- `lib/ui/welcome_screen.dart` — replaces `sign_in_screen.dart`.
- `lib/ui/onboarding_flow.dart` — two-step wizard.
- `lib/ui/add_sheet.dart`, `lib/ui/enrich_sheet.dart` — modal bottom sheets.
- `lib/ui/manage_screen.dart`, `lib/ui/settings_screen.dart` — full-screen pushes.
- Matching test files under `test/domain`, `test/app`, `test/ui`.

**Modify:**
- `lib/domain/urgency.dart` — add `manageMeta`.
- `lib/domain/routing.dart` — onboarding gate.
- `lib/data/repository.dart`, `lib/data/firestore_repository.dart`, `lib/data/in_memory_repository.dart` — `newTaskId()`.
- `lib/auth/auth_service.dart` — cancel handling + `signOut` guard.
- `lib/ui/home_router.dart`, `lib/ui/daily_screen.dart`, `lib/ui/cleared_screen.dart`, `lib/ui/empty_pool_screen.dart` — real navigation.
- `lib/auth/auth_gate.dart`, `lib/main.dart` — reference `WelcomeScreen`; drop dangling `(D18)` comment.
- `test/domain/routing_test.dart`, `test/app_smoke_test.dart` — set `onboardingComplete: true` on routed users.
- `docs/IMPLEMENTATION-ROADMAP.md`, `CLAUDE.md` — status + learnings.

**Delete:**
- `lib/ui/sign_in_screen.dart` and `test/ui/sign_in_screen_test.dart` (replaced by welcome).

---

## Key Interfaces (defined once; tasks reference these exact signatures)

```dart
// lib/domain/edits.dart
enum DeadlineChoice { none, today, tomorrow, thisWeek, nextWeek, pickDate }
enum RepeatChoice { oneOff, every3, weekly, fortnightly, monthly, custom }
enum CustomUnit { days, weeks, months }

DateTime? dueAtFor(DeadlineChoice choice, DateTime now, {DateTime? pickedDate});
DeadlineChoice deadlineChoiceFor(DateTime? dueAt, DateTime now);
({TaskKind kind, int? intervalDays}) repeatToFields(
    RepeatChoice choice, {int customN, CustomUnit customUnit});
({RepeatChoice choice, int customN, CustomUnit customUnit}) repeatChoiceFor(
    TaskKind kind, int? intervalDays);
Task buildTask({
  required String id, required String title,
  required DeadlineChoice deadline, DateTime? pickedDate,
  required RepeatChoice repeat, int customN, CustomUnit customUnit,
  required DateTime createdAt, required DateTime now,
  TaskStatus status, DateTime? completedAt,
});
TransitionResult seedOnboarding(UserState state,
    {required int target, required List<Task> tasks, required DateTime now});
TransitionResult saveTask(UserState state, Task task);       // add + edit
TransitionResult updateSettings(UserState state,
    {int? target, List<String>? weekday, List<String>? weekend});

// lib/domain/urgency.dart
String manageMeta(Task task, DateTime now);

// lib/data/repository.dart (added to the abstract Repository)
String newTaskId();
```

---

### Task 1: Deadline & repeat chip value maps

**Files:**
- Create: `lib/domain/edits.dart`
- Test: `test/domain/edits_maps_test.dart`

**Interfaces:**
- Consumes: `Task`, `TaskKind` from `lib/domain/task.dart`; `daysBetweenLocalDates` from `lib/domain/urgency.dart`.
- Produces: the four map functions + three enums in the Key Interfaces block.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/edits_maps_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/edits.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9); // a Wednesday, 09:00

  group('dueAtFor', () {
    test('none -> null', () => expect(dueAtFor(DeadlineChoice.none, now), isNull));
    test('today -> midnight today', () =>
        expect(dueAtFor(DeadlineChoice.today, now), DateTime(2026, 6, 24)));
    test('tomorrow -> +1 day', () =>
        expect(dueAtFor(DeadlineChoice.tomorrow, now), DateTime(2026, 6, 25)));
    test('this week -> +7 days', () =>
        expect(dueAtFor(DeadlineChoice.thisWeek, now), DateTime(2026, 7, 1)));
    test('next week -> +14 days', () =>
        expect(dueAtFor(DeadlineChoice.nextWeek, now), DateTime(2026, 7, 8)));
    test('pickDate -> date-only of picked', () =>
        expect(dueAtFor(DeadlineChoice.pickDate, now, pickedDate: DateTime(2026, 8, 3, 14)),
            DateTime(2026, 8, 3)));
  });

  group('deadlineChoiceFor (reverse)', () {
    test('null -> none', () => expect(deadlineChoiceFor(null, now), DeadlineChoice.none));
    test('today', () => expect(deadlineChoiceFor(DateTime(2026, 6, 24), now), DeadlineChoice.today));
    test('tomorrow', () => expect(deadlineChoiceFor(DateTime(2026, 6, 25), now), DeadlineChoice.tomorrow));
    test('+7 -> thisWeek', () => expect(deadlineChoiceFor(DateTime(2026, 7, 1), now), DeadlineChoice.thisWeek));
    test('+14 -> nextWeek', () => expect(deadlineChoiceFor(DateTime(2026, 7, 8), now), DeadlineChoice.nextWeek));
    test('non-preset -> pickDate', () => expect(deadlineChoiceFor(DateTime(2026, 6, 30), now), DeadlineChoice.pickDate));
  });

  group('repeatToFields', () {
    test('oneOff', () => expect(repeatToFields(RepeatChoice.oneOff), (kind: TaskKind.oneOff, intervalDays: null)));
    test('every3', () => expect(repeatToFields(RepeatChoice.every3), (kind: TaskKind.recurring, intervalDays: 3)));
    test('weekly', () => expect(repeatToFields(RepeatChoice.weekly), (kind: TaskKind.recurring, intervalDays: 7)));
    test('fortnightly', () => expect(repeatToFields(RepeatChoice.fortnightly), (kind: TaskKind.recurring, intervalDays: 14)));
    test('monthly', () => expect(repeatToFields(RepeatChoice.monthly), (kind: TaskKind.recurring, intervalDays: 30)));
    test('custom 3 weeks -> 21', () => expect(
        repeatToFields(RepeatChoice.custom, customN: 3, customUnit: CustomUnit.weeks),
        (kind: TaskKind.recurring, intervalDays: 21)));
    test('custom clamps N to 1..99', () => expect(
        repeatToFields(RepeatChoice.custom, customN: 0, customUnit: CustomUnit.days).intervalDays, 1));
  });

  group('repeatChoiceFor (reverse)', () {
    test('oneOff', () => expect(repeatChoiceFor(TaskKind.oneOff, null).choice, RepeatChoice.oneOff));
    test('7 -> weekly', () => expect(repeatChoiceFor(TaskKind.recurring, 7).choice, RepeatChoice.weekly));
    test('30 -> monthly', () => expect(repeatChoiceFor(TaskKind.recurring, 30).choice, RepeatChoice.monthly));
    test('21 -> custom 3 weeks', () {
      final r = repeatChoiceFor(TaskKind.recurring, 21);
      expect((r.choice, r.customN, r.customUnit), (RepeatChoice.custom, 3, CustomUnit.weeks));
    });
    test('60 -> custom 2 months', () {
      final r = repeatChoiceFor(TaskKind.recurring, 60);
      expect((r.choice, r.customN, r.customUnit), (RepeatChoice.custom, 2, CustomUnit.months));
    });
    test('5 -> custom 5 days', () {
      final r = repeatChoiceFor(TaskKind.recurring, 5);
      expect((r.choice, r.customN, r.customUnit), (RepeatChoice.custom, 5, CustomUnit.days));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/edits_maps_test.dart`
Expected: FAIL — `edits.dart` and its symbols do not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/edits.dart
import 'task.dart';
import 'urgency.dart' show daysBetweenLocalDates;

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/edits_maps_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/edits.dart test/domain/edits_maps_test.dart
git commit -m "feat(domain): deadline/repeat chip <-> field maps"
```

---

### Task 2: `buildTask` assembly + `manageMeta` label

**Files:**
- Modify: `lib/domain/edits.dart`
- Modify: `lib/domain/urgency.dart`
- Test: `test/domain/edits_build_test.dart`, `test/domain/manage_meta_test.dart`

**Interfaces:**
- Consumes: Task 1's maps; `metaOf` from `lib/domain/urgency.dart`.
- Produces: `buildTask(...)` and `manageMeta(task, now)` per Key Interfaces.

- [ ] **Step 1: Write the failing tests**

```dart
// test/domain/edits_build_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/edits.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);

  test('builds a recurring task with deadline + custom repeat, trimming title', () {
    final t = buildTask(
      id: 'a', title: '  Water the plants ',
      deadline: DeadlineChoice.tomorrow,
      repeat: RepeatChoice.custom, customN: 2, customUnit: CustomUnit.weeks,
      createdAt: DateTime(2026, 6, 1), now: now,
    );
    expect(t.id, 'a');
    expect(t.title, 'Water the plants');
    expect(t.kind, TaskKind.recurring);
    expect(t.intervalDays, 14);
    expect(t.dueAt, DateTime(2026, 6, 25));
    expect(t.status, TaskStatus.active);
  });

  test('one-off, no deadline preserves passed-in status/createdAt/completedAt (edit)', () {
    final t = buildTask(
      id: 'b', title: 'Back up laptop',
      deadline: DeadlineChoice.none, repeat: RepeatChoice.oneOff,
      createdAt: DateTime(2026, 5, 1), now: now,
      status: TaskStatus.benched, completedAt: DateTime(2026, 6, 20),
    );
    expect(t.kind, TaskKind.oneOff);
    expect(t.intervalDays, isNull);
    expect(t.dueAt, isNull);
    expect(t.createdAt, DateTime(2026, 5, 1));
    expect(t.status, TaskStatus.benched);
    expect(t.completedAt, DateTime(2026, 6, 20));
  });
}
```

```dart
// test/domain/manage_meta_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/urgency.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  Task rec(int n) => Task(id: 'r', title: 'r', kind: TaskKind.recurring, intervalDays: n, createdAt: now);

  test('recurring presets', () {
    expect(manageMeta(rec(1), now), 'Daily');
    expect(manageMeta(rec(3), now), 'Every 3 days');
    expect(manageMeta(rec(7), now), 'Weekly');
    expect(manageMeta(rec(14), now), 'Fortnightly');
    expect(manageMeta(rec(30), now), 'Monthly');
  });

  test('recurring custom decomposition', () {
    expect(manageMeta(rec(21), now), 'Every 3 weeks');
    expect(manageMeta(rec(60), now), 'Every 2 months');
    expect(manageMeta(rec(5), now), 'Every 5 days');
  });

  test('one-off defers to metaOf', () {
    final oneOff = Task(id: 'o', title: 'o', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 25), createdAt: now);
    expect(manageMeta(oneOff, now), 'due tomorrow');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/domain/edits_build_test.dart test/domain/manage_meta_test.dart`
Expected: FAIL — `buildTask` and `manageMeta` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/domain/edits.dart`:

```dart
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
```

Append to `lib/domain/urgency.dart`:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/edits_build_test.dart test/domain/manage_meta_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/edits.dart lib/domain/urgency.dart test/domain/edits_build_test.dart test/domain/manage_meta_test.dart
git commit -m "feat(domain): buildTask assembly + manageMeta label"
```

---

### Task 3: Pure write builders (`seedOnboarding`, `saveTask`, `updateSettings`)

**Files:**
- Modify: `lib/domain/edits.dart`
- Test: `test/domain/edits_builders_test.dart`

**Interfaces:**
- Consumes: `TransitionResult` from `lib/domain/transitions.dart`; `UserState`; `Task`.
- Produces: `seedOnboarding`, `saveTask`, `updateSettings` per Key Interfaces. (One `saveTask` serves both add and edit — the spec's `addTask`/`editTask` are identical, so they are unified here, DRY.)

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/edits_builders_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/edits.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  UserState base() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 20));

  test('seedOnboarding flips onboardingComplete, sets target + lastActiveDate, carries tasks', () {
    final tasks = [Task(id: 'a', title: 'Dishes', kind: TaskKind.oneOff, createdAt: now)];
    final r = seedOnboarding(base(), target: 4, tasks: tasks, now: now);
    expect(r.user.onboardingComplete, isTrue);
    expect(r.user.target, 4);
    expect(r.user.lastActiveDate, DateTime(2026, 6, 24));
    expect(r.changedTasks, tasks);
  });

  test('saveTask returns the task and an unchanged user', () {
    final u = base();
    final t = Task(id: 'x', title: 'X', kind: TaskKind.oneOff, createdAt: now);
    final r = saveTask(u, t);
    expect(r.user, u);
    expect(r.changedTasks, [t]);
  });

  test('updateSettings writes only the provided fields', () {
    final r = updateSettings(base(), target: 5, weekday: const ['08:00'], weekend: const []);
    expect(r.user.target, 5);
    expect(r.user.remindersWeekday, const ['08:00']);
    expect(r.user.remindersWeekend, const []);
    expect(r.changedTasks, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/edits_builders_test.dart`
Expected: FAIL — builders undefined.

- [ ] **Step 3: Write minimal implementation**

Add imports + functions to `lib/domain/edits.dart`:

```dart
import 'transitions.dart';
import 'user_state.dart';
```

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/edits_builders_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/edits.dart test/domain/edits_builders_test.dart
git commit -m "feat(domain): seedOnboarding/saveTask/updateSettings builders"
```

---

### Task 4: Onboarding gate in `routeHome`

**Files:**
- Modify: `lib/domain/routing.dart:21-34`
- Modify: `test/domain/routing_test.dart`
- Modify: `test/app_smoke_test.dart:21`

**Interfaces:**
- Consumes: `UserState.onboardingComplete`.
- Produces: `routeHome` returns `AppScreen.onboardTarget` when `!onboardingComplete`, else unchanged.

- [ ] **Step 1: Update existing tests, then add the gate test (write the failing test)**

In `test/domain/routing_test.dart`, change the base user (line 9) to be onboarded, and add a gate test:

```dart
final user = UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true);
```

```dart
  test('not onboarded -> onboardTarget regardless of pool', () {
    final fresh = UserState(timezone: 'UTC', lastActiveDate: now); // onboardingComplete defaults false
    expect(routeHome(fresh, const [], now), AppScreen.onboardTarget);
    expect(routeHome(fresh, [due('a')], now), AppScreen.onboardTarget);
  });
```

In `test/app_smoke_test.dart`, set the seeded user onboarded (line ~21):

```dart
      UserState(timezone: 'UTC', target: 3, lastActiveDate: DateTime(2026, 6, 24), onboardingComplete: true),
```

- [ ] **Step 2: Run tests to verify the new test fails**

Run: `flutter test test/domain/routing_test.dart`
Expected: FAIL — `not onboarded -> onboardTarget` fails (currently returns `emptyPool`/`daily`).

- [ ] **Step 3: Add the gate as the first decision in `routeHome`**

In `lib/domain/routing.dart`, immediately inside `routeHome` before the `poolEmpty` line:

```dart
AppScreen routeHome(UserState state, List<Task> tasks, DateTime now) {
  if (!state.onboardingComplete) return AppScreen.onboardTarget;
  final poolEmpty = !tasks.any((t) =>
      t.status == TaskStatus.active || t.status == TaskStatus.benched);
  // ...unchanged...
```

- [ ] **Step 4: Run the full suite to verify routing + smoke pass**

Run: `flutter test test/domain/routing_test.dart test/app_smoke_test.dart test/ui/home_router_test.dart`
Expected: PASS (home_router already uses onboarded users).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/routing.dart test/domain/routing_test.dart test/app_smoke_test.dart
git commit -m "feat(domain): gate first-run on onboardingComplete in routeHome"
```

---

### Task 5: `Repository.newTaskId()`

**Files:**
- Modify: `lib/data/repository.dart`
- Modify: `lib/data/firestore_repository.dart`
- Modify: `lib/data/in_memory_repository.dart`
- Test: `test/data/in_memory_repository_test.dart` (append), `test/data/firestore_repository_test.dart` (append)

**Interfaces:**
- Produces: `String newTaskId()` on `Repository` and both implementations.

- [ ] **Step 1: Write the failing tests**

Append to `test/data/in_memory_repository_test.dart`:

```dart
  test('newTaskId returns distinct ids', () {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
      tasks: const [],
    );
    final a = repo.newTaskId();
    final b = repo.newTaskId();
    expect(a, isNotEmpty);
    expect(a, isNot(b));
  });
```

(Ensure `UserState` is imported in that file; add the import if missing.)

Append to `test/data/firestore_repository_test.dart`:

```dart
  test('newTaskId returns distinct non-empty ids', () {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreRepository(db, 'u1');
    expect(repo.newTaskId(), isNotEmpty);
    expect(repo.newTaskId(), isNot(repo.newTaskId()));
  });
```

(Use the imports already present in that test file: `FakeFirebaseFirestore`, `FirestoreRepository`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/in_memory_repository_test.dart test/data/firestore_repository_test.dart`
Expected: FAIL — `newTaskId` not defined.

- [ ] **Step 3: Implement on the interface + both impls**

`lib/data/repository.dart` — add to the abstract class:

```dart
  /// Allocate a new, unique task id. Firestore uses a client-side auto-id;
  /// the in-memory fake uses a counter.
  String newTaskId();
```

`lib/data/firestore_repository.dart` — add a method:

```dart
  @override
  String newTaskId() => _tasksRef.doc().id;
```

`lib/data/in_memory_repository.dart` — add a counter field and method:

```dart
  int _idSeq = 0;

  @override
  String newTaskId() => 'gen-${_idSeq++}';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/in_memory_repository_test.dart test/data/firestore_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repository.dart lib/data/firestore_repository.dart lib/data/in_memory_repository.dart test/data/in_memory_repository_test.dart test/data/firestore_repository_test.dart
git commit -m "feat(data): add Repository.newTaskId for client-side id allocation"
```

---

### Task 6: `OnboardingController`

**Files:**
- Create: `lib/app/onboarding_controller.dart`
- Test: `test/app/onboarding_controller_test.dart`

**Interfaces:**
- Consumes: `Repository` (`newTaskId`, `commit`), `Clock` from `lib/app/providers.dart`, `seedOnboarding` from `edits.dart`.
- Produces:
  - `class OnboardingController { OnboardingController({required Repository repo, required Clock now}); Future<void> finish(UserState user, {required int target, required List<String> titles}); }`
  - `final onboardingControllerProvider = Provider<OnboardingController>(...)`

- [ ] **Step 1: Write the failing test**

```dart
// test/app/onboarding_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/onboarding_controller.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  UserState fresh() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 20));

  ({OnboardingController c, InMemoryRepository repo, ProviderContainer container}) harness(UserState u) {
    final repo = InMemoryRepository(user: u, tasks: const []);
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      nowProvider.overrideWithValue(() => now),
    ]);
    return (c: container.read(onboardingControllerProvider), repo: repo, container: container);
  }

  test('finish seeds trimmed, de-duplicated tasks and flips onboardingComplete', () async {
    final h = harness(fresh());
    addTearDown(h.container.dispose);
    await h.c.finish(fresh(), target: 2, titles: ['Dishes', ' Dishes ', '', 'Laundry']);

    final user = await h.repo.watchUser().first;
    final tasks = await h.repo.watchTasks().first;
    expect(user.onboardingComplete, isTrue);
    expect(user.target, 2);
    expect(tasks.map((t) => t.title).toList(), ['Dishes', 'Laundry']);
    expect(tasks.every((t) => t.kind == TaskKind.oneOff && t.dueAt == null), isTrue);
    expect(tasks.map((t) => t.id).toSet().length, 2); // distinct ids
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app/onboarding_controller_test.dart`
Expected: FAIL — controller/provider undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/app/onboarding_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/edits.dart';
import '../domain/task.dart';
import '../domain/user_state.dart';
import 'providers.dart';

/// Builds the onboarding batch seed (D23) and commits it in one WriteBatch.
class OnboardingController {
  OnboardingController({required Repository repo, required Clock now})
      : _repo = repo,
        _now = now;

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app/onboarding_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/onboarding_controller.dart test/app/onboarding_controller_test.dart
git commit -m "feat(app): OnboardingController batch seed"
```

---

### Task 7: `PoolController` (add / edit / remove)

**Files:**
- Create: `lib/app/pool_controller.dart`
- Test: `test/app/pool_controller_test.dart`

**Interfaces:**
- Consumes: `Repository`, `ToastController` (`toastProvider.notifier`), `Clock`, `buildTask`/`saveTask` from `edits.dart`, `remove` from `transitions.dart`, the chip enums.
- Produces:
  - `class PoolController` with:
    - `Future<void> add(UserState user, {required String title, required DeadlineChoice deadline, DateTime? pickedDate, required RepeatChoice repeat, int customN, CustomUnit customUnit})`
    - `Future<void> edit(UserState user, Task original, {required String title, required DeadlineChoice deadline, DateTime? pickedDate, required RepeatChoice repeat, int customN, CustomUnit customUnit})`
    - `Future<void> remove(UserState user, Task task)`
  - `final poolControllerProvider = Provider<PoolController>(...)`

- [ ] **Step 1: Write the failing test**

```dart
// test/app/pool_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/pool_controller.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/app/toast_controller.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/edits.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9);
  UserState user() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24), onboardingComplete: true);
  Task seed() => Task(id: 't1', title: 'Old', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

  ({PoolController c, InMemoryRepository repo, ProviderContainer container}) harness() {
    final repo = InMemoryRepository(user: user(), tasks: [seed()]);
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      nowProvider.overrideWithValue(() => now),
    ]);
    return (c: container.read(poolControllerProvider), repo: repo, container: container);
  }

  test('add creates a recurring task with the mapped fields', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.add(user(), title: 'Water plants', deadline: DeadlineChoice.today, repeat: RepeatChoice.weekly);
    final tasks = await h.repo.watchTasks().first;
    final added = tasks.firstWhere((t) => t.title == 'Water plants');
    expect(added.kind, TaskKind.recurring);
    expect(added.intervalDays, 7);
    expect(added.dueAt, DateTime(2026, 6, 24));
  });

  test('edit preserves id/createdAt/status and updates fields', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.edit(user(), seed(), title: 'New title', deadline: DeadlineChoice.tomorrow, repeat: RepeatChoice.oneOff);
    final tasks = await h.repo.watchTasks().first;
    final edited = tasks.firstWhere((t) => t.id == 't1');
    expect(edited.title, 'New title');
    expect(edited.dueAt, DateTime(2026, 6, 25));
    expect(edited.createdAt, DateTime(2026, 6, 1));
  });

  test('remove archives via status:removed and toasts', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.remove(user(), seed());
    final tasks = await h.repo.watchTasks().first;
    expect(tasks.where((t) => t.id == 't1'), isEmpty); // filtered out (removed)
    expect(h.container.read(toastProvider), 'Deleted "Old"');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app/pool_controller_test.dart`
Expected: FAIL — controller undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/app/pool_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/edits.dart';
import '../domain/task.dart';
import '../domain/transitions.dart' as domain;
import '../domain/user_state.dart';
import 'providers.dart';
import 'toast_controller.dart';

/// Add/edit/remove pool tasks. Each builds a task (or reuses domain.remove),
/// then commits through the Repository seam.
class PoolController {
  PoolController({required Repository repo, required ToastController toast, required Clock now})
      : _repo = repo,
        _toast = toast,
        _now = now;

  final Repository _repo;
  final ToastController _toast;
  final Clock _now;

  Future<void> add(
    UserState user, {
    required String title,
    required DeadlineChoice deadline,
    DateTime? pickedDate,
    required RepeatChoice repeat,
    int customN = 2,
    CustomUnit customUnit = CustomUnit.weeks,
  }) {
    final now = _now();
    final task = buildTask(
      id: _repo.newTaskId(),
      title: title,
      deadline: deadline,
      pickedDate: pickedDate,
      repeat: repeat,
      customN: customN,
      customUnit: customUnit,
      createdAt: now,
      now: now,
    );
    return _repo.commit(saveTask(user, task));
  }

  Future<void> edit(
    UserState user,
    Task original, {
    required String title,
    required DeadlineChoice deadline,
    DateTime? pickedDate,
    required RepeatChoice repeat,
    int customN = 2,
    CustomUnit customUnit = CustomUnit.weeks,
  }) {
    final task = buildTask(
      id: original.id,
      title: title,
      deadline: deadline,
      pickedDate: pickedDate,
      repeat: repeat,
      customN: customN,
      customUnit: customUnit,
      createdAt: original.createdAt,
      now: _now(),
      status: original.status,
      completedAt: original.completedAt,
    );
    return _repo.commit(saveTask(user, task));
  }

  Future<void> remove(UserState user, Task task) {
    _toast.show('Deleted "${task.title}"');
    return _repo.commit(domain.remove(user, task));
  }
}

final poolControllerProvider = Provider<PoolController>(
  (ref) => PoolController(
    repo: ref.watch(repositoryProvider),
    toast: ref.watch(toastProvider.notifier),
    now: ref.watch(nowProvider),
  ),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app/pool_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/pool_controller.dart test/app/pool_controller_test.dart
git commit -m "feat(app): PoolController add/edit/remove"
```

---

### Task 8: `SettingsController` (target + reminders)

**Files:**
- Create: `lib/app/settings_controller.dart`
- Test: `test/app/settings_controller_test.dart`

**Interfaces:**
- Consumes: `Repository`, `updateSettings` from `edits.dart`.
- Produces:
  - `class SettingsController` with `Future<void> setTarget(UserState user, int target)` and `Future<void> setReminders(UserState user, {required List<String> weekday, required List<String> weekend})`.
  - `final settingsControllerProvider = Provider<SettingsController>(...)`

- [ ] **Step 1: Write the failing test**

```dart
// test/app/settings_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/app/settings_controller.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  UserState user() => UserState(timezone: 'UTC', target: 3, lastActiveDate: DateTime(2026, 6, 24), onboardingComplete: true);

  ({SettingsController c, InMemoryRepository repo, ProviderContainer container}) harness() {
    final repo = InMemoryRepository(user: user(), tasks: const []);
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    return (c: container.read(settingsControllerProvider), repo: repo, container: container);
  }

  test('setTarget clamps to 1..6', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.setTarget(user(), 9);
    expect((await h.repo.watchUser().first).target, 6);
  });

  test('setReminders sorts and stores both arrays', () async {
    final h = harness();
    addTearDown(h.container.dispose);
    await h.c.setReminders(user(), weekday: ['18:30', '08:00'], weekend: ['10:00']);
    final u = await h.repo.watchUser().first;
    expect(u.remindersWeekday, ['08:00', '18:30']);
    expect(u.remindersWeekend, ['10:00']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app/settings_controller_test.dart`
Expected: FAIL — controller undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/app/settings_controller.dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app/settings_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/settings_controller.dart test/app/settings_controller_test.dart
git commit -m "feat(app): SettingsController target + reminders"
```

---

### Task 9: `TargetStepper` shared widget

**Files:**
- Create: `lib/ui/widgets/target_stepper.dart`
- Test: `test/ui/target_stepper_test.dart`

**Interfaces:**
- Produces: `class TargetStepper extends StatelessWidget { const TargetStepper({required this.value, required this.onChanged, this.numeralSize, super.key}); final int value; final ValueChanged<int> onChanged; final double? numeralSize; }` — renders `−  <value>  +`; buttons clamp 1–6 and call `onChanged` only within range.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/target_stepper_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/widgets/target_stepper.dart';

void main() {
  testWidgets('+ increments, − decrements, clamped 1..6', (tester) async {
    int value = 3;
    Widget build(int v) => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => TargetStepper(
                value: v,
                onChanged: (n) => setState(() => value = n),
              ),
            ),
          ),
        );
    await tester.pumpWidget(build(value));
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('target-inc')));
    await tester.pump();
    expect(value, 4);

    value = 6;
    await tester.pumpWidget(build(value));
    await tester.tap(find.byKey(const ValueKey('target-inc')));
    await tester.pump();
    expect(value, 6); // clamped at max

    value = 1;
    await tester.pumpWidget(build(value));
    await tester.tap(find.byKey(const ValueKey('target-dec')));
    await tester.pump();
    expect(value, 1); // clamped at min
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/target_stepper_test.dart`
Expected: FAIL — `TargetStepper` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/widgets/target_stepper.dart
import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/type_scale.dart';

/// −  value  +  stepper, clamped to 1..6. Shared by onboarding + settings.
class TargetStepper extends StatelessWidget {
  const TargetStepper({
    required this.value,
    required this.onChanged,
    this.numeralSize = 57.5,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double numeralSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          glyph: '−',
          key: const ValueKey('target-dec'),
          enabled: value > 1,
          onTap: () => onChanged(value - 1),
        ),
        const SizedBox(width: 18),
        Text('$value',
            style: TypeScale.serif(numeralSize, weight: FontWeight.w500, color: Palette.ink)),
        const SizedBox(width: 18),
        _StepButton(
          glyph: '+',
          key: const ValueKey('target-inc'),
          enabled: value < 6,
          onTap: () => onChanged(value + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.glyph, required this.enabled, required this.onTap, super.key});

  final String glyph;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF6F3EC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE7E2D8), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(glyph,
            style: TypeScale.sans(22,
                weight: FontWeight.w600,
                color: enabled ? Palette.ink : const Color(0xFFCFC9BD))),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/target_stepper_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/target_stepper.dart test/ui/target_stepper_test.dart
git commit -m "feat(ui): shared TargetStepper widget"
```

---

### Task 10: `WelcomeScreen` + `AuthService` cleanups (§F)

**Files:**
- Modify: `lib/auth/auth_service.dart`
- Create: `lib/ui/welcome_screen.dart`
- Delete: `lib/ui/sign_in_screen.dart`, `test/ui/sign_in_screen_test.dart`
- Modify: `lib/auth/auth_gate.dart:7,21,29`, `lib/main.dart` (drop dangling `(D18)` comment if present)
- Test: `test/ui/welcome_screen_test.dart`

**Interfaces:**
- Consumes: `authServiceProvider` from `lib/auth/auth_providers.dart`.
- Produces: `class WelcomeScreen extends ConsumerStatefulWidget`. `AuthService.signInWithGoogle()` now returns normally on user-cancel (no throw) and throws a generic error otherwise; `signOut()` skips Google sign-out when never initialized.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/welcome_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/auth_service.dart';
import 'package:justone/ui/welcome_screen.dart';

class _FakeAuth implements AuthService {
  _FakeAuth({this.error});
  final Object? error;
  int signInCalls = 0;
  @override
  Future<void> signInWithGoogle() async {
    signInCalls++;
    if (error != null) throw error!;
  }
  @override
  Future<void> signOut() async {}
}

void main() {
  Widget host(AuthService auth) => ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: WelcomeScreen()),
      );

  testWidgets('renders wordmark and Google CTA; tap calls sign-in', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(host(auth));
    expect(find.text('Just One'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(auth.signInCalls, 1);
  });

  testWidgets('a sign-in failure shows the error message', (tester) async {
    await tester.pumpWidget(host(_FakeAuth(error: StateError('boom'))));
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(find.textContaining('Sign-in failed'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/welcome_screen_test.dart`
Expected: FAIL — `WelcomeScreen` undefined.

- [ ] **Step 3: Refactor `AuthService`, then build `WelcomeScreen`**

In `lib/auth/auth_service.dart`, swallow user-cancel and guard `signOut`:

```dart
  @override
  Future<void> signInWithGoogle() async {
    try {
      if (!_initialized) {
        await GoogleSignIn.instance.initialize();
        _initialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google Sign-In returned no ID token; check the OAuth client configuration.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return; // user backed out — silent
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    if (_initialized) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
```

Create `lib/ui/welcome_screen.dart` (no `google_sign_in` import — cancel is handled in the service). Lift exact colours/sizes/spacing from the prototype `WELCOME / LOGIN` block (`Chore App Designs.dc.html:69-88`):

```dart
// lib/ui/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';

/// First-run entry (D8): Google sign-in live; Apple/email shown as future.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TickMark(),
              const SizedBox(height: 24),
              Center(child: Text('Just One',
                  style: TypeScale.serif(45.5, weight: FontWeight.w500, color: Palette.ink))),
              const SizedBox(height: 8),
              Center(child: Text('One task a day. That’s enough.',
                  style: TypeScale.sans(15.8, color: Palette.muted))),
              const SizedBox(height: 48),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                _AuthButton(label: 'Continue with Google', filled: true, onTap: _signIn),
                const SizedBox(height: 10),
                const _AuthButton(label: 'Continue with Apple', filled: false, onTap: null),
                const SizedBox(height: 6),
                const Center(child: _DisabledText('Continue with email')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Center(child: Text(_error!, style: TypeScale.sans(12.4, color: Palette.terracotta))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TickMark extends StatelessWidget {
  const _TickMark();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
          alignment: Alignment.center,
          child: const Icon(Icons.check_rounded, color: Palette.iconCream, size: 40),
        ),
      );
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: filled ? Palette.ink : Colors.white,
          border: filled ? null : Border.all(color: const Color(0xFFE2DCCF), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TypeScale.sans(14,
                weight: FontWeight.w700,
                color: disabled
                    ? const Color(0xFFC2BCAE)
                    : (filled ? Palette.paper : Palette.ink))),
      ),
    );
  }
}

class _DisabledText extends StatelessWidget {
  const _DisabledText(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(label,
            style: TypeScale.sans(12.4, weight: FontWeight.w700, color: const Color(0xFFC2BCAE))),
      );
}
```

Update `lib/auth/auth_gate.dart`: replace the `import '../ui/sign_in_screen.dart';` with `import '../ui/welcome_screen.dart';` and both `SignInScreen()` usages with `WelcomeScreen()`. Delete `lib/ui/sign_in_screen.dart` and `test/ui/sign_in_screen_test.dart`. In `lib/main.dart`, remove the dangling `(D18)` comment reference if one remains.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/welcome_screen_test.dart test/auth/auth_gate_test.dart`
Expected: PASS. (If `auth_gate_test.dart` referenced `SignInScreen`, update it to `WelcomeScreen`.)

- [ ] **Step 5: Commit**

```bash
git add -A lib/auth/auth_service.dart lib/ui/welcome_screen.dart lib/auth/auth_gate.dart lib/main.dart lib/ui/sign_in_screen.dart test/ui/sign_in_screen_test.dart test/ui/welcome_screen_test.dart test/auth/auth_gate_test.dart
git commit -m "feat(ui): designed welcome screen; move Google cancel handling into AuthService"
```

---

### Task 11: `OnboardingFlow` wizard + HomeRouter wiring

**Files:**
- Create: `lib/ui/onboarding_flow.dart`
- Modify: `lib/ui/home_router.dart`
- Test: `test/ui/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: `userProvider`, `onboardingControllerProvider`, `TargetStepper`.
- Produces: `class OnboardingFlow extends ConsumerStatefulWidget`. `HomeRouter` renders it for `AppScreen.onboardTarget`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/onboarding_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/home_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  testWidgets('fresh user sees onboarding, completes it, lands on daily', (tester) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now), // onboardingComplete:false
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: HomeRouter()),
    ));
    await tester.pump();

    // Step 1: target
    expect(find.text('How much is enough?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();

    // Step 2: add chores via a suggestion chip
    expect(find.text("What's on your plate?"), findsOneWidget);
    await tester.tap(find.text('Dishes'));
    await tester.pump();
    await tester.tap(find.text('Start Just One'));
    await tester.pump(); // commit
    await tester.pump(); // stream re-emit -> re-route

    expect(find.byType(DailyScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/onboarding_flow_test.dart`
Expected: FAIL — `OnboardingFlow` undefined / HomeRouter has no onboarding case.

- [ ] **Step 3: Build `OnboardingFlow`, wire HomeRouter**

Create `lib/ui/onboarding_flow.dart` (lift spacing/copy from prototype `ONBOARD: TARGET` / `ONBOARD: ADD` blocks, `Chore App Designs.dc.html:90-150`). Two internal steps; suggestion chips toggle into a `titles` list; "Start Just One" calls `OnboardingController.finish`:

```dart
// lib/ui/onboarding_flow.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/onboarding_controller.dart';
import '../app/providers.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'widgets/target_stepper.dart';

const _suggestions = ['Dishes', 'Laundry', 'Water the plants', 'Reply to emails', 'Take the bins out', 'Make the bed'];

class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});
  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  int _step = 0;
  int _target = 3;
  final _titles = <String>[];
  final _draft = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _addDraft() {
    final t = _draft.text.trim();
    if (t.isEmpty || _titles.contains(t)) {
      _draft.clear();
      return;
    }
    setState(() { _titles.add(t); _draft.clear(); });
  }

  void _toggle(String title) => setState(() {
        _titles.contains(title) ? _titles.remove(title) : _titles.add(title);
      });

  Future<void> _finish() async {
    final user = ref.read(userProvider).value;
    if (user == null || _submitting) return;
    setState(() => _submitting = true);
    await ref.read(onboardingControllerProvider).finish(user, target: _target, titles: _titles);
    // onboardingComplete flips true -> the stream re-emits and HomeRouter re-routes.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: _step == 0 ? _buildTarget() : _buildAdd(),
        ),
      ),
    );
  }

  Widget _buildTarget() {
    return Column(
      children: [
        _eyebrow('Step 1 of 2'),
        const Spacer(),
        Text('DAILY TARGET',
            style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 2.4, color: Palette.accent)),
        const SizedBox(height: 14),
        Text('How much is enough?',
            textAlign: TextAlign.center,
            style: TypeScale.serif(31.9, weight: FontWeight.w500, color: Palette.ink)),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          child: Text("Finish this many in a day and you've done enough. Change it whenever.",
              textAlign: TextAlign.center, style: TypeScale.sans(14, height: 1.55, color: Palette.muted)),
        ),
        const SizedBox(height: 28),
        TargetStepper(value: _target, onChanged: (n) => setState(() => _target = n)),
        const Spacer(),
        _primary('Continue', () => setState(() => _step = 1)),
      ],
    );
  }

  Widget _buildAdd() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          GestureDetector(
            onTap: () => setState(() => _step = 0),
            child: const Icon(Icons.chevron_left, color: Color(0xFF6F6A60)),
          ),
          const Spacer(),
          _eyebrow('Step 2 of 2'),
          const Spacer(),
          const SizedBox(width: 24),
        ]),
        const SizedBox(height: 18),
        Text("What's on your plate?",
            style: TypeScale.serif(28.4, weight: FontWeight.w500, color: Palette.ink)),
        const SizedBox(height: 10),
        Text("Add a few. We'll surface one at a time — never the whole list.",
            style: TypeScale.sans(14, height: 1.5, color: Palette.muted)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _draft,
              onSubmitted: (_) => _addDraft(),
              decoration: InputDecoration(
                hintText: 'Add a chore…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _addDraft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(12)),
              child: Text('Add', style: TypeScale.sans(12.4, weight: FontWeight.w700, color: Palette.paper)),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              _Chip(label: s, selected: _titles.contains(s), onTap: () => _toggle(s)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              for (final t in _titles)
                ListTile(
                  dense: true,
                  title: Text(t, style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
                  trailing: GestureDetector(
                    onTap: () => setState(() => _titles.remove(t)),
                    child: const Icon(Icons.close, size: 18, color: Palette.terracotta),
                  ),
                ),
            ],
          ),
        ),
        _primary('Start Just One', _titles.isEmpty || _submitting ? null : _finish),
      ],
    );
  }

  Widget _eyebrow(String s) => Text(s.toUpperCase(),
      style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 1.8, color: const Color(0xFFB3AC9E)));

  Widget _primary(String label, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: onTap == null ? const Color(0xFFB8B2A6) : Palette.ink,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.paper)),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Palette.accent : Colors.white,
          border: Border.all(color: selected ? Palette.accent : const Color(0xFFE7E2D8), width: 1.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(selected ? '✓ $label' : label,
            style: TypeScale.sans(12, weight: FontWeight.w700, color: selected ? const Color(0xFFFBF9F4) : const Color(0xFF6F6A60))),
      ),
    );
  }
}
```

In `lib/ui/home_router.dart`, import the flow and add the case before the switch default:

```dart
import 'onboarding_flow.dart';
// ...
final child = switch (screen) {
  AppScreen.onboardTarget => const OnboardingFlow(),
  AppScreen.daily => DailyScreen(user: user, task: selectTask(tasks, now)!),
  // ...existing cases...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/onboarding_flow_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/onboarding_flow.dart lib/ui/home_router.dart test/ui/onboarding_flow_test.dart
git commit -m "feat(ui): onboarding wizard + routeHome wiring"
```

---

### Task 12: `AddSheet` + `EnrichSheet` bottom sheets

**Files:**
- Create: `lib/ui/add_sheet.dart`, `lib/ui/enrich_sheet.dart`
- Test: `test/ui/add_enrich_sheet_test.dart`

**Interfaces:**
- Consumes: `userProvider`, `poolControllerProvider`, chip enums + `deadlineChoiceFor`/`repeatChoiceFor` from `edits.dart`.
- Produces:
  - `Future<void> showAddSheet(BuildContext context, WidgetRef ref)` — shows AddSheet; on "Add to pool" opens EnrichSheet for the typed title.
  - `Future<void> showEnrichSheet(BuildContext context, WidgetRef ref, {String? title, Task? existing})` — shows EnrichSheet; on Save commits via `add` (new) or `edit` (existing).

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/add_enrich_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/add_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  testWidgets('add flow: type title -> enrich -> save creates a task', (tester) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true),
      tasks: const [],
    );
    late WidgetRef capturedRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return Scaffold(body: Center(
            child: ElevatedButton(
              onPressed: () => showAddSheet(context, ref),
              child: const Text('open'),
            ),
          ));
        }),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Descale kettle');
    await tester.tap(find.text('Add to pool'));
    await tester.pumpAndSettle();

    // Enrich sheet now showing; Repeat defaults to One-off; just Save.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final tasks = await repo.watchTasks().first;
    expect(tasks.map((t) => t.title), contains('Descale kettle'));
    expect(capturedRef, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/add_enrich_sheet_test.dart`
Expected: FAIL — `showAddSheet` undefined.

- [ ] **Step 3: Build the sheets**

Create `lib/ui/add_sheet.dart` (prototype `ADD SHEET`, lines 388-402) and `lib/ui/enrich_sheet.dart` (prototype `ENRICH SHEET`, lines 404-449). The add sheet collects a title; "Add to pool" closes it and opens the enrich sheet. The enrich sheet holds local `DeadlineChoice`/`RepeatChoice`/custom state (pre-seeded via the reverse maps when editing), a `showDatePicker` for "Pick a date", a custom-repeat sub-panel, and Save → `PoolController.add`/`.edit`.

```dart
// lib/ui/add_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/task.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'enrich_sheet.dart';

/// Quick-add: title only, then hand off to the enrich sheet (prototype flow).
Future<void> showAddSheet(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final title = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2DCCF), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Text('NEW CHORE', style: TypeScale.sans(9.8, weight: FontWeight.w700, letterSpacing: 1.6, color: const Color(0xFFA8A193))),
            TextField(
              controller: controller,
              autofocus: true,
              style: TypeScale.serif(25.2, weight: FontWeight.w500, color: Palette.ink),
              decoration: const InputDecoration(hintText: 'What needs doing?', border: InputBorder.none),
              onSubmitted: (v) => Navigator.of(sheetContext).pop(v.trim()),
            ),
            const SizedBox(height: 18),
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(sheetContext).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(color: const Color(0xFFF1EDE4), borderRadius: BorderRadius.circular(14)),
                  child: Text('Cancel', style: TypeScale.sans(14, weight: FontWeight.w700, color: const Color(0xFF8A847A))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(sheetContext).pop(controller.text.trim()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: Text('Add to pool', style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.paper)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
  if (title == null || title.isEmpty || !context.mounted) return;
  await showEnrichSheet(context, ref, title: title);
}

/// Re-exported for callers that only need a Task edit entry point.
Future<void> showEditSheet(BuildContext context, WidgetRef ref, Task task) =>
    showEnrichSheet(context, ref, existing: task);
```

```dart
// lib/ui/enrich_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/pool_controller.dart';
import '../app/providers.dart';
import '../domain/edits.dart';
import '../domain/task.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';

/// Deadline + repeat enrichment. [existing] => edit; otherwise add [title].
Future<void> showEnrichSheet(BuildContext context, WidgetRef ref,
    {String? title, Task? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EnrichSheet(title: title, existing: existing, ref: ref),
  );
}

class _EnrichSheet extends StatefulWidget {
  const _EnrichSheet({this.title, this.existing, required this.ref});
  final String? title;
  final Task? existing;
  final WidgetRef ref;
  @override
  State<_EnrichSheet> createState() => _EnrichSheetState();
}

class _EnrichSheetState extends State<_EnrichSheet> {
  late DeadlineChoice _deadline;
  late RepeatChoice _repeat;
  late int _customN;
  late CustomUnit _customUnit;
  DateTime? _pickedDate;

  @override
  void initState() {
    super.initState();
    final now = widget.ref.read(nowProvider)();
    final t = widget.existing;
    _deadline = t == null ? DeadlineChoice.none : deadlineChoiceFor(t.dueAt, now);
    _pickedDate = (_deadline == DeadlineChoice.pickDate) ? t!.dueAt : null;
    final r = t == null
        ? (choice: RepeatChoice.oneOff, customN: 2, customUnit: CustomUnit.weeks)
        : repeatChoiceFor(t.kind, t.intervalDays);
    _repeat = r.choice;
    _customN = r.customN;
    _customUnit = r.customUnit;
  }

  String get _title => widget.existing?.title ?? widget.title ?? '';

  Future<void> _pickDate() async {
    final now = widget.ref.read(nowProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() { _deadline = DeadlineChoice.pickDate; _pickedDate = picked; });
  }

  Future<void> _save() async {
    final user = widget.ref.read(userProvider).value;
    if (user == null) { Navigator.of(context).pop(); return; }
    final pool = widget.ref.read(poolControllerProvider);
    final existing = widget.existing;
    if (existing == null) {
      await pool.add(user,
          title: _title, deadline: _deadline, pickedDate: _pickedDate,
          repeat: _repeat, customN: _customN, customUnit: _customUnit);
    } else {
      await pool.edit(user, existing,
          title: _title, deadline: _deadline, pickedDate: _pickedDate,
          repeat: _repeat, customN: _customN, customUnit: _customUnit);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2DCCF), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(_title, style: TypeScale.serif(22.4, weight: FontWeight.w500, color: Palette.ink)),
          const SizedBox(height: 20),
          _sectionLabel('Deadline'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final entry in const [
              (DeadlineChoice.none, 'No deadline'), (DeadlineChoice.today, 'Today'),
              (DeadlineChoice.tomorrow, 'Tomorrow'), (DeadlineChoice.thisWeek, 'This week'),
              (DeadlineChoice.nextWeek, 'Next week'),
            ])
              _chip(entry.$2, _deadline == entry.$1, () => setState(() { _deadline = entry.$1; _pickedDate = null; })),
            _chip(_pickedDate == null ? '◷ Pick a date' : '◷ ${_pickedDate!.year}-${_pickedDate!.month.toString().padLeft(2, '0')}-${_pickedDate!.day.toString().padLeft(2, '0')}',
                _deadline == DeadlineChoice.pickDate, _pickDate, special: true),
          ]),
          const SizedBox(height: 18),
          _sectionLabel('Repeat'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final entry in const [
              (RepeatChoice.oneOff, 'One-off'), (RepeatChoice.every3, 'Every 3 days'),
              (RepeatChoice.weekly, 'Weekly'), (RepeatChoice.fortnightly, 'Fortnightly'),
              (RepeatChoice.monthly, 'Monthly'),
            ])
              _chip(entry.$2, _repeat == entry.$1, () => setState(() => _repeat = entry.$1)),
            _chip('⊕ Custom', _repeat == RepeatChoice.custom, () => setState(() => _repeat = RepeatChoice.custom), special: true),
          ]),
          if (_repeat == RepeatChoice.custom) _customPanel(),
          const SizedBox(height: 22),
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFF1EDE4), borderRadius: BorderRadius.circular(14)),
                child: Text('Back', style: TypeScale.sans(14, weight: FontWeight.w700, color: const Color(0xFF8A847A))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: Text('Save', style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.paper)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _customPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F1),
        border: Border.all(color: const Color(0xFFB7CDB4), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CUSTOM REPEAT', style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 0.6, color: Palette.accent)),
        const SizedBox(height: 12),
        Row(children: [
          Text('Every', style: TypeScale.sans(11.1, weight: FontWeight.w700, color: const Color(0xFFA8A193))),
          const SizedBox(width: 12),
          GestureDetector(
            key: const ValueKey('custom-dec'),
            onTap: () => setState(() => _customN = (_customN - 1).clamp(1, 99)),
            child: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(width: 46, child: Text('$_customN', textAlign: TextAlign.center, style: TypeScale.serif(25.2, weight: FontWeight.w600, color: Palette.ink))),
          GestureDetector(
            key: const ValueKey('custom-inc'),
            onTap: () => setState(() => _customN = (_customN + 1).clamp(1, 99)),
            child: const Icon(Icons.add_circle_outline),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final u in CustomUnit.values)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _customUnit = u),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _customUnit == u ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(_unitLabel(u), style: TypeScale.sans(12.5, weight: FontWeight.w700, color: _customUnit == u ? Palette.ink : const Color(0xFF8A847A))),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  String _unitLabel(CustomUnit u) => switch (u) {
        CustomUnit.days => 'Days',
        CustomUnit.weeks => 'Weeks',
        CustomUnit.months => 'Months',
      };

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(s, style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 0.4, color: const Color(0xFFA8A193))),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap, {bool special = false}) {
    final bg = selected ? (special ? Palette.accent : Palette.ink) : (special ? const Color(0xFFF3F6F1) : Colors.white);
    final fg = selected ? (special ? const Color(0xFFFBF9F4) : Palette.paper) : (special ? Palette.accent : const Color(0xFF6F6A60));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: selected ? bg : const Color(0xFFE7E2D8), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TypeScale.sans(12.5, weight: FontWeight.w700, color: fg)),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/add_enrich_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/add_sheet.dart lib/ui/enrich_sheet.dart test/ui/add_enrich_sheet_test.dart
git commit -m "feat(ui): add + enrich bottom sheets"
```

---

### Task 13: `ManageScreen`

**Files:**
- Create: `lib/ui/manage_screen.dart`
- Test: `test/ui/manage_screen_test.dart`

**Interfaces:**
- Consumes: `userProvider`, `tasksProvider`, `nowProvider`, `poolControllerProvider`, `manageMeta`, `urgencyOf`, `showAddSheet`/`showEditSheet`, `SettingsScreen` (Task 14 — import added then).
- Produces: `class ManageScreen extends ConsumerWidget`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/manage_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/manage_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  Future<InMemoryRepository> pump(WidgetTester tester) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true),
      tasks: [Task(id: 't1', title: 'Water plants', kind: TaskKind.recurring, intervalDays: 7, dueAt: now, createdAt: now)],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: ManageScreen()),
    ));
    await tester.pump();
    return repo;
  }

  testWidgets('lists tasks with cadence meta', (tester) async {
    await pump(tester);
    expect(find.text('Water plants'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
  });

  testWidgets('delete asks to confirm then removes', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('delete-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this chore?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final tasks = await repo.watchTasks().first;
    expect(tasks.where((t) => t.id == 't1'), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/manage_screen_test.dart`
Expected: FAIL — `ManageScreen` undefined.

- [ ] **Step 3: Build `ManageScreen`**

Create `lib/ui/manage_screen.dart` (prototype `MANAGE`, lines 248-297). Tapping a row opens the edit sheet; the trash icon opens a confirm dialog then calls `PoolController.remove`; the FAB opens the add sheet; the gear pushes `SettingsScreen`.

```dart
// lib/ui/manage_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/pool_controller.dart';
import '../app/providers.dart';
import '../domain/task.dart';
import '../domain/urgency.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'add_sheet.dart';
import 'settings_screen.dart';

class ManageScreen extends ConsumerWidget {
  const ManageScreen({super.key});

  Color _dot(double u) => u > 0.7 ? Palette.terracotta : (u > 0.4 ? const Color(0xFFCDB16A) : const Color(0xFFA9BF9C));

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Task task) async {
    final user = ref.read(userProvider).value;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete this chore?', style: TypeScale.serif(19.9, weight: FontWeight.w500, color: Palette.ink)),
        content: Text('“${task.title}” will be gone for good. This can’t be undone.',
            style: TypeScale.sans(14, height: 1.5, color: Palette.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.terracotta)),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(poolControllerProvider).remove(user, task);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final now = ref.watch(nowProvider)();
    final pool = [...tasks]..sort((a, b) => urgencyOf(b, now).compareTo(urgencyOf(a, now)));

    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ChromeButton(child: const Icon(Icons.chevron_left, color: Color(0xFF6F6A60)), onTap: () => Navigator.of(context).pop()),
                  Text('Your pool', style: TypeScale.serif(15.8, weight: FontWeight.w600, color: Palette.ink)),
                  _ChromeButton(
                    child: const Icon(Icons.settings_outlined, size: 19, color: Color(0xFF8A847A)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                itemCount: pool.length,
                itemBuilder: (context, i) {
                  final t = pool[i];
                  return GestureDetector(
                    onTap: () => showEditSheet(context, ref, t),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: _dot(urgencyOf(t, now)))),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.title, style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
                            const SizedBox(height: 5),
                            Text(manageMeta(t, now), style: TypeScale.sans(11.1, weight: FontWeight.w600, color: const Color(0xFFA8A193))),
                          ]),
                        ),
                        GestureDetector(
                          key: ValueKey('delete-${t.id}'),
                          onTap: () => _confirmDelete(context, ref, t),
                          child: const Icon(Icons.delete_outline, size: 18, color: Palette.terracotta),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: GestureDetector(
        onTap: () => showAddSheet(context, ref),
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(19)),
          child: const Icon(Icons.add, color: Palette.paper),
        ),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)), child: child),
      );
}
```

(Note: this imports `settings_screen.dart` from Task 14. Implement Task 14 in the same working session before running the full suite; the focused manage test does not tap the gear, so it compiles only once `SettingsScreen` exists — keep Task 13 and 14 in one branch/PR.)

- [ ] **Step 4: Run test to verify it passes (after Task 14 exists)**

Run: `flutter test test/ui/manage_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/manage_screen.dart test/ui/manage_screen_test.dart
git commit -m "feat(ui): manage pool screen"
```

---

### Task 14: `SettingsScreen`

**Files:**
- Create: `lib/ui/settings_screen.dart`
- Test: `test/ui/settings_screen_test.dart`

**Interfaces:**
- Consumes: `userProvider`, `settingsControllerProvider`, `authServiceProvider`, `TargetStepper`.
- Produces: `class SettingsScreen extends ConsumerStatefulWidget`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  Future<InMemoryRepository> pump(WidgetTester tester) async {
    final repo = InMemoryRepository(
      user: UserState(
        timezone: 'UTC', target: 3, lastActiveDate: now, onboardingComplete: true,
        remindersWeekday: const ['08:00', '18:30'], remindersWeekend: const ['10:00'],
      ),
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    return repo;
  }

  testWidgets('bumping the target writes it', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('target-inc')));
    await tester.pump();
    expect((await repo.watchUser().first).target, 4);
  });

  testWidgets('removing a weekday reminder writes the shorter array', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remove-reminder-0')));
    await tester.pump();
    expect((await repo.watchUser().first).remindersWeekday, const ['18:30']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings_screen_test.dart`
Expected: FAIL — `SettingsScreen` undefined.

- [ ] **Step 3: Build `SettingsScreen`**

Create `lib/ui/settings_screen.dart` (prototype `SETTINGS`, lines 299-348). Daily-target stepper writes via `SettingsController.setTarget`; weekday/weekend tabs choose which array is edited; each reminder row has a time picker (tap → `showTimePicker` → replace) and a remove button; "Add a reminder" appends (disabled at 3); reminders write via `setReminders`; "Sign out" calls `AuthService.signOut()`.

```dart
// lib/ui/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/settings_controller.dart';
import '../auth/auth_providers.dart';
import '../domain/user_state.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'widgets/target_stepper.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _weekend = false;

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  List<String> _activeList(UserState u) => _weekend ? u.remindersWeekend : u.remindersWeekday;

  Future<void> _writeReminders(UserState u, List<String> next) {
    final ctrl = ref.read(settingsControllerProvider);
    return _weekend
        ? ctrl.setReminders(u, weekday: u.remindersWeekday, weekend: next)
        : ctrl.setReminders(u, weekday: next, weekend: u.remindersWeekend);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider).value;
    if (user == null) return const Scaffold(backgroundColor: Palette.paper, body: SizedBox.expand());
    final list = _activeList(user);

    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                GestureDetector(onTap: () => Navigator.of(context).pop(), child: const SizedBox(width: 40, child: Icon(Icons.chevron_left, color: Color(0xFF6F6A60)))),
                Text('Reminders', style: TypeScale.serif(15.8, weight: FontWeight.w600, color: Palette.ink)),
                const SizedBox(width: 40),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                children: [
                  _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Daily target', style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
                      const SizedBox(height: 5),
                      Text('Tasks before today counts as a win', style: TypeScale.sans(11.1, color: const Color(0xFFA8A193))),
                    ]),
                    TargetStepper(value: user.target, numeralSize: 28.4, onChanged: (n) => ref.read(settingsControllerProvider).setTarget(user, n)),
                  ])),
                  const SizedBox(height: 18),
                  _tabs(),
                  const SizedBox(height: 12),
                  for (var i = 0; i < list.length; i++)
                    _reminderRow(user, list, i),
                  if (list.length < 3) _addRow(user, list),
                  const SizedBox(height: 22),
                  _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Signed in · sync on', style: TypeScale.sans(14, weight: FontWeight.w600, color: const Color(0xFF6F6A60))),
                    GestureDetector(
                      onTap: () => ref.read(authServiceProvider).signOut(),
                      child: Text('Sign out', style: TypeScale.sans(12.4, weight: FontWeight.w700, color: Palette.terracotta)),
                    ),
                  ])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(label, style: TypeScale.sans(12.4, weight: FontWeight.w700, color: active ? Palette.ink : const Color(0xFFA8A193))),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE9E5DC), borderRadius: BorderRadius.circular(13)),
      child: Row(children: [
        tab('Weekdays', !_weekend, () => setState(() => _weekend = false)),
        tab('Weekends', _weekend, () => setState(() => _weekend = true)),
      ]),
    );
  }

  Widget _reminderRow(UserState user, List<String> list, int i) {
    return _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      GestureDetector(
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: _parse(list[i]));
          if (picked != null) {
            final next = [...list]..[i] = _fmt(picked);
            await _writeReminders(user, next);
          }
        },
        child: Text(list[i], style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
      ),
      GestureDetector(
        key: ValueKey('remove-reminder-$i'),
        onTap: () => _writeReminders(user, [...list]..removeAt(i)),
        child: const Icon(Icons.close, size: 18, color: Palette.terracotta),
      ),
    ]));
  }

  Widget _addRow(UserState user, List<String> list) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
        if (picked != null) await _writeReminders(user, [...list, _fmt(picked)]);
      },
      child: _card(Row(children: [
        const Icon(Icons.add, size: 18, color: Color(0xFF8A847A)),
        const SizedBox(width: 8),
        Text('Add a reminder', style: TypeScale.sans(14, weight: FontWeight.w600, color: const Color(0xFF6F6A60))),
      ])),
    );
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings_screen.dart test/ui/settings_screen_test.dart
git commit -m "feat(ui): settings screen — target + reminders (D17)"
```

---

### Task 15: Wire navigation into the daily-loop screens

**Files:**
- Modify: `lib/ui/home_router.dart`, `lib/ui/daily_screen.dart`, `lib/ui/cleared_screen.dart`, `lib/ui/empty_pool_screen.dart`
- Test: `test/ui/daily_screen_test.dart` (extend), `test/ui/home_router_test.dart` (extend)

**Interfaces:**
- Consumes: `ManageScreen`, `showAddSheet`.
- Produces: daily menu → push `ManageScreen`; daily/manage/emptyPool FAB → `showAddSheet`; cleared "Review pool" → push `ManageScreen`. Stats still uses `PlaceholderScreen`.

- [ ] **Step 1: Write the failing test**

Extend `test/ui/daily_screen_test.dart` with a navigation test (mirror its existing harness; it overrides `repositoryProvider`/`nowProvider` and pumps `DailyScreen` inside a `MaterialApp`):

```dart
  testWidgets('menu button opens the manage screen', (tester) async {
    // ...use the file's existing pump harness with an onboarded user + due task...
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Your pool'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/daily_screen_test.dart`
Expected: FAIL — menu still opens `PlaceholderScreen` ("Manage — coming soon").

- [ ] **Step 3: Replace the placeholder pushes**

In `lib/ui/daily_screen.dart`: replace the `_open(context, 'Manage')` chrome button with a push to `ManageScreen`, and the FAB's `_open(context, 'Add')` with `showAddSheet(context, ref)` (the widget is a `ConsumerWidget`, so pass its `ref`). Keep `_open(context, 'Stats')` as the `PlaceholderScreen` push. Remove the now-unused `_open`/`PlaceholderScreen` import if Manage/Add no longer use it (Stats still does — keep the import).

In `lib/ui/home_router.dart`: change `ClearedScreen(onReviewPool: ...)` and `EmptyPoolScreen(onAdd: ...)` to push `ManageScreen` / call `showAddSheet`. Because `showAddSheet` needs a `WidgetRef`, pass `ref` from `HomeRouter.build` into the callbacks.

Concretely in `home_router.dart`:

```dart
AppScreen.cleared => ClearedScreen(
    onReviewPool: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageScreen()))),
AppScreen.emptyPool => EmptyPoolScreen(onAdd: () => showAddSheet(context, ref)),
```

with `import 'manage_screen.dart';` and `import 'add_sheet.dart';` added, and the `_open`/`PlaceholderScreen` helper removed from `home_router.dart` if no longer referenced there.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/daily_screen_test.dart test/ui/home_router_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/daily_screen.dart lib/ui/home_router.dart lib/ui/cleared_screen.dart lib/ui/empty_pool_screen.dart test/ui/daily_screen_test.dart test/ui/home_router_test.dart
git commit -m "feat(ui): wire daily-loop screens to manage + add"
```

---

### Task 16: Full-suite green + docs

**Files:**
- Modify: `docs/IMPLEMENTATION-ROADMAP.md`, `CLAUDE.md`

**Interfaces:** none (integration + documentation).

- [ ] **Step 1: Run the entire suite**

Run: `flutter test`
Expected: PASS — all suites green. Fix any regressions (most likely a lingering `SignInScreen`/placeholder reference; grep `rg -n "SignInScreen|coming soon" lib test`).

- [ ] **Step 2: Run the analyzer**

Run: `flutter analyze`
Expected: No issues. Fix unused imports (e.g. dropped `PlaceholderScreen`/`google_sign_in` imports).

- [ ] **Step 3: Update the roadmap status**

In `docs/IMPLEMENTATION-ROADMAP.md`, set the Phase 4 row Status to `**✅ Complete**` with the final green test count, and add a "Decisions captured during Phase-4" subsection noting: single `saveTask` builder (add+edit unified), `newTaskId()` as the only seam addition, This/Next-week = +7/+14, reminders fully editable (D17), welcome screen + `AuthService` cancel handling landed.

- [ ] **Step 4: Record any hard-won learnings in `CLAUDE.md`**

Add a learning only if something took multiple attempts (e.g. bottom-sheet tests needing `pumpAndSettle`, or routing-test breakage from the `onboardingComplete` default). Keep it to the format already in the file.

- [ ] **Step 5: Commit**

```bash
git add docs/IMPLEMENTATION-ROADMAP.md CLAUDE.md
git commit -m "docs: mark Phase 4 complete; record decisions + learnings"
```

---

## Self-Review

**1. Spec coverage:**
- Scope boundary with Phase 6 (no FCM/permission) → honoured; settings only writes reminders (Tasks 8, 14). ✓
- A1 onboarding gate → Task 4. ✓ A2/A3 navigation (pushes + sheets) → Tasks 11–15. ✓
- B1/B2 forward+reverse maps → Task 1. B3 interaction (undated baseline, no force) → covered by `buildTask`/urgency (Tasks 2). B4 builders → Task 3. B5 `manageMeta` → Task 2. B6 assembly → Task 2. ✓
- C `newTaskId` → Task 5. ✓
- D controllers → Tasks 6–8. ✓
- E screens (welcome, onboarding, add/enrich, manage, settings, shared TargetStepper) → Tasks 9–14. ✓
- F carry-overs (cancel handling behind AuthService, signOut guard, drop `(D18)` comment) → Task 10. ✓
- G error handling (optimistic, trim, clamps, confirm dialog) → woven through Tasks 6–14. ✓
- H testing → every task is TDD; full suite in Task 16. ✓
- I out-of-scope (stats placeholder kept, Apple/email disabled, no partial-resume) → Tasks 10, 15. ✓

**2. Placeholder scan:** No "TBD"/"similar to"/"add error handling" — every code step shows real code. UI styling steps reference exact prototype line ranges and use real `Palette`/`TypeScale` tokens. ✓

**3. Type consistency:** `saveTask` (not `addTask`/`editTask`) used consistently across Tasks 3, 7; `DeadlineChoice`/`RepeatChoice`/`CustomUnit` identical across Tasks 1, 2, 7, 12; `newTaskId()` identical across Tasks 5, 6, 7; controller constructor shapes match their providers; `showAddSheet`/`showEditSheet`/`showEnrichSheet` signatures consistent across Tasks 12, 13, 15. ✓

**Note on task ordering:** Tasks 13 and 14 are mutually referenced (ManageScreen imports SettingsScreen) — implement both before running the full suite; commit 13 then 14 in the same branch.
