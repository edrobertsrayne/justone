# Phase 2 — Daily-loop UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the playable daily loop — swipeable daily card + `cleared` / `emptyPool` / `targetHit` screens + toasts — driven by the Phase-1 domain engine against an in-memory fake repository.

**Architecture:** A `Repository` seam (in-memory now, Firestore in Phase 3) feeds Riverpod `StreamProvider`s. Screens are derived purely from the pure `routeHome`. A `DailyController` runs the four actions (complete/skip/remove/keepGoing) by calling Phase-1 transitions and committing the result. The card's drag/fling/spring-back/long-press physics are hand-built on `GestureDetector` + `AnimationController`.

**Tech Stack:** Flutter, flutter_riverpod ^3.3.2 (manual providers, no codegen), google_fonts, the Phase-1 `lib/domain` + `lib/theme`.

## Global Constraints

- **No Firebase imports** anywhere in `lib/` this phase — the data layer is in-memory only.
- `now` is always passed into `lib/domain` calls; never `DateTime.now()` inside `lib/domain`. UI/controllers get `now` from `nowProvider` (a `Clock = DateTime Function()`), never by calling `DateTime.now()` inline in widgets.
- Halo colour comes from the top-level `haloColor(double u)` in `lib/theme/palette.dart` — do not re-derive the calm→urgent interpolation. Calm `rgb(95,140,99)`, urgent `rgb(196,104,63)`.
- The daily screen shows **no** counters, badges, meta text, or streak numbers — the halo is the only ambient signal. The streak number appears **only** on `targetHit`.
- `routeHome` / `selectTask` / `isDue` from Phase 1 are the routing + selection authority. Do **not** reintroduce the prototype's `urg > 0.04` cutoff (`dueThreshold = 0.30` is the live cutoff).
- Exact tokens (verbatim from the spec / prototype): title `Newsreader` 500 / 40.4px; "TODAY" overline `Nunito Sans` 700 / 9.8px / .2em / `#c2bcae`; toast bg `#2b2824`, cream text `Nunito Sans` 600 / 12.4px; hint "✓ Done" bg `#5f8c63`, "Skip ✕" bg `#6f8099`; FAB `#2b2824` 56×56; halo `sz = 340 + u*160`, height `sz*0.86`, blur ~62, opacity `0.12 + u*0.5`, anchored centre-bottom ~130px below the card bottom.
- Toast strings (exact): `"Day streak secured for today"`, `"That was your last skip for today"`, `"You're out of skips until tomorrow"`, `"Bonus round — your streak is safe"`.
- Files under ~1000 lines; YAGNI; TDD; frequent commits.
- Theme/font-dependent widget tests must call `TestWidgetsFlutterBinding.ensureInitialized()` (google_fonts), as in Phase 1.

**File structure (created this phase):**
```
lib/data/repository.dart            abstract Repository
lib/data/in_memory_repository.dart  fake impl + seeded factory
lib/app/providers.dart              repository/user/tasks/now providers + Clock
lib/app/toast_controller.dart       ToastController + toastProvider
lib/app/daily_controller.dart       DailyController + dailyControllerProvider
lib/ui/placeholder_screen.dart      generic "coming soon"
lib/ui/toast.dart                   ToastOverlay widget
lib/ui/empty_pool_screen.dart
lib/ui/cleared_screen.dart
lib/ui/target_hit_screen.dart
lib/ui/swipe_card.dart              visuals (Task 10) + gestures (Task 11)
lib/ui/daily_screen.dart            chrome + FAB + SwipeCard host
lib/ui/home_router.dart             routeHome -> screen
lib/main.dart                       replaces the counter app
```

---

### Task 1: Repository seam + InMemoryRepository

**Files:**
- Create: `lib/data/repository.dart`
- Create: `lib/data/in_memory_repository.dart`
- Test: `test/data/in_memory_repository_test.dart`

**Interfaces:**
- Consumes: `UserState` (`lib/domain/user_state.dart`), `Task`/`TaskKind`/`TaskStatus` (`lib/domain/task.dart`), `TransitionResult` (`lib/domain/transitions.dart`), `routeHome`/`AppScreen` (`lib/domain/routing.dart`).
- Produces: `abstract class Repository { Stream<UserState> watchUser(); Stream<List<Task>> watchTasks(); Future<void> commit(TransitionResult result); }`; `class InMemoryRepository implements Repository` with `InMemoryRepository({required UserState user, required List<Task> tasks})` and `factory InMemoryRepository.seeded()`.

- [ ] **Step 1: Write the failing tests**

`test/data/in_memory_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/routing.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/transitions.dart';
import 'package:justone/domain/user_state.dart';

UserState _user() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23));
Task _task(String id, {TaskStatus status = TaskStatus.active}) => Task(
      id: id,
      title: 'T$id',
      kind: TaskKind.oneOff,
      createdAt: DateTime(2026, 6, 1),
      status: status,
    );

void main() {
  test('watchUser/watchTasks replay the latest value to new subscribers', () async {
    final repo = InMemoryRepository(user: _user(), tasks: [_task('1')]);
    expect((await repo.watchUser().first).timezone, 'UTC');
    expect((await repo.watchTasks().first).single.id, '1');
  });

  test('commit replaces the user, merges changedTasks by id, and re-emits', () async {
    final repo = InMemoryRepository(user: _user(), tasks: [_task('1'), _task('2')]);
    final emitted = <List<Task>>[];
    final sub = repo.watchTasks().listen(emitted.add);
    await Future<void>.delayed(Duration.zero);

    final changed = _task('1', status: TaskStatus.archived);
    await repo.commit(TransitionResult(
      user: _user().copyWith(doneToday: 1),
      changedTasks: [changed],
    ));

    expect((await repo.watchUser().first).doneToday, 1);
    final latest = await repo.watchTasks().first;
    expect(latest.length, 2); // unchanged task retained
    expect(latest.firstWhere((t) => t.id == '1').status, TaskStatus.archived);
    expect(latest.firstWhere((t) => t.id == '2').status, TaskStatus.active);
    expect(emitted.length, greaterThanOrEqualTo(1)); // live subscriber got the update
    await sub.cancel();
  });

  test('commit appends a changedTask whose id is new', () async {
    final repo = InMemoryRepository(user: _user(), tasks: [_task('1')]);
    await repo.commit(TransitionResult(user: _user(), changedTasks: [_task('9')]));
    final latest = await repo.watchTasks().first;
    expect(latest.map((t) => t.id), containsAll(['1', '9']));
  });

  test('seeded() opens on the daily screen (at least one task is due)', () async {
    final repo = InMemoryRepository.seeded();
    final user = await repo.watchUser().first;
    final tasks = await repo.watchTasks().first;
    expect(routeHome(user, tasks, DateTime.now()), AppScreen.daily);
  });
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `flutter test test/data/in_memory_repository_test.dart`
Expected: FAIL — `repository.dart` / `in_memory_repository.dart` do not exist.

- [ ] **Step 3: Write the implementation**

`lib/data/repository.dart`:
```dart
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
}
```

`lib/data/in_memory_repository.dart`:
```dart
import 'dart:async';

import '../domain/task.dart';
import '../domain/transitions.dart';
import '../domain/user_state.dart';
import 'repository.dart';

/// In-memory fake repository (Phase 2). Streams replay the latest value to each
/// new subscriber, then deliver live updates — adequate for a single-isolate fake.
class InMemoryRepository implements Repository {
  InMemoryRepository({required UserState user, required List<Task> tasks})
      : _user = user,
        _tasks = List<Task>.of(tasks);

  UserState _user;
  List<Task> _tasks;
  final _userCtrl = StreamController<UserState>.broadcast();
  final _tasksCtrl = StreamController<List<Task>>.broadcast();

  @override
  Stream<UserState> watchUser() async* {
    yield _user;
    yield* _userCtrl.stream;
  }

  @override
  Stream<List<Task>> watchTasks() async* {
    yield List<Task>.unmodifiable(_tasks);
    yield* _tasksCtrl.stream;
  }

  @override
  Future<void> commit(TransitionResult result) async {
    _user = result.user;
    final updated = List<Task>.of(_tasks);
    for (final changed in result.changedTasks) {
      final i = updated.indexWhere((t) => t.id == changed.id);
      if (i >= 0) {
        updated[i] = changed;
      } else {
        updated.add(changed);
      }
    }
    _tasks = updated;
    _userCtrl.add(_user);
    _tasksCtrl.add(List<Task>.unmodifiable(_tasks));
  }

  /// A realistic pool for running the app by hand. At least one task is due so
  /// the app opens on `daily`. Tests construct [InMemoryRepository] directly.
  factory InMemoryRepository.seeded() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime day(int offset) => today.add(Duration(days: offset));
    final tasks = <Task>[
      Task(id: 't1', title: 'Reply to the landlord', kind: TaskKind.oneOff, dueAt: day(-2), createdAt: day(-5)),
      Task(id: 't2', title: 'Water the plants', kind: TaskKind.recurring, intervalDays: 3, dueAt: day(0), createdAt: day(-10)),
      Task(id: 't3', title: 'Take out the recycling', kind: TaskKind.recurring, intervalDays: 7, dueAt: day(0), createdAt: day(-14)),
      Task(id: 't4', title: 'Back up the laptop', kind: TaskKind.oneOff, createdAt: day(-3)),
      Task(id: 't5', title: 'Descale the kettle', kind: TaskKind.oneOff, dueAt: day(6), createdAt: day(-1)),
    ];
    final user = UserState(
      timezone: 'UTC',
      target: 3,
      rerolls: 3,
      streak: 4,
      bestStreak: 4,
      onboardingComplete: true,
      lastActiveDate: today,
    );
    return InMemoryRepository(user: user, tasks: tasks);
  }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `flutter test test/data/in_memory_repository_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/ test/data/
git commit -m "feat(data): add Repository seam + InMemoryRepository"
```

---

### Task 2: Providers (repository / user / tasks / now)

**Files:**
- Create: `lib/app/providers.dart`
- Test: `test/app/providers_test.dart`

**Interfaces:**
- Consumes: `Repository`, `InMemoryRepository`, `UserState`, `Task`.
- Produces: `typedef Clock = DateTime Function();`, `repositoryProvider` (`Provider<Repository>`, defaults to `InMemoryRepository.seeded()`), `userProvider` (`StreamProvider<UserState>`), `tasksProvider` (`StreamProvider<List<Task>>`), `nowProvider` (`Provider<Clock>`, defaults to `DateTime.now`).

- [ ] **Step 1: Write the failing test**

`test/app/providers_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  test('user/tasks providers stream the overridden repository', () async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), streak: 7),
      tasks: [Task(id: 'a', title: 'A', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1))],
    );
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    expect((await container.read(userProvider.future)).streak, 7);
    expect((await container.read(tasksProvider.future)).single.id, 'a');
  });

  test('nowProvider can be overridden to a fixed instant', () {
    final fixed = DateTime(2026, 6, 23, 9);
    final container = ProviderContainer(overrides: [nowProvider.overrideWithValue(() => fixed)]);
    addTearDown(container.dispose);
    expect(container.read(nowProvider)(), fixed);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/app/providers_test.dart`
Expected: FAIL — `providers.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/app/providers.dart`:
```dart
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
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/app/providers_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/providers.dart test/app/providers_test.dart
git commit -m "feat(app): add repository/user/tasks/now providers"
```

---

### Task 3: ToastController

**Files:**
- Create: `lib/app/toast_controller.dart`
- Test: `test/app/toast_controller_test.dart`

**Interfaces:**
- Produces: `class ToastController extends Notifier<String?>` with `void show(String message, {Duration duration})`; `final toastProvider = NotifierProvider<ToastController, String?>(ToastController.new);`. State is the current toast message, or `null` when none.

- [ ] **Step 1: Write the failing test**

`test/app/toast_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/toast_controller.dart';

void main() {
  test('show sets the message then auto-clears after the duration', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(toastProvider), isNull);
    container.read(toastProvider.notifier).show('hi', duration: const Duration(milliseconds: 20));
    expect(container.read(toastProvider), 'hi');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(container.read(toastProvider), isNull);
  });

  test('a second show replaces the first message', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(toastProvider.notifier);
    c.show('one');
    c.show('two');
    expect(container.read(toastProvider), 'two');
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/app/toast_controller_test.dart`
Expected: FAIL — `toast_controller.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/app/toast_controller.dart`:
```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the current top-toast message (or null). Auto-clears after [show]'s
/// duration; a new [show] replaces the current message and resets the timer.
class ToastController extends Notifier<String?> {
  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(String message, {Duration duration = const Duration(seconds: 2)}) {
    _timer?.cancel();
    state = message;
    _timer = Timer(duration, () => state = null);
  }
}

final toastProvider = NotifierProvider<ToastController, String?>(ToastController.new);
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/app/toast_controller_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/toast_controller.dart test/app/toast_controller_test.dart
git commit -m "feat(app): add ToastController with auto-dismiss"
```

---

### Task 4: DailyController

**Files:**
- Create: `lib/app/daily_controller.dart`
- Test: `test/app/daily_controller_test.dart`

**Interfaces:**
- Consumes: `Repository`, `ToastController`, `Clock`, the domain transitions (`complete`/`skip`/`remove`/`keepGoing` from `lib/domain/transitions.dart`).
- Produces: `class DailyController` with `Future<void> complete(UserState, Task)`, `Future<void> skip(UserState, Task)`, `void skipDenied()`, `Future<void> remove(UserState, Task)`, `Future<void> keepGoing(UserState)`; `final dailyControllerProvider = Provider<DailyController>(...)`.
- Contract: the card never flings off on a denied skip — `skip` is only called when `rerolls > 0`; `skipDenied` handles the empty case. `skip` defensively re-guards.

- [ ] **Step 1: Write the failing test**

`test/app/daily_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/daily_controller.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/app/toast_controller.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

UserState _user({int rerolls = 3, bool banked = false}) => UserState(
      timezone: 'UTC',
      lastActiveDate: DateTime(2026, 6, 23),
      rerolls: rerolls,
      bankedToday: banked,
      streak: 4,
    );
Task _t() => Task(id: 'x', title: 'X', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

({DailyController controller, InMemoryRepository repo, ProviderContainer container}) _harness(UserState u) {
  final repo = InMemoryRepository(user: u, tasks: [_t()]);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    nowProvider.overrideWithValue(() => DateTime(2026, 6, 23, 9)),
  ]);
  return (controller: container.read(dailyControllerProvider), repo: repo, container: container);
}

void main() {
  test('complete banks the streak with a toast on the first completion', () async {
    final h = _harness(_user(banked: false));
    addTearDown(h.container.dispose);
    await h.controller.complete(_user(banked: false), _t());
    expect(h.container.read(toastProvider), 'Day streak secured for today');
    expect((await h.repo.watchUser().first).bankedToday, isTrue);
  });

  test('complete after banking shows no streak toast', () async {
    final h = _harness(_user(banked: true));
    addTearDown(h.container.dispose);
    await h.controller.complete(_user(banked: true), _t());
    expect(h.container.read(toastProvider), isNull);
  });

  test('skip spends a reroll; the skip landing on zero toasts the last-skip warning', () async {
    final h = _harness(_user(rerolls: 1));
    addTearDown(h.container.dispose);
    await h.controller.skip(_user(rerolls: 1), _t());
    expect(h.container.read(toastProvider), 'That was your last skip for today');
    expect((await h.repo.watchUser().first).rerolls, 0);
  });

  test('skipDenied toasts and commits nothing', () async {
    final h = _harness(_user(rerolls: 0));
    addTearDown(h.container.dispose);
    h.controller.skipDenied();
    expect(h.container.read(toastProvider), "You're out of skips until tomorrow");
  });

  test('keepGoing dismisses the target and toasts the bonus message', () async {
    final h = _harness(_user());
    addTearDown(h.container.dispose);
    await h.controller.keepGoing(_user());
    expect(h.container.read(toastProvider), 'Bonus round — your streak is safe');
    expect((await h.repo.watchUser().first).targetDismissed, isTrue);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/app/daily_controller_test.dart`
Expected: FAIL — `daily_controller.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/app/daily_controller.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/task.dart';
import '../domain/transitions.dart' as domain;
import '../domain/user_state.dart';
import 'providers.dart';
import 'toast_controller.dart';

/// The action layer for the daily loop: reads a snapshot, calls the Phase-1
/// transition, fires any toast, and commits the result.
class DailyController {
  DailyController({required Repository repo, required ToastController toast, required Clock now})
      : _repo = repo,
        _toast = toast,
        _now = now;

  final Repository _repo;
  final ToastController _toast;
  final Clock _now;

  Future<void> complete(UserState user, Task task) {
    final banks = !user.bankedToday;
    final result = domain.complete(user, task, _now());
    if (banks) _toast.show('Day streak secured for today');
    return _repo.commit(result);
  }

  Future<void> skip(UserState user, Task task) {
    if (user.rerolls <= 0) {
      skipDenied();
      return Future<void>.value();
    }
    final result = domain.skip(user, task);
    if (result.user.rerolls == 0) _toast.show('That was your last skip for today');
    return _repo.commit(result);
  }

  void skipDenied() => _toast.show("You're out of skips until tomorrow");

  Future<void> remove(UserState user, Task task) => _repo.commit(domain.remove(user, task));

  Future<void> keepGoing(UserState user) {
    _toast.show('Bonus round — your streak is safe');
    return _repo.commit(domain.keepGoing(user));
  }
}

final dailyControllerProvider = Provider<DailyController>((ref) => DailyController(
      repo: ref.watch(repositoryProvider),
      toast: ref.watch(toastProvider.notifier),
      now: ref.watch(nowProvider),
    ));
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/app/daily_controller_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/daily_controller.dart test/app/daily_controller_test.dart
git commit -m "feat(app): add DailyController actions + toasts"
```

---

### Task 5: PlaceholderScreen

**Files:**
- Create: `lib/ui/placeholder_screen.dart`
- Test: `test/ui/placeholder_screen_test.dart`

**Interfaces:**
- Produces: `class PlaceholderScreen extends StatelessWidget { const PlaceholderScreen({super.key, required this.title}); final String title; }` — a paper-backed scaffold showing "`<title>` — coming soon" with a back affordance (standard `AppBar`).

- [ ] **Step 1: Write the failing test**

`test/ui/placeholder_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/placeholder_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows the title and a coming-soon line', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlaceholderScreen(title: 'Manage')));
    expect(find.text('Manage'), findsOneWidget);
    expect(find.textContaining('coming soon'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/placeholder_screen_test.dart`
Expected: FAIL — `placeholder_screen.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/placeholder_screen.dart`:
```dart
import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Stand-in for screens that arrive in Phase 4/5 (manage / stats / add). The
/// route is real; only the body is swapped later.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      appBar: AppBar(title: Text(title), backgroundColor: Palette.paper),
      body: Center(
        child: Text('$title — coming soon',
            style: const TextStyle(color: Palette.muted)),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/placeholder_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/placeholder_screen.dart test/ui/placeholder_screen_test.dart
git commit -m "feat(ui): add PlaceholderScreen for deferred destinations"
```

---

### Task 6: ToastOverlay widget

**Files:**
- Create: `lib/ui/toast.dart`
- Test: `test/ui/toast_test.dart`

**Interfaces:**
- Consumes: `toastProvider`.
- Produces: `class ToastOverlay extends ConsumerWidget` — watches `toastProvider` and, when non-null, renders the top-anchored pill; renders nothing when null. Intended to be stacked above the screen content (top-aligned).

- [ ] **Step 1: Write the failing test**

`test/ui/toast_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/toast_controller.dart';
import 'package:justone/ui/toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('renders nothing when no toast, shows the pill when set', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: Stack(children: [ToastOverlay()]))),
    ));
    expect(find.text('Saved'), findsNothing);

    final element = tester.element(find.byType(ToastOverlay));
    final container = ProviderScope.containerOf(element);
    container.read(toastProvider.notifier).show('Saved', duration: const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/toast_test.dart`
Expected: FAIL — `toast.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/toast.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/toast_controller.dart';
import '../theme/palette.dart';

/// Top-anchored, auto-dismissing toast pill. Stack this above screen content.
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(toastProvider);
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: message == null
              ? const SizedBox.shrink()
              : Center(
                  key: ValueKey(message),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    decoration: BoxDecoration(
                      color: Palette.ink,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Palette.paper,
                        fontFamily: 'Nunito Sans',
                        fontWeight: FontWeight.w600,
                        fontSize: 12.4,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/toast_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/toast.dart test/ui/toast_test.dart
git commit -m "feat(ui): add top-anchored ToastOverlay"
```

---

### Task 7: EmptyPoolScreen

**Files:**
- Create: `lib/ui/empty_pool_screen.dart`
- Test: `test/ui/empty_pool_screen_test.dart`

**Interfaces:**
- Produces: `class EmptyPoolScreen extends StatelessWidget { const EmptyPoolScreen({super.key, required this.onAdd}); final VoidCallback onAdd; }` — hollow sage ring glyph, headline "Your pool\nis empty", body copy, and an "Add a chore" pill that calls `onAdd`.

- [ ] **Step 1: Write the failing test**

`test/ui/empty_pool_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/empty_pool_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows empty-pool copy and fires onAdd', (tester) async {
    var added = false;
    await tester.pumpWidget(MaterialApp(home: EmptyPoolScreen(onAdd: () => added = true)));
    expect(find.textContaining('Your pool'), findsOneWidget);
    expect(find.textContaining('Add a chore whenever one turns up'), findsOneWidget);
    await tester.tap(find.text('Add a chore'));
    expect(added, isTrue);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/empty_pool_screen_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/empty_pool_screen.dart`:
```dart
import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Zero tasks in the pool — distinct from `cleared` (which has tasks, none due).
class EmptyPoolScreen extends StatelessWidget {
  const EmptyPoolScreen({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0xFFE9EEE2), Palette.paper]),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDFE5D8)),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Your pool\nis empty',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 28.4, color: Palette.ink),
              ),
              const SizedBox(height: 14),
              const SizedBox(
                width: 210,
                child: Text(
                  'Nothing to do, and nothing hanging over you. Add a chore whenever one turns up.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Nunito Sans', fontSize: 15.8, height: 1.55, color: Palette.muted),
                ),
              ),
              const SizedBox(height: 30),
              _Pill(label: 'Add a chore', filled: true, onTap: onAdd),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared CTA pill: filled (ink) or outline. Reused by the rest screens.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        decoration: BoxDecoration(
          color: filled ? Palette.ink : null,
          border: filled ? null : Border.all(color: const Color(0xFFDDD6C9), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito Sans',
            fontWeight: FontWeight.w700,
            fontSize: 12.4,
            color: filled ? Palette.paper : const Color(0xFF6F6A60),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/empty_pool_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/empty_pool_screen.dart test/ui/empty_pool_screen_test.dart
git commit -m "feat(ui): add EmptyPoolScreen"
```

---

### Task 8: ClearedScreen

**Files:**
- Create: `lib/ui/cleared_screen.dart`
- Test: `test/ui/cleared_screen_test.dart`

**Interfaces:**
- Consumes: the `_Pill` pattern (re-declare a private `_Pill` in this file — do not export Task 7's; each file owns its own small pill to stay self-contained).
- Produces: `class ClearedScreen extends StatelessWidget { const ClearedScreen({super.key, required this.onReviewPool}); final VoidCallback onReviewPool; }` — breathing sage-dot glyph, headline "You're on top of\nthings", body "Nothing left in the pool. Enjoy the quiet.", and a "Review pool" outline pill calling `onReviewPool`. **No "Keep going" here.**

- [ ] **Step 1: Write the failing test**

`test/ui/cleared_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/cleared_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows cleared copy, a Review pool CTA, and no Keep going', (tester) async {
    var reviewed = false;
    await tester.pumpWidget(MaterialApp(home: ClearedScreen(onReviewPool: () => reviewed = true)));
    expect(find.textContaining("on top of"), findsOneWidget);
    expect(find.textContaining('Enjoy the quiet'), findsOneWidget);
    expect(find.textContaining('Keep going'), findsNothing);
    await tester.tap(find.text('Review pool'));
    expect(reviewed, isTrue);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/cleared_screen_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/cleared_screen.dart`:
```dart
import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// "You're caught up" — tasks remain but none are due. Distinct from emptyPool.
/// Terminal for the day: the only exit is reviewing the pool (no re-serve).
class ClearedScreen extends StatelessWidget {
  const ClearedScreen({super.key, required this.onReviewPool});

  final VoidCallback onReviewPool;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0xFFE9EEE2), Palette.paper]),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "You're on top of\nthings",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 28.4, color: Palette.ink),
              ),
              const SizedBox(height: 14),
              const SizedBox(
                width: 200,
                child: Text(
                  'Nothing left in the pool. Enjoy the quiet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Nunito Sans', fontSize: 15.8, height: 1.55, color: Palette.muted),
                ),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: onReviewPool,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDD6C9), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Review pool',
                    style: TextStyle(
                        fontFamily: 'Nunito Sans',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.4,
                        color: Color(0xFF6F6A60)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/cleared_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/cleared_screen.dart test/ui/cleared_screen_test.dart
git commit -m "feat(ui): add ClearedScreen (rest, no re-serve)"
```

---

### Task 9: TargetHitScreen

**Files:**
- Create: `lib/ui/target_hit_screen.dart`
- Test: `test/ui/target_hit_screen_test.dart`

**Interfaces:**
- Consumes: `UserState` (`streak`, `targetMetDays`, `target`).
- Produces: `class TargetHitScreen extends StatelessWidget { const TargetHitScreen({super.key, required this.user, required this.onKeepGoing}); final UserState user; final VoidCallback onKeepGoing; }` — `target` sage dots, "Daily target met", a two-stat card (streak + targetMetDays), body, and a "Keep going!" outline pill calling `onKeepGoing`. This is the only screen showing the streak number.

- [ ] **Step 1: Write the failing test**

`test/ui/target_hit_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/target_hit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows both stats and fires onKeepGoing', (tester) async {
    var kept = false;
    final user = UserState(
        timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), target: 3, streak: 5, targetMetDays: 12);
    await tester.pumpWidget(
        MaterialApp(home: TargetHitScreen(user: user, onKeepGoing: () => kept = true)));
    expect(find.textContaining('Daily target met'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // streak
    expect(find.text('12'), findsOneWidget); // targetMetDays
    expect(find.textContaining('Day streak'), findsOneWidget);
    expect(find.textContaining('On target'), findsOneWidget);
    await tester.tap(find.text('Keep going!'));
    expect(kept, isTrue);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/target_hit_screen_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/target_hit_screen.dart`:
```dart
import 'package:flutter/material.dart';

import '../domain/user_state.dart';
import '../theme/palette.dart';

/// Daily target reached — the one moment the streak number surfaces in the loop.
class TargetHitScreen extends StatelessWidget {
  const TargetHitScreen({super.key, required this.user, required this.onKeepGoing});

  final UserState user;
  final VoidCallback onKeepGoing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  user.target,
                  (_) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4.5),
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Daily target met',
                  style: TextStyle(
                      fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 28.4, color: Palette.accent)),
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Stat(value: '${user.streak}', label: 'Day streak', sub: 'showed up', color: Palette.accent),
                      const VerticalDivider(width: 1, color: Color(0xFFEFE9DE), indent: 16, endIndent: 16),
                      _Stat(value: '${user.targetMetDays}', label: 'On target', sub: 'hit full goal', color: Palette.ink),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 210,
                child: Text("You've done enough for today.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Nunito Sans', fontSize: 14, height: 1.55, color: Palette.muted)),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onKeepGoing,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDD6C9), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('Keep going!',
                      style: TextStyle(
                          fontFamily: 'Nunito Sans', fontWeight: FontWeight.w700, fontSize: 12.4, color: Color(0xFF6F6A60))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.sub, required this.color});

  final String value;
  final String label;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 40.4, color: color)),
          const SizedBox(height: 8),
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Nunito Sans', fontWeight: FontWeight.w700, fontSize: 8.7, letterSpacing: 1.0, color: Color(0xFFA8A193))),
          const SizedBox(height: 3),
          Text(sub, style: const TextStyle(fontFamily: 'Nunito Sans', fontSize: 11.1, color: Color(0xFFBDB7AB))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/target_hit_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/target_hit_screen.dart test/ui/target_hit_screen_test.dart
git commit -m "feat(ui): add TargetHitScreen with streak reveal"
```

---

### Task 10: SwipeCard — visuals (title, halo, hint labels)

**Files:**
- Create: `lib/ui/swipe_card.dart`
- Test: `test/ui/swipe_card_visual_test.dart`

**Interfaces:**
- Consumes: `Task`, the top-level `haloColor(double u)`.
- Produces: `class SwipeCard extends StatefulWidget` with constructor
  `const SwipeCard({super.key, required this.task, required this.urgency, required this.canSkip, required this.onComplete, required this.onSkip, required this.onSkipDenied, required this.onRemove});`
  fields: `final Task task; final double urgency; final bool canSkip; final VoidCallback onComplete, onSkip, onSkipDenied, onRemove;`.
- This task builds the visual shell + state scaffolding (drag offset field defaulting to 0, hint-opacity getters). Gestures land in Task 11.

- [ ] **Step 1: Write the failing test**

`test/ui/swipe_card_visual_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/ui/swipe_card.dart';

Task _t() => Task(id: 'x', title: 'Water the plants', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows the task title and no meta/counter text', (tester) async {
    await tester.pumpWidget(_host(SwipeCard(
      task: _t(),
      urgency: 0.6,
      canSkip: true,
      onComplete: () {},
      onSkip: () {},
      onSkipDenied: () {},
      onRemove: () {},
    )));
    expect(find.text('Water the plants'), findsOneWidget);
    // restraint: no due/overdue/streak/counter text on the card
    expect(find.textContaining('overdue'), findsNothing);
    expect(find.textContaining('due'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/swipe_card_visual_test.dart`
Expected: FAIL — `swipe_card.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/swipe_card.dart`:
```dart
import 'package:flutter/material.dart';

import '../domain/task.dart';
import '../theme/palette.dart';

/// The daily card. Serves one task: title + urgency halo only (no counters).
/// Drag right = Done, drag left = Skip, long-press = Remove (Task 11 wires the
/// gestures onto this shell).
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.task,
    required this.urgency,
    required this.canSkip,
    required this.onComplete,
    required this.onSkip,
    required this.onSkipDenied,
    required this.onRemove,
  });

  final Task task;
  final double urgency;
  final bool canSkip;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onSkipDenied;
  final VoidCallback onRemove;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> with SingleTickerProviderStateMixin {
  double _dx = 0; // current horizontal drag offset

  // Fraction of card width past which a release commits the action.
  static const double thresholdFraction = 0.25;

  double get _doneOpacity => _dx > 0 ? (_dx / 160).clamp(0.0, 1.0) : 0.0;
  double get _skipOpacity => _dx < 0 ? (-_dx / 160).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    final u = widget.urgency.clamp(0.0, 1.0);
    final sz = 340 + u * 160;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Halo: a single blurred ellipse anchored centre-bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: -130,
              child: Center(
                child: Opacity(
                  opacity: 0.12 + u * 0.5,
                  child: Container(
                    width: sz,
                    height: sz * 0.86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: haloColor(u),
                      boxShadow: [BoxShadow(color: haloColor(u), blurRadius: 62, spreadRadius: 20)],
                    ),
                  ),
                ),
              ),
            ),
            // The card content.
            Transform.translate(
              offset: Offset(_dx, 0),
              child: Transform.rotate(
                angle: _dx / 2400, // slight tilt with the drag
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.task.title,
                          style: const TextStyle(
                            fontFamily: 'Newsreader',
                            fontWeight: FontWeight.w500,
                            fontSize: 40.4,
                            height: 1.16,
                            letterSpacing: -0.6,
                            color: Palette.ink,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 30,
                      child: _Hint(label: '✓ Done', color: Palette.accent, opacity: _doneOpacity),
                    ),
                    Positioned(
                      top: 0,
                      right: 30,
                      child: _Hint(label: 'Skip ✕', color: const Color(0xFF6F8099), opacity: _skipOpacity),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.color, required this.opacity});

  final String label;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(
          label,
          style: const TextStyle(
              fontFamily: 'Nunito Sans', fontWeight: FontWeight.w800, fontSize: 11.1, letterSpacing: 1.3, color: Colors.white),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/swipe_card_visual_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/swipe_card.dart test/ui/swipe_card_visual_test.dart
git commit -m "feat(ui): add SwipeCard visual shell (title + halo + hints)"
```

---

### Task 11: SwipeCard — gestures (drag / fling / spring-back / long-press)

**Files:**
- Modify: `lib/ui/swipe_card.dart`
- Test: `test/ui/swipe_card_gesture_test.dart`

**Interfaces:**
- Consumes: the `SwipeCard` shell + callbacks from Task 10.
- Produces: drag handling that updates `_dx`, reveals hints, and on release commits (`onComplete` right / `onSkip` left when `canSkip` / `onSkipDenied` left when `!canSkip`) past the threshold or springs back under it; plus long-press → `onRemove`.

- [ ] **Step 1: Write the failing tests**

`test/ui/swipe_card_gesture_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/ui/swipe_card.dart';

Task _t() => Task(id: 'x', title: 'Water the plants', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

Widget _host({required bool canSkip, required Map<String, bool> hits}) => MaterialApp(
      home: Scaffold(
        body: SwipeCard(
          task: _t(),
          urgency: 0.5,
          canSkip: canSkip,
          onComplete: () => hits['complete'] = true,
          onSkip: () => hits['skip'] = true,
          onSkipDenied: () => hits['denied'] = true,
          onRemove: () => hits['remove'] = true,
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drag right past threshold completes', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(hits['complete'], isTrue);
  });

  testWidgets('drag left past threshold skips when allowed', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(hits['skip'], isTrue);
    expect(hits['denied'], isNull);
  });

  testWidgets('drag left past threshold is denied when out of skips', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: false, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(hits['denied'], isTrue);
    expect(hits['skip'], isNull);
  });

  testWidgets('small drag springs back without firing', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(hits['complete'], isNull);
    expect(hits['skip'], isNull);
  });

  testWidgets('long-press removes', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.longPress(find.byType(SwipeCard));
    await tester.pumpAndSettle();
    expect(hits['remove'], isTrue);
  });
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `flutter test test/ui/swipe_card_gesture_test.dart`
Expected: FAIL — no gesture handling yet (callbacks never fire).

- [ ] **Step 3: Wire the gestures**

In `lib/ui/swipe_card.dart`, give `SwipeCardState` an `AnimationController` and gesture handlers, and wrap the content in a `GestureDetector`. Add to the class:

```dart
  late final AnimationController _spring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  double _width = 0;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    final threshold = (_width == 0 ? 200 : _width * thresholdFraction);
    if (_dx > threshold) {
      _flingOff(1, widget.onComplete);
    } else if (_dx < -threshold) {
      if (widget.canSkip) {
        _flingOff(-1, widget.onSkip);
      } else {
        _springBack();
        widget.onSkipDenied();
      }
    } else {
      _springBack();
    }
  }

  void _springBack() {
    final from = _dx;
    _spring
      ..reset()
      ..duration = const Duration(milliseconds: 250);
    final anim = Tween<double>(begin: from, end: 0)
        .animate(CurvedAnimation(parent: _spring, curve: Curves.easeOutCubic));
    void listener() => setState(() => _dx = anim.value);
    anim.addListener(listener);
    _spring.forward().whenComplete(() => anim.removeListener(listener));
  }

  void _flingOff(int dir, VoidCallback then) {
    final target = dir * (_width == 0 ? 800 : _width * 1.5);
    final from = _dx;
    _spring
      ..reset()
      ..duration = const Duration(milliseconds: 200);
    final anim = Tween<double>(begin: from, end: target)
        .animate(CurvedAnimation(parent: _spring, curve: Curves.easeOut));
    void listener() => setState(() => _dx = anim.value);
    anim.addListener(listener);
    _spring.forward().whenComplete(() {
      anim.removeListener(listener);
      then();
    });
  }
```

Capture the width in `build` (set `_width = constraints.maxWidth;` inside the `LayoutBuilder` builder), and wrap the outer `Stack`'s card content with:

```dart
GestureDetector(
  onHorizontalDragUpdate: _onDragUpdate,
  onHorizontalDragEnd: _onDragEnd,
  onLongPress: widget.onRemove,
  child: /* the Transform.translate(...) card subtree */,
)
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `flutter test test/ui/swipe_card_gesture_test.dart`
Expected: PASS (5 tests). Also re-run Task 10's visual test to confirm no regression:
Run: `flutter test test/ui/swipe_card_visual_test.dart` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/swipe_card.dart test/ui/swipe_card_gesture_test.dart
git commit -m "feat(ui): wire SwipeCard drag/fling/spring-back/long-press"
```

---

### Task 12: DailyScreen (chrome + FAB + SwipeCard host)

**Files:**
- Create: `lib/ui/daily_screen.dart`
- Test: `test/ui/daily_screen_test.dart`

**Interfaces:**
- Consumes: `UserState`, `Task`, `urgencyOf` (`lib/domain/urgency.dart`), `nowProvider`, `dailyControllerProvider`, `SwipeCard`, `PlaceholderScreen`.
- Produces: `class DailyScreen extends ConsumerWidget { const DailyScreen({super.key, required this.user, required this.task}); final UserState user; final Task task; }` — renders the top chrome (manage ☰ left, "TODAY" centre, stats 📊 right), the `SwipeCard` (callbacks wired to `dailyControllerProvider`, `canSkip: user.rerolls > 0`, `urgency: urgencyOf(task, now)`), and the ink FAB bottom-right. ☰/📊/FAB push `PlaceholderScreen`s ('Manage' / 'Stats' / 'Add').

- [ ] **Step 1: Write the failing test**

`test/ui/daily_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/placeholder_screen.dart';
import 'package:justone/ui/swipe_card.dart';

UserState _user() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), rerolls: 3);
Task _t() => Task(id: 'x', title: 'Water the plants', kind: TaskKind.recurring, intervalDays: 3, dueAt: DateTime(2026, 6, 23), createdAt: DateTime(2026, 6, 1));

Widget _app() => ProviderScope(
      overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 6, 23, 9))],
      child: MaterialApp(home: DailyScreen(user: _user(), task: _t())),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders chrome + the served card', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byType(SwipeCard), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets('the FAB opens the add placeholder', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byKey(const ValueKey('daily-fab')));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceholderScreen), findsOneWidget);
    expect(find.textContaining('Add'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/daily_screen_test.dart`
Expected: FAIL — `daily_screen.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/daily_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/daily_controller.dart';
import '../app/providers.dart';
import '../domain/task.dart';
import '../domain/urgency.dart';
import '../domain/user_state.dart';
import '../theme/palette.dart';
import 'placeholder_screen.dart';
import 'swipe_card.dart';

class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key, required this.user, required this.task});

  final UserState user;
  final Task task;

  void _open(BuildContext context, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceholderScreen(title: title)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(dailyControllerProvider);
    final now = ref.watch(nowProvider)();
    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ChromeButton(icon: Icons.menu, onTap: () => _open(context, 'Manage')),
                      const Text('TODAY',
                          style: TextStyle(
                              fontFamily: 'Nunito Sans',
                              fontWeight: FontWeight.w700,
                              fontSize: 9.8,
                              letterSpacing: 1.96,
                              color: Color(0xFFC2BCAE))),
                      _ChromeButton(icon: Icons.bar_chart, onTap: () => _open(context, 'Stats')),
                    ],
                  ),
                ),
                Expanded(
                  child: SwipeCard(
                    task: task,
                    urgency: urgencyOf(task, now),
                    canSkip: user.rerolls > 0,
                    onComplete: () => controller.complete(user, task),
                    onSkip: () => controller.skip(user, task),
                    onSkipDenied: controller.skipDenied,
                    onRemove: () => controller.remove(user, task),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 22,
              bottom: 30,
              child: GestureDetector(
                key: const ValueKey('daily-fab'),
                onTap: () => _open(context, 'Add'),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(19)),
                  child: const Icon(Icons.add, color: Palette.paper),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, size: 18, color: const Color(0xFF8A847A)),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/daily_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/daily_screen.dart test/ui/daily_screen_test.dart
git commit -m "feat(ui): add DailyScreen chrome + FAB + card host"
```

---

### Task 13: HomeRouter

**Files:**
- Create: `lib/ui/home_router.dart`
- Test: `test/ui/home_router_test.dart`

**Interfaces:**
- Consumes: `userProvider`, `tasksProvider`, `nowProvider`, `routeHome`/`AppScreen`, `selectTask`, `dailyControllerProvider`, all screen widgets, `PlaceholderScreen`.
- Produces: `class HomeRouter extends ConsumerWidget` — reads the three providers, computes `routeHome(user, tasks, now)`, and renders `DailyScreen` (with `selectTask(tasks, now)!`) / `ClearedScreen` / `EmptyPoolScreen` / `TargetHitScreen`. Loading → paper blank; error → paper blank. `cleared`→`manage` placeholder, `emptyPool`/`add`→`add` placeholder, `targetHit`→`keepGoing()`.

- [ ] **Step 1: Write the failing test**

`test/ui/home_router_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/cleared_screen.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/empty_pool_screen.dart';
import 'package:justone/ui/home_router.dart';
import 'package:justone/ui/target_hit_screen.dart';

final _now = DateTime(2026, 6, 23, 9);
UserState _user({int target = 3, int done = 0, bool dismissed = false}) => UserState(
    timezone: 'UTC', lastActiveDate: _now, target: target, doneToday: done, targetDismissed: dismissed, onboardingComplete: true);
Task _due() => Task(id: 'd', title: 'Due now', kind: TaskKind.recurring, intervalDays: 3, dueAt: _now, createdAt: DateTime(2026, 6, 1));
Task _notDue() => Task(id: 'n', title: 'Later', kind: TaskKind.oneOff, dueAt: _now.add(const Duration(days: 40)), createdAt: DateTime(2026, 6, 1));

Future<void> _pump(WidgetTester tester, UserState user, List<Task> tasks) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(InMemoryRepository(user: user, tasks: tasks)),
      nowProvider.overrideWithValue(() => _now),
    ],
    child: const MaterialApp(home: HomeRouter()),
  ));
  await tester.pump(); // let the streams emit
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a due task routes to DailyScreen', (tester) async {
    await _pump(tester, _user(), [_due()]);
    expect(find.byType(DailyScreen), findsOneWidget);
  });

  testWidgets('no tasks routes to EmptyPoolScreen', (tester) async {
    await _pump(tester, _user(), []);
    expect(find.byType(EmptyPoolScreen), findsOneWidget);
  });

  testWidgets('tasks but none due routes to ClearedScreen', (tester) async {
    await _pump(tester, _user(), [_notDue()]);
    expect(find.byType(ClearedScreen), findsOneWidget);
  });

  testWidgets('target met (not dismissed) routes to TargetHitScreen', (tester) async {
    await _pump(tester, _user(target: 1, done: 1), [_due()]);
    expect(find.byType(TargetHitScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/home_router_test.dart`
Expected: FAIL — `home_router.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/ui/home_router.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/daily_controller.dart';
import '../app/providers.dart';
import '../domain/routing.dart';
import '../domain/selection.dart';
import '../theme/palette.dart';
import 'cleared_screen.dart';
import 'daily_screen.dart';
import 'empty_pool_screen.dart';
import 'placeholder_screen.dart';
import 'target_hit_screen.dart';

/// Derives the current screen purely from routeHome and renders it.
class HomeRouter extends ConsumerWidget {
  const HomeRouter({super.key});

  void _open(BuildContext context, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceholderScreen(title: title)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final now = ref.watch(nowProvider)();

    final user = userAsync.valueOrNull;
    final tasks = tasksAsync.valueOrNull;
    if (user == null || tasks == null) {
      return const ColoredBox(color: Palette.paper, child: SizedBox.expand());
    }

    final screen = routeHome(user, tasks, now);
    final child = switch (screen) {
      AppScreen.daily => DailyScreen(user: user, task: selectTask(tasks, now)!),
      AppScreen.cleared => ClearedScreen(onReviewPool: () => _open(context, 'Manage')),
      AppScreen.emptyPool => EmptyPoolScreen(onAdd: () => _open(context, 'Add')),
      AppScreen.targetHit =>
        TargetHitScreen(user: user, onKeepGoing: () => ref.read(dailyControllerProvider).keepGoing(user)),
      // welcome/onboard*/add/manage/settings/stats are not reachable from the
      // Phase-2 home loop (auth + those screens arrive later).
      _ => const ColoredBox(color: Palette.paper, child: SizedBox.expand()),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child);
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/home_router_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home_router.dart test/ui/home_router_test.dart
git commit -m "feat(ui): add HomeRouter deriving screen from routeHome"
```

---

### Task 14: App entry — main.dart + ToastOverlay

**Files:**
- Modify: `lib/main.dart` (replace the counter app)
- Delete/replace: `test/widget_test.dart` → `test/app_smoke_test.dart`
- Test: `test/app_smoke_test.dart`

**Interfaces:**
- Consumes: `buildAppTheme()` (`lib/theme/app_theme.dart`), `HomeRouter`, `ToastOverlay`.
- Produces: `void main()` → `runApp(const ProviderScope(child: JustOneApp()))`; `class JustOneApp extends StatelessWidget` → `MaterialApp(theme: buildAppTheme(), home: Stack(children: [HomeRouter(), ToastOverlay()]))` (ToastOverlay stacked above the router so toasts float over every screen).

- [ ] **Step 1: Write the failing test**

`test/app_smoke_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/main.dart';
import 'package:justone/ui/home_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('app boots into the home router on the seeded daily loop', (tester) async {
    await tester.pumpWidget(const ProviderScopedApp());
    await tester.pump();
    expect(find.byType(HomeRouter), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget); // seeded pool opens on daily
  });
}
```

(Expose a small `ProviderScopedApp` wrapper in `main.dart` so the test can pump the whole app, scope included.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/app_smoke_test.dart`
Expected: FAIL — `main.dart` still defines the counter app / no `ProviderScopedApp`.

- [ ] **Step 3: Write the implementation**

Replace `lib/main.dart` entirely:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'ui/home_router.dart';
import 'ui/toast.dart';

void main() => runApp(const ProviderScopedApp());

/// Whole app incl. the Riverpod scope, so widget tests can pump it directly.
class ProviderScopedApp extends StatelessWidget {
  const ProviderScopedApp({super.key});

  @override
  Widget build(BuildContext context) => const ProviderScope(child: JustOneApp());
}

class JustOneApp extends StatelessWidget {
  const JustOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Just One',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const Stack(
        children: [
          Positioned.fill(child: HomeRouter()),
          ToastOverlay(),
        ],
      ),
    );
  }
}
```

Then delete the old counter test:
```bash
git rm test/widget_test.dart
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `flutter test test/app_smoke_test.dart`
Expected: PASS. Then run the whole suite:
Run: `flutter test`
Expected: PASS (all Phase-1 + Phase-2 tests green).

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart test/app_smoke_test.dart
git commit -m "feat(app): boot JustOne into the daily loop with toasts"
```

---

## Self-Review notes (author)

- **Spec coverage:** seam (T1) · providers/clock (T2) · toasts (T3,T6) · actions + reroll guard (T4) · placeholders (T5) · emptyPool/cleared/targetHit (T7–T9) · card visuals + halo + hints (T10) · gestures incl. denied-skip + long-press (T11) · chrome + FAB + nav (T12) · pure routeHome routing (T13) · app entry + toast overlay (T14). All §A–§G + global constraints map to a task.
- **`now` discipline:** UI obtains `now` only via `nowProvider`; domain calls receive it as a parameter. No `DateTime.now()` in widgets except inside `InMemoryRepository.seeded()` (data layer, manual-run seed only).
- **No-counter rule:** the card test asserts no "due/overdue" text; only `targetHit` shows the streak number.
- **Type consistency:** `SwipeCard` callback set (`onComplete/onSkip/onSkipDenied/onRemove` + `canSkip`) is identical in T10, T11, T12. `DailyController` method names match their call sites in `DailyScreen`/`HomeRouter`. `routeHome`/`selectTask`/`urgencyOf` signatures match Phase-1.
- **Deferred (not in any task, by design):** auth/welcome/onboarding, daily-reset trigger, Firestore, real manage/stats/add/settings/stats bodies, the long-press progress-ring + exact 1100ms hold (uses Flutter's default long-press; tuning deferred).
