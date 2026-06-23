# Phase 1 — Domain Core + Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart domain core (models, urgency, selection, routing, transitions) and design system (palette, type scale, theme) for Just One, fully test-first, with no Firebase or UI.

**Architecture:** Immutable value classes plus free functions in `lib/domain/`; pure presentation constants and a `ThemeData` in `lib/theme/`. Every function takes `now` explicitly (no ambient clock) so it's deterministic and unit-testable. Firestore (de)serialization, repositories, widgets, and gestures are out of scope (later phases).

**Tech Stack:** Dart / Flutter, `flutter_test`, `google_fonts`. No Firebase imports in this phase.

Spec: `docs/superpowers/specs/2026-06-23-phase-1-domain-core-design.md`. Roadmap: `docs/IMPLEMENTATION-ROADMAP.md`.

## Global Constraints

- **No Firebase imports** anywhere under `lib/domain/` or `lib/theme/`.
- **Keep every file well under 1,000 lines** (project rule); these are all small.
- `now` is always a parameter — never call `DateTime.now()` inside domain functions.
- **Colour tokens (exact):** paper `#f3f1ec`, ink `#2b2824`, mutedStrong `#5c574e`, muted `#8f8a80`, accent `#5f8c63`, terracotta `#c2683f`, icon-cream `#efeae0`. Halo endpoints: calm `rgb(95,140,99)`, urgent `rgb(196,104,63)`.
- **Type families:** `Newsreader` (serif — display/headings/titles/numerals), `Nunito Sans` (UI/body/labels). Major-second scale, ratio 1.125, base 14px.
- **Urgency constants (tunable, single source):** floor `0.04`, span `0.94`, steepness `2`, one-off horizon `7` days, undated-one-off baseline `0.35`. "Due" / "cleared" threshold: `urg > 0.04`.
- **Defaults:** `target` 3, `rerolls` 3.
- Run all tests with `flutter test`. A single file: `flutter test test/<path>`.

---

### Task 1: Task model + enums

**Files:**
- Create: `lib/domain/task.dart`
- Test: `test/domain/task_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum TaskKind { oneOff, recurring }`; `enum TaskStatus { active, benched, archived, removed }`; `class Task` with named-required constructor (fields: `String id`, `String title`, `TaskKind kind`, `int? intervalDays`, `DateTime? dueAt`, `DateTime createdAt`, `DateTime? completedAt`, `TaskStatus status` default `active`), `Task copyWith({...})`, value `==`/`hashCode`. Constructor asserts recurring⇒`intervalDays>0`, oneOff⇒`intervalDays==null`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/task_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';

void main() {
  final base = Task(
    id: 't1',
    title: 'Water plants',
    kind: TaskKind.recurring,
    intervalDays: 3,
    dueAt: DateTime(2026, 6, 23),
    createdAt: DateTime(2026, 6, 20),
  );

  test('defaults status to active', () {
    expect(base.status, TaskStatus.active);
  });

  test('copyWith changes only named fields and keeps value equality', () {
    final benched = base.copyWith(status: TaskStatus.benched);
    expect(benched.status, TaskStatus.benched);
    expect(benched.title, 'Water plants');
    expect(benched, base.copyWith(status: TaskStatus.benched));
    expect(benched == base, isFalse);
  });

  test('recurring task requires a positive intervalDays', () {
    expect(
      () => Task(
        id: 'x', title: 'bad', kind: TaskKind.recurring,
        createdAt: DateTime(2026, 6, 20),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('one-off task must not have intervalDays', () {
    expect(
      () => Task(
        id: 'x', title: 'bad', kind: TaskKind.oneOff, intervalDays: 5,
        createdAt: DateTime(2026, 6, 20),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/task_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:justone/domain/task.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/task.dart
enum TaskKind { oneOff, recurring }

enum TaskStatus { active, benched, archived, removed }

class Task {
  final String id;
  final String title;
  final TaskKind kind;
  final int? intervalDays;
  final DateTime? dueAt;
  final DateTime createdAt;
  final DateTime? completedAt;
  final TaskStatus status;

  Task({
    required this.id,
    required this.title,
    required this.kind,
    this.intervalDays,
    this.dueAt,
    required this.createdAt,
    this.completedAt,
    this.status = TaskStatus.active,
  })  : assert(
          kind != TaskKind.recurring ||
              (intervalDays != null && intervalDays > 0),
          'recurring tasks need a positive intervalDays',
        ),
        assert(
          kind != TaskKind.oneOff || intervalDays == null,
          'one-off tasks must not have intervalDays',
        );

  Task copyWith({
    String? id,
    String? title,
    TaskKind? kind,
    int? intervalDays,
    DateTime? dueAt,
    DateTime? createdAt,
    DateTime? completedAt,
    TaskStatus? status,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      intervalDays: intervalDays ?? this.intervalDays,
      dueAt: dueAt ?? this.dueAt,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      other.intervalDays == intervalDays &&
      other.dueAt == dueAt &&
      other.createdAt == createdAt &&
      other.completedAt == completedAt &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
        id, title, kind, intervalDays, dueAt, createdAt, completedAt, status,
      );
}
```

> Note: `copyWith` cannot set a nullable field back to `null` (the `?? this` idiom). Phase 1 never needs to clear `dueAt`/`completedAt`, so this is fine.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/task_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/task.dart test/domain/task_test.dart
git commit -m "feat(domain): add Task model with kind/status enums and invariants"
```

---

### Task 2: UserState model

**Files:**
- Create: `lib/domain/user_state.dart`
- Test: `test/domain/user_state_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class UserState` (flat fields, grouped by comment). Config: `String timezone`, `int target` (default 3), `List<String> remindersWeekday` (default `const []`), `List<String> remindersWeekend` (default `const []`), `bool onboardingComplete` (default false). Progress: `int streak`, `bestStreak`, `targetMetDays`, `lifetimeDone` (default 0). Today: `bool bankedToday`, `bool targetDismissed`, `int doneToday`, `int rerolls` (default 3), `DateTime lastActiveDate` (required). `UserState copyWith({...})` for every field; value `==`/`hashCode`.

> Design note: flat (not nested) — the spec's Config/Progress/Today grouping is rendered as comment sections, which keeps `copyWith` single-level. Phase 3 maps this flat shape to the single Firestore user doc.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/user_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  final base = UserState(
    timezone: 'Europe/London',
    lastActiveDate: DateTime(2026, 6, 23),
  );

  test('applies documented defaults', () {
    expect(base.target, 3);
    expect(base.rerolls, 3);
    expect(base.streak, 0);
    expect(base.onboardingComplete, isFalse);
    expect(base.remindersWeekday, isEmpty);
  });

  test('copyWith updates only named fields with value equality', () {
    final next = base.copyWith(streak: 2, bankedToday: true);
    expect(next.streak, 2);
    expect(next.bankedToday, isTrue);
    expect(next.timezone, 'Europe/London');
    expect(next, base.copyWith(streak: 2, bankedToday: true));
    expect(next == base, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/user_state_test.dart`
Expected: FAIL — URI for `user_state.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/user_state.dart
class UserState {
  // --- config ---
  final String timezone;
  final int target;
  final List<String> remindersWeekday;
  final List<String> remindersWeekend;
  final bool onboardingComplete;

  // --- progress ---
  final int streak;
  final int bestStreak;
  final int targetMetDays;
  final int lifetimeDone;

  // --- today (reset client-side per D7) ---
  final bool bankedToday;
  final bool targetDismissed;
  final int doneToday;
  final int rerolls;
  final DateTime lastActiveDate;

  const UserState({
    required this.timezone,
    this.target = 3,
    this.remindersWeekday = const [],
    this.remindersWeekend = const [],
    this.onboardingComplete = false,
    this.streak = 0,
    this.bestStreak = 0,
    this.targetMetDays = 0,
    this.lifetimeDone = 0,
    this.bankedToday = false,
    this.targetDismissed = false,
    this.doneToday = 0,
    this.rerolls = 3,
    required this.lastActiveDate,
  });

  UserState copyWith({
    String? timezone,
    int? target,
    List<String>? remindersWeekday,
    List<String>? remindersWeekend,
    bool? onboardingComplete,
    int? streak,
    int? bestStreak,
    int? targetMetDays,
    int? lifetimeDone,
    bool? bankedToday,
    bool? targetDismissed,
    int? doneToday,
    int? rerolls,
    DateTime? lastActiveDate,
  }) {
    return UserState(
      timezone: timezone ?? this.timezone,
      target: target ?? this.target,
      remindersWeekday: remindersWeekday ?? this.remindersWeekday,
      remindersWeekend: remindersWeekend ?? this.remindersWeekend,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      streak: streak ?? this.streak,
      bestStreak: bestStreak ?? this.bestStreak,
      targetMetDays: targetMetDays ?? this.targetMetDays,
      lifetimeDone: lifetimeDone ?? this.lifetimeDone,
      bankedToday: bankedToday ?? this.bankedToday,
      targetDismissed: targetDismissed ?? this.targetDismissed,
      doneToday: doneToday ?? this.doneToday,
      rerolls: rerolls ?? this.rerolls,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    );
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is UserState &&
      other.timezone == timezone &&
      other.target == target &&
      _listEq(other.remindersWeekday, remindersWeekday) &&
      _listEq(other.remindersWeekend, remindersWeekend) &&
      other.onboardingComplete == onboardingComplete &&
      other.streak == streak &&
      other.bestStreak == bestStreak &&
      other.targetMetDays == targetMetDays &&
      other.lifetimeDone == lifetimeDone &&
      other.bankedToday == bankedToday &&
      other.targetDismissed == targetDismissed &&
      other.doneToday == doneToday &&
      other.rerolls == rerolls &&
      other.lastActiveDate == lastActiveDate;

  @override
  int get hashCode => Object.hash(
        timezone,
        target,
        Object.hashAll(remindersWeekday),
        Object.hashAll(remindersWeekend),
        onboardingComplete,
        streak,
        bestStreak,
        targetMetDays,
        lifetimeDone,
        bankedToday,
        targetDismissed,
        doneToday,
        rerolls,
        lastActiveDate,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/user_state_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/user_state.dart test/domain/user_state_test.dart
git commit -m "feat(domain): add UserState model with defaults and copyWith"
```

---

### Task 3: Date helper + urgency curve

**Files:**
- Create: `lib/domain/urgency.dart`
- Test: `test/domain/urgency_test.dart`

**Interfaces:**
- Consumes: `Task`, `TaskKind` from `task.dart`.
- Produces: `int daysBetweenLocalDates(DateTime a, DateTime b)` (calendar-day difference, DST-safe; `b − a`, so future is positive); `double urgencyOf(Task task, DateTime now)` returning `[0,1]`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/urgency_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/urgency.dart';

Task recurring({required int interval, required DateTime dueAt}) => Task(
      id: 'r', title: 'r', kind: TaskKind.recurring,
      intervalDays: interval, dueAt: dueAt, createdAt: DateTime(2026, 1, 1),
    );

void main() {
  final now = DateTime(2026, 6, 23, 12);

  test('daysBetweenLocalDates counts calendar days, DST-safe', () {
    expect(daysBetweenLocalDates(DateTime(2026, 6, 23), DateTime(2026, 6, 24)), 1);
    expect(daysBetweenLocalDates(DateTime(2026, 6, 24), DateTime(2026, 6, 23)), -1);
    // across a UK spring-forward boundary (29 Mar 2026) still exactly 1 day
    expect(daysBetweenLocalDates(DateTime(2026, 3, 28), DateTime(2026, 3, 29)), 1);
  });

  test('due today is ~0.51', () {
    final u = urgencyOf(recurring(interval: 7, dueAt: now), now);
    expect(u, closeTo(0.51, 0.02));
  });

  test('one full cycle overdue is ~0.87', () {
    final due = now.subtract(const Duration(days: 7));
    final u = urgencyOf(recurring(interval: 7, dueAt: due), now);
    expect(u, closeTo(0.87, 0.02));
  });

  test('far from due falls to the 0.04 floor (not due)', () {
    final due = now.add(const Duration(days: 21)); // r = -3 for interval 7
    final u = urgencyOf(recurring(interval: 7, dueAt: due), now);
    expect(u, closeTo(0.04, 0.01));
    expect(u, lessThanOrEqualTo(0.04 + 0.005));
  });

  test('undated one-off returns the constant low-band baseline', () {
    final t = Task(
      id: 'o', title: 'fix shelf', kind: TaskKind.oneOff,
      createdAt: DateTime(2026, 1, 1),
    );
    expect(urgencyOf(t, now), 0.35);
  });

  test('one-off with a deadline uses the 7-day horizon', () {
    final t = Task(
      id: 'o2', title: 'cancel sub', kind: TaskKind.oneOff,
      dueAt: now, createdAt: DateTime(2026, 1, 1),
    );
    expect(urgencyOf(t, now), closeTo(0.51, 0.02)); // due today, r=0
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/urgency_test.dart`
Expected: FAIL — URI for `urgency.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/urgency.dart
import 'dart:math' as math;

import 'task.dart';

// Tunable urgency constants (single source — see plan Global Constraints).
const double _floor = 0.04;
const double _span = 0.94;
const double _steepness = 2.0;
const int _oneOffHorizonDays = 7;
const double _undatedBaseline = 0.35;

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/urgency_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/urgency.dart test/domain/urgency_test.dart
git commit -m "feat(domain): add urgency sigmoid and DST-safe day helper"
```

---

### Task 4: meta label derivation

**Files:**
- Modify: `lib/domain/urgency.dart` (add `metaOf`)
- Test: `test/domain/meta_test.dart`

**Interfaces:**
- Consumes: `Task`, `daysBetweenLocalDates`.
- Produces: `String metaOf(Task task, DateTime now)` — the daily-card label.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/meta_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/urgency.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);

  Task recurringDue(DateTime dueAt, {DateTime? completedAt}) => Task(
        id: 'r', title: 'r', kind: TaskKind.recurring, intervalDays: 7,
        dueAt: dueAt, completedAt: completedAt, createdAt: DateTime(2026, 1, 1),
      );

  test('completed today shows "done today"', () {
    final t = recurringDue(now.add(const Duration(days: 7)),
        completedAt: DateTime(2026, 6, 23, 9));
    expect(metaOf(t, now), 'done today');
  });

  test('overdue labels', () {
    expect(metaOf(recurringDue(DateTime(2026, 6, 21)), now), '2 days overdue');
    expect(metaOf(recurringDue(DateTime(2026, 6, 22)), now), '1 day overdue');
  });

  test('upcoming labels', () {
    expect(metaOf(recurringDue(DateTime(2026, 6, 23, 20)), now), 'due today');
    expect(metaOf(recurringDue(DateTime(2026, 6, 24)), now), 'due tomorrow');
    expect(metaOf(recurringDue(DateTime(2026, 6, 26)), now), 'due in 3 days');
  });

  test('undated one-off shows "no deadline"', () {
    final t = Task(
      id: 'o', title: 'x', kind: TaskKind.oneOff,
      createdAt: DateTime(2026, 1, 1),
    );
    expect(metaOf(t, now), 'no deadline');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/meta_test.dart`
Expected: FAIL — `metaOf` is not defined.

- [ ] **Step 3: Write minimal implementation** (append to `lib/domain/urgency.dart`)

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/meta_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/urgency.dart test/domain/meta_test.dart
git commit -m "feat(domain): derive daily-card meta label from task inputs"
```

---

### Task 5: selection engine

**Files:**
- Create: `lib/domain/selection.dart`
- Test: `test/domain/selection_test.dart`

**Interfaces:**
- Consumes: `Task`, `TaskStatus`, `urgencyOf`.
- Produces: `bool isDue(Task task, DateTime now)` (`urgencyOf > 0.04`); `Task? selectTask(Iterable<Task> tasks, DateTime now)` (highest-urgency `active` task; ties → earlier `dueAt` (nulls last) → earlier `createdAt`; `null` if none active).

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/selection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/selection.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);

  Task r(String id, {required int overdueDays, TaskStatus status = TaskStatus.active}) =>
      Task(
        id: id, title: id, kind: TaskKind.recurring, intervalDays: 7,
        dueAt: now.subtract(Duration(days: overdueDays)),
        createdAt: DateTime(2026, 1, 1), status: status,
      );

  test('returns null when no active tasks', () {
    expect(selectTask([r('a', overdueDays: 3, status: TaskStatus.benched)], now), isNull);
  });

  test('picks the highest-urgency active task', () {
    final picked = selectTask([
      r('low', overdueDays: -2),
      r('high', overdueDays: 5),
      r('mid', overdueDays: 1),
    ], now);
    expect(picked!.id, 'high');
  });

  test('ignores benched/archived/removed', () {
    final picked = selectTask([
      r('benched', overdueDays: 10, status: TaskStatus.benched),
      r('active', overdueDays: 2),
    ], now);
    expect(picked!.id, 'active');
  });

  test('isDue tracks the 0.04 threshold', () {
    expect(isDue(r('due', overdueDays: 0), now), isTrue);
    expect(isDue(r('faroff', overdueDays: -21), now), isFalse); // r=-3 -> ~0.04
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/selection_test.dart`
Expected: FAIL — URI for `selection.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/selection.dart
import 'task.dart';
import 'urgency.dart';

bool isDue(Task task, DateTime now) => urgencyOf(task, now) > 0.04;

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/selection_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/selection.dart test/domain/selection_test.dart
git commit -m "feat(domain): add task selection engine and isDue"
```

---

### Task 6: screen routing

**Files:**
- Create: `lib/domain/routing.dart`
- Test: `test/domain/routing_test.dart`

**Interfaces:**
- Consumes: `Task`, `TaskStatus`, `UserState`, `selectTask`, `isDue`.
- Produces: `enum AppScreen { welcome, onboardTarget, onboardAdd, daily, cleared, emptyPool, targetHit, add, manage, settings, stats }`; `AppScreen routeHome(UserState state, List<Task> tasks, DateTime now)` for a signed-in, onboarded user (HANDOFF §4).

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/routing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/routing.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);
  final user = UserState(timezone: 'UTC', lastActiveDate: now);

  Task due(String id) => Task(
        id: id, title: id, kind: TaskKind.recurring, intervalDays: 7,
        dueAt: now, createdAt: DateTime(2026, 1, 1),
      );
  Task notDue(String id) => Task(
        id: id, title: id, kind: TaskKind.recurring, intervalDays: 7,
        dueAt: now.add(const Duration(days: 21)), createdAt: DateTime(2026, 1, 1),
      );

  test('no tasks -> emptyPool', () {
    expect(routeHome(user, const [], now), AppScreen.emptyPool);
  });

  test('archived-only pool still counts as empty', () {
    final archived = due('a').copyWith(status: TaskStatus.archived);
    expect(routeHome(user, [archived], now), AppScreen.emptyPool);
  });

  test('target met and not dismissed -> targetHit', () {
    final hit = user.copyWith(target: 1, doneToday: 1);
    expect(routeHome(hit, [due('a')], now), AppScreen.targetHit);
  });

  test('target met but dismissed falls through to daily', () {
    final hit = user.copyWith(target: 1, doneToday: 1, targetDismissed: true);
    expect(routeHome(hit, [due('a')], now), AppScreen.daily);
  });

  test('tasks present but none due -> cleared', () {
    expect(routeHome(user, [notDue('a')], now), AppScreen.cleared);
  });

  test('a due task -> daily', () {
    expect(routeHome(user, [due('a')], now), AppScreen.daily);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/routing_test.dart`
Expected: FAIL — URI for `routing.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/routing.dart
import 'selection.dart';
import 'task.dart';
import 'user_state.dart';

enum AppScreen {
  welcome,
  onboardTarget,
  onboardAdd,
  daily,
  cleared,
  emptyPool,
  targetHit,
  add,
  manage,
  settings,
  stats,
}

/// Home-loop routing for a signed-in, onboarded user (HANDOFF §4).
/// Auth/onboarding gating (welcome, onboard*) is layered on in later phases.
AppScreen routeHome(UserState state, List<Task> tasks, DateTime now) {
  final poolEmpty = !tasks.any((t) =>
      t.status == TaskStatus.active || t.status == TaskStatus.benched);
  if (poolEmpty) return AppScreen.emptyPool;

  if (state.doneToday >= state.target && !state.targetDismissed) {
    return AppScreen.targetHit;
  }

  final selected = selectTask(tasks, now);
  if (selected == null || !isDue(selected, now)) return AppScreen.cleared;

  return AppScreen.daily;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/routing_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/routing.dart test/domain/routing_test.dart
git commit -m "feat(domain): add home-screen routing function"
```

---

### Task 7: TransitionResult + complete

**Files:**
- Create: `lib/domain/transitions.dart`
- Test: `test/domain/transitions_complete_test.dart`

**Interfaces:**
- Consumes: `Task`, `TaskKind`, `TaskStatus`, `UserState`.
- Produces: `class TransitionResult { final UserState user; final List<Task> changedTasks; const TransitionResult({required this.user, required this.changedTasks}); }`; `TransitionResult complete(UserState state, Task task, DateTime now)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/transitions_complete_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/transitions.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);
  final user = UserState(timezone: 'UTC', target: 3, lastActiveDate: now);

  Task oneOff() => Task(
        id: 'o', title: 'o', kind: TaskKind.oneOff,
        dueAt: now, createdAt: DateTime(2026, 1, 1),
      );
  Task recurring() => Task(
        id: 'r', title: 'r', kind: TaskKind.recurring, intervalDays: 5,
        dueAt: now, createdAt: DateTime(2026, 1, 1),
      );

  test('one-off is archived and counters increment', () {
    final res = complete(user, oneOff(), now);
    expect(res.changedTasks.single.status, TaskStatus.archived);
    expect(res.changedTasks.single.completedAt, now);
    expect(res.user.doneToday, 1);
    expect(res.user.lifetimeDone, 1);
  });

  test('recurring stays active with advanced dueAt', () {
    final res = complete(user, recurring(), now);
    final t = res.changedTasks.single;
    expect(t.status, TaskStatus.active);
    expect(t.completedAt, now);
    expect(t.dueAt, now.add(const Duration(days: 5)));
  });

  test('first completion of the day banks the streak', () {
    final res = complete(user, oneOff(), now);
    expect(res.user.bankedToday, isTrue);
    expect(res.user.streak, 1);
    expect(res.user.bestStreak, 1);
  });

  test('later completion same day does not re-bank', () {
    final banked = user.copyWith(bankedToday: true, streak: 4, bestStreak: 9, doneToday: 1);
    final res = complete(banked, oneOff(), now);
    expect(res.user.streak, 4);
    expect(res.user.bestStreak, 9);
    expect(res.user.doneToday, 2);
  });

  test('exact target hit bumps targetMetDays; non-exact does not', () {
    final atTwo = user.copyWith(doneToday: 2, bankedToday: true, streak: 1);
    expect(complete(atTwo, oneOff(), now).user.targetMetDays, 1); // 2 -> 3 == target
    final atThree = user.copyWith(doneToday: 3, bankedToday: true, streak: 1);
    expect(complete(atThree, oneOff(), now).user.targetMetDays, 0); // 3 -> 4, overshoot
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/transitions_complete_test.dart`
Expected: FAIL — URI for `transitions.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/transitions.dart
import 'dart:math' as math;

import 'task.dart';
import 'user_state.dart';

/// The intended writes from a pure transition. Phase 3 commits [user] and
/// [changedTasks] together in one Firestore WriteBatch (D11).
class TransitionResult {
  final UserState user;
  final List<Task> changedTasks;
  const TransitionResult({required this.user, required this.changedTasks});
}

/// Complete a task (swipe-right Done). HANDOFF §4.
TransitionResult complete(UserState state, Task task, DateTime now) {
  final Task updated;
  if (task.kind == TaskKind.oneOff) {
    updated = task.copyWith(status: TaskStatus.archived, completedAt: now);
  } else {
    updated = task.copyWith(
      completedAt: now,
      dueAt: now.add(Duration(days: task.intervalDays!)),
    );
  }

  var user = state.copyWith(
    doneToday: state.doneToday + 1,
    lifetimeDone: state.lifetimeDone + 1,
  );

  if (!state.bankedToday) {
    final newStreak = state.streak + 1;
    user = user.copyWith(
      bankedToday: true,
      streak: newStreak,
      bestStreak: math.max(state.bestStreak, newStreak),
    );
  }

  if (user.doneToday == user.target) {
    user = user.copyWith(targetMetDays: user.targetMetDays + 1);
  }

  return TransitionResult(user: user, changedTasks: [updated]);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/transitions_complete_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/transitions.dart test/domain/transitions_complete_test.dart
git commit -m "feat(domain): add complete transition with streak banking"
```

---

### Task 8: skip / remove / keepGoing

**Files:**
- Modify: `lib/domain/transitions.dart`
- Test: `test/domain/transitions_misc_test.dart`

**Interfaces:**
- Consumes: `TransitionResult`, `Task`, `TaskStatus`, `UserState`.
- Produces: `TransitionResult skip(UserState state, Task task)` (task→benched, `rerolls−1`; asserts `rerolls>0`); `TransitionResult remove(UserState state, Task task)` (task→removed; user unchanged); `TransitionResult keepGoing(UserState state)` (`targetDismissed=true`; empty `changedTasks`).

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/transitions_misc_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/transitions.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);
  final user = UserState(timezone: 'UTC', lastActiveDate: now);
  final task = Task(
    id: 't', title: 't', kind: TaskKind.recurring, intervalDays: 7,
    dueAt: now, createdAt: DateTime(2026, 1, 1),
  );

  test('skip benches the task and decrements rerolls', () {
    final res = skip(user.copyWith(rerolls: 3), task);
    expect(res.changedTasks.single.status, TaskStatus.benched);
    expect(res.user.rerolls, 2);
  });

  test('remove marks the task removed and leaves the user unchanged', () {
    final res = remove(user, task);
    expect(res.changedTasks.single.status, TaskStatus.removed);
    expect(res.user, user);
  });

  test('keepGoing sets targetDismissed with no task change', () {
    final res = keepGoing(user);
    expect(res.user.targetDismissed, isTrue);
    expect(res.changedTasks, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/transitions_misc_test.dart`
Expected: FAIL — `skip`/`remove`/`keepGoing` not defined.

- [ ] **Step 3: Write minimal implementation** (append to `lib/domain/transitions.dart`)

```dart
/// Skip / reroll (swipe-left). Benches the task for today, spends a reroll.
TransitionResult skip(UserState state, Task task) {
  assert(state.rerolls > 0, 'no rerolls left — caller must guard');
  return TransitionResult(
    user: state.copyWith(rerolls: state.rerolls - 1),
    changedTasks: [task.copyWith(status: TaskStatus.benched)],
  );
}

/// Remove a task from the pool entirely (long-press).
TransitionResult remove(UserState state, Task task) {
  return TransitionResult(
    user: state,
    changedTasks: [task.copyWith(status: TaskStatus.removed)],
  );
}

/// "Keep going" from targetHit/cleared — dismiss the celebration for today.
TransitionResult keepGoing(UserState state) {
  return TransitionResult(
    user: state.copyWith(targetDismissed: true),
    changedTasks: const [],
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/transitions_misc_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/transitions.dart test/domain/transitions_misc_test.dart
git commit -m "feat(domain): add skip, remove, and keepGoing transitions"
```

---

### Task 9: dailyReset (with streak break)

**Files:**
- Modify: `lib/domain/transitions.dart`
- Test: `test/domain/transitions_reset_test.dart`

**Interfaces:**
- Consumes: `TransitionResult`, `Task`, `TaskStatus`, `UserState`, `daysBetweenLocalDates`.
- Produces: `TransitionResult dailyReset(UserState state, List<Task> tasks, DateTime now, {int defaultRerolls = 3})`. No-op when same local date. On rollover: reset today-counters, set `lastActiveDate=now`, un-bench all benched tasks (in `changedTasks`); zero `streak` iff `!bankedToday || gap >= 2`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/transitions_reset_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/transitions.dart';

void main() {
  Task benched() => Task(
        id: 'b', title: 'b', kind: TaskKind.recurring, intervalDays: 7,
        dueAt: DateTime(2026, 6, 20), createdAt: DateTime(2026, 1, 1),
        status: TaskStatus.benched,
      );

  final yesterday = DateTime(2026, 6, 22);
  final today = DateTime(2026, 6, 23, 9);

  UserState active({required DateTime last, bool banked = true, int streak = 5}) =>
      UserState(
        timezone: 'UTC', lastActiveDate: last, bankedToday: banked,
        streak: streak, doneToday: 2, rerolls: 1, targetDismissed: true,
      );

  test('same local date is a no-op', () {
    final state = active(last: DateTime(2026, 6, 23, 1));
    final res = dailyReset(state, [benched()], today);
    expect(res.user, state);
    expect(res.changedTasks, isEmpty);
  });

  test('rollover resets counters and un-benches tasks', () {
    final res = dailyReset(active(last: yesterday), [benched()], today);
    expect(res.user.doneToday, 0);
    expect(res.user.rerolls, 3);
    expect(res.user.bankedToday, isFalse);
    expect(res.user.targetDismissed, isFalse);
    expect(res.user.lastActiveDate, today);
    expect(res.changedTasks.single.status, TaskStatus.active);
  });

  test('consecutive banked day keeps the streak', () {
    final res = dailyReset(active(last: yesterday, banked: true), const [], today);
    expect(res.user.streak, 5);
  });

  test('left day unbanked breaks the streak (gap 1)', () {
    final res = dailyReset(active(last: yesterday, banked: false), const [], today);
    expect(res.user.streak, 0);
  });

  test('multi-day gap breaks the streak even if last day was banked', () {
    final res = dailyReset(
      active(last: DateTime(2026, 6, 20), banked: true), const [], today);
    expect(res.user.streak, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/transitions_reset_test.dart`
Expected: FAIL — `dailyReset` not defined.

- [ ] **Step 3: Write minimal implementation** (append to `lib/domain/transitions.dart`, and add the import)

At the top of `lib/domain/transitions.dart`, add alongside the existing imports:

```dart
import 'urgency.dart' show daysBetweenLocalDates;
```

Then append:

```dart
/// Daily rollover (D7). Idempotent: a no-op when [now] is the same local date
/// as [state.lastActiveDate], so it is safe to call on every resume (D22).
TransitionResult dailyReset(
  UserState state,
  List<Task> tasks,
  DateTime now, {
  int defaultRerolls = 3,
}) {
  final gap = daysBetweenLocalDates(state.lastActiveDate, now);
  if (gap == 0) {
    return TransitionResult(user: state, changedTasks: const []);
  }

  // Streak counts consecutive local days each with a completion. It breaks when
  // the day being left ended unbanked, or a full intermediate day was skipped.
  final brokeStreak = !state.bankedToday || gap >= 2;

  final user = state.copyWith(
    bankedToday: false,
    targetDismissed: false,
    doneToday: 0,
    rerolls: defaultRerolls,
    lastActiveDate: now,
    streak: brokeStreak ? 0 : state.streak,
  );

  final unbenched = tasks
      .where((t) => t.status == TaskStatus.benched)
      .map((t) => t.copyWith(status: TaskStatus.active))
      .toList();

  return TransitionResult(user: user, changedTasks: unbenched);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/transitions_reset_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/transitions.dart test/domain/transitions_reset_test.dart
git commit -m "feat(domain): add daily reset with streak-break logic"
```

---

### Task 10: palette + halo colour

**Files:**
- Create: `lib/theme/palette.dart`
- Test: `test/theme/palette_test.dart`

**Interfaces:**
- Consumes: `package:flutter/painting.dart` (`Color`).
- Produces: a `Palette` abstract holder of `static const Color` tokens (`paper`, `ink`, `mutedStrong`, `muted`, `accent`, `terracotta`, `iconCream`); `Color haloColor(double u)` interpolating calm `rgb(95,140,99)` ↔ urgent `rgb(196,104,63)` by `u` (clamped).

- [ ] **Step 1: Write the failing test**

```dart
// test/theme/palette_test.dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/theme/palette.dart';

void main() {
  test('tokens use the exact spec hex values', () {
    expect(Palette.paper, const Color(0xFFF3F1EC));
    expect(Palette.ink, const Color(0xFF2B2824));
    expect(Palette.accent, const Color(0xFF5F8C63));
    expect(Palette.terracotta, const Color(0xFFC2683F));
  });

  test('haloColor interpolates calm -> urgent', () {
    expect(haloColor(0), const Color.fromARGB(255, 95, 140, 99));
    expect(haloColor(1), const Color.fromARGB(255, 196, 104, 63));
    final mid = haloColor(0.5);
    expect(mid.red, closeTo(145, 1));
    expect(mid.green, closeTo(122, 1));
    expect(mid.blue, closeTo(81, 1));
  });

  test('haloColor clamps out-of-range input', () {
    expect(haloColor(-1), haloColor(0));
    expect(haloColor(2), haloColor(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/palette_test.dart`
Expected: FAIL — URI for `palette.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/theme/palette.dart
import 'dart:ui';

/// Static colour tokens for the paper/ink aesthetic (HANDOFF §6).
abstract final class Palette {
  static const Color paper = Color(0xFFF3F1EC);
  static const Color ink = Color(0xFF2B2824);
  static const Color mutedStrong = Color(0xFF5C574E);
  static const Color muted = Color(0xFF8F8A80);
  static const Color accent = Color(0xFF5F8C63);
  static const Color terracotta = Color(0xFFC2683F);
  static const Color iconCream = Color(0xFFEFEAE0);
}

const Color _haloCalm = Color.fromARGB(255, 95, 140, 99);
const Color _haloUrgent = Color.fromARGB(255, 196, 104, 63);

/// Urgency -> halo colour (the prototype's `mix(u)`); [u] clamped to [0,1].
Color haloColor(double u) {
  return Color.lerp(_haloCalm, _haloUrgent, u.clamp(0.0, 1.0))!;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/palette_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/theme/palette.dart test/theme/palette_test.dart
git commit -m "feat(theme): add colour palette and halo interpolation"
```

---

### Task 11: type scale + text styles

**Files:**
- Modify: `pubspec.yaml` (add `google_fonts`)
- Create: `lib/theme/type_scale.dart`
- Test: `test/theme/type_scale_test.dart`

**Interfaces:**
- Consumes: `google_fonts`, `package:flutter/painting.dart`.
- Produces: `abstract final class TypeScale` with `static const double` ladder steps (`body = 14.0`, plus named steps `caption`, `label`, `overline`, `title`, `headline`, `display`, `numeral` chosen from the major-second ladder) and `static TextStyle serif(double size, {FontWeight weight, ...})` / `sans(...)` builders wrapping `GoogleFonts.newsreader` / `GoogleFonts.nunitoSans`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add google_fonts`
Expected: `pubspec.yaml` gains a `google_fonts:` line under dependencies; `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test**

```dart
// test/theme/type_scale_test.dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/theme/type_scale.dart';

void main() {
  test('body anchors the scale at 14', () {
    expect(TypeScale.body, 14.0);
  });

  test('ladder steps follow the 1.125 major-second ratio', () {
    expect(TypeScale.title / TypeScale.body, closeTo(1.125, 0.01));
  });

  test('serif/sans builders apply size and weight', () {
    final s = TypeScale.serif(TypeScale.headline, weight: FontWeight.w500);
    expect(s.fontSize, closeTo(TypeScale.headline, 0.01));
    expect(s.fontWeight, FontWeight.w500);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/theme/type_scale_test.dart`
Expected: FAIL — URI for `type_scale.dart` doesn't exist.

- [ ] **Step 4: Write minimal implementation**

```dart
// lib/theme/type_scale.dart
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Major-second modular scale (ratio 1.125, base 14px) — HANDOFF §6.
abstract final class TypeScale {
  static const double overline = 11.1; // uppercase eyebrows
  static const double caption = 12.4;
  static const double label = 12.4;
  static const double body = 14.0; // anchor
  static const double title = 15.8;
  static const double headline = 22.4;
  static const double display = 35.9;
  static const double numeral = 51.1; // target/streak numerals, clock

  /// Newsreader (serif) — display, headings, task titles, numerals.
  static TextStyle serif(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.newsreader(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  /// Nunito Sans — UI, body, labels.
  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.nunitoSans(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/theme/type_scale_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/theme/type_scale.dart test/theme/type_scale_test.dart
git commit -m "feat(theme): add modular type scale with Newsreader/Nunito Sans"
```

---

### Task 12: app theme

**Files:**
- Create: `lib/theme/app_theme.dart`
- Test: `test/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: `package:flutter/material.dart`, `Palette`, `TypeScale`.
- Produces: `ThemeData buildAppTheme()` — light theme, paper scaffold, ink text, accent-green seed, default font Nunito Sans.

- [ ] **Step 1: Write the failing test**

```dart
// test/theme/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/theme/app_theme.dart';
import 'package:justone/theme/palette.dart';

void main() {
  test('theme uses paper scaffold and accent seed, light brightness', () {
    final theme = buildAppTheme();
    expect(theme.scaffoldBackgroundColor, Palette.paper);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.brightness, Brightness.light);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: FAIL — URI for `app_theme.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'palette.dart';
import 'type_scale.dart';

/// The single light theme for Just One (paper/ink aesthetic, HANDOFF §6).
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.light,
  ).copyWith(surface: Palette.paper);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Palette.paper,
    textTheme: TextTheme(
      bodyMedium: TypeScale.sans(TypeScale.body, color: Palette.ink),
      titleMedium: TypeScale.serif(TypeScale.title, color: Palette.ink),
      headlineMedium: TypeScale.serif(TypeScale.headline, color: Palette.ink),
      displaySmall: TypeScale.serif(TypeScale.display, color: Palette.ink),
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS — every domain + theme test green.

- [ ] **Step 6: Commit**

```bash
git add lib/theme/app_theme.dart test/theme/app_theme_test.dart
git commit -m "feat(theme): assemble app ThemeData from palette and type scale"
```

---

## Notes for the implementer

- The default Flutter counter app (`lib/main.dart`, `test/widget_test.dart`) is **not touched** in this phase — wiring the theme into a running app is Phase 2. (`test/widget_test.dart` references the old counter UI; leave it. If it fails the full-suite run, that's pre-existing — flag it, don't fix it here.)
- Everything in `lib/domain/` must stay free of Firebase and Flutter-widget imports. `lib/theme/` may import `flutter/material.dart`.
- All constants flagged "tunable" (urgency, defaults) live in one place per file so later tuning is a one-line change.
- `UserState` intentionally **omits** the server-only `lastNotified` field. No Phase-1 logic reads or writes it, and there's no serialization yet; it's added in Phase 3 when the Firestore mapping lands. This is a conscious YAGNI deviation from the spec's "model it as read-only" line, not an oversight.
```
