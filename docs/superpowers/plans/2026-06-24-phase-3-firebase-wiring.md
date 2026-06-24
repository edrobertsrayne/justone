# Phase 3 — Firebase Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `InMemoryRepository` with a Firestore-backed implementation behind the existing `Repository` seam, gated by mandatory Google Sign-In, with a client-authoritative daily reset and owner-isolation security rules — reusing the entire Phase-2 UI unchanged.

**Architecture:** A new `FirestoreRepository` implements the unchanged 3-method `Repository` seam; `repositoryProvider` is rebuilt from the signed-in uid so the whole data layer swaps behind one provider. Auth, bootstrap, and the lifecycle reset are thin Riverpod-wired units around the pure Phase-1 domain (which is never modified). All Firebase-facing code is tested in plain `flutter test` via in-memory Dart fakes — no device, no emulator.

**Tech Stack:** Flutter, flutter_riverpod 3.3.2 (manual providers, no codegen), firebase_core 4.11.0, firebase_auth 6.5.4, cloud_firestore 6.6.0, google_sign_in 7.2.0, flutter_timezone 5.1.0; dev: fake_cloud_firestore 4.1.1, firebase_auth_mocks 0.15.2.

**Spec:** `docs/superpowers/specs/2026-06-24-phase-3-firebase-wiring-design.md`.

## Global Constraints

Every task implicitly includes these. Exact values are authoritative.

- **No new runtime deps** — all Firebase packages already in `pubspec.yaml`. Add only **dev** deps `fake_cloud_firestore: ^4.1.1` and `firebase_auth_mocks: ^0.15.2`. **No automated test uses a device or emulator.**
- **The `Repository` interface is the only data seam.** No Firebase imports anywhere in `lib/` outside `lib/data/firestore_*.dart`, `lib/auth/`, `lib/app/providers.dart`, and `lib/main.dart`. Domain, UI, and the Phase-2 controllers must not learn Firestore exists.
- **`now` always via `nowProvider`** (the `Clock` seam) — never `DateTime.now()` in domain, controllers, or the reset trigger.
- **The pure domain (`lib/domain/`) is never modified.** Serialization, D9 increment diffing, and validation live in the data layer.
- **Google Sign-In only, mandatory (D8).** No anonymous/email auth this phase.
- **Owner-isolation only for rules (D12).** No field/schema/transition validation in rules.
- **Firestore field names are canonical** (spec §"Consolidated Firestore data model"): `kind` ∈ `'one-off'|'recurring'`; `status` ∈ `'active'|'benched'|'archived'|'removed'`; `lastActiveDate` is a `'YYYY-MM-DD'` **string** on the wire; `reminders` is `{weekday:[...], weekend:[...]}`. `urg`/`meta`/`screen` are never persisted.
- **Reminder defaults:** `weekday: ['08:00','18:30','21:00']`, `weekend: ['10:00','20:00']`.
- **`google_sign_in` 7.x is instance-based:** `GoogleSignIn.instance.initialize()` then `authenticate()`; idToken via `account.authentication.idToken`; cancel is `GoogleSignInException` with `code == GoogleSignInExceptionCode.canceled`.
- **riverpod 3.3.2:** use `AsyncValue.value` (nullable) — `valueOrNull` does not exist. When awaiting a `StreamProvider.future` in a unit test with no widget tree, first establish a listener (`container.listen(p, (_, __) {})`, closed in `addTearDown`) or the provider auto-disposes mid-load (CLAUDE.md learning).

---

## Task 1: Dev deps + `Repository.dispose()` seam

**Files:**
- Modify: `pubspec.yaml` (add two dev deps)
- Modify: `lib/data/repository.dart`
- Modify: `lib/data/in_memory_repository.dart`
- Test: `test/data/in_memory_repository_test.dart` (add a case)

**Interfaces:**
- Produces: `abstract class Repository { Stream<UserState> watchUser(); Stream<List<Task>> watchTasks(); Future<void> commit(TransitionResult); void dispose(); }`
- Produces: `InMemoryRepository.dispose()` closes its two `StreamController`s.

- [ ] **Step 1: Add dev dependencies**

Run: `flutter pub add --dev fake_cloud_firestore:^4.1.1 firebase_auth_mocks:^0.15.2`
Expected: `pubspec.yaml` gains both under `dev_dependencies`; `flutter pub get` resolves (`fake_cloud_firestore 4.1.1`, `firebase_auth_mocks 0.15.2`).

- [ ] **Step 2: Write the failing test**

Add to `test/data/in_memory_repository_test.dart` (inside `main()`):

```dart
  test('dispose closes the controllers so further commits throw', () async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23)),
      tasks: const [],
    );
    repo.watchUser().listen((_) {});
    repo.watchTasks().listen((_) {});
    repo.dispose();
    expect(
      () => repo.commit(TransitionResult(
        user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
        changedTasks: const [],
      )),
      throwsStateError,
    );
  });
```

Ensure the imports at the top of the file include `package:justone/domain/transitions.dart` and `package:justone/domain/user_state.dart` (add any missing).

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/in_memory_repository_test.dart`
Expected: FAIL — `dispose` is not defined on `InMemoryRepository`.

- [ ] **Step 4: Add `dispose()` to the seam and the fake**

In `lib/data/repository.dart`, add to the abstract class (after `commit`):

```dart
  /// Release resources (Firestore listeners / stream controllers). Called when
  /// the repository is replaced (e.g. sign-out) or the app shuts down.
  void dispose();
```

In `lib/data/in_memory_repository.dart`, add this method to the class (after `commit`):

```dart
  @override
  void dispose() {
    _userCtrl.close();
    _tasksCtrl.close();
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/in_memory_repository_test.dart`
Expected: PASS (all cases).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/repository.dart lib/data/in_memory_repository.dart test/data/in_memory_repository_test.dart
git commit -m "feat(data): add Repository.dispose seam + dev test fakes"
```

---

## Task 2: Firestore mappers — Task ↔ doc

**Files:**
- Create: `lib/data/firestore_mappers.dart`
- Test: `test/data/firestore_mappers_test.dart`

**Interfaces:**
- Produces: `Map<String, dynamic> taskToFirestore(Task t)`
- Produces: `Task taskFromFirestore(String id, Map<String, dynamic> data)` — throws `FormatException` on bad enum or invariant violation.

- [ ] **Step 1: Write the failing test**

Create `test/data/firestore_mappers_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/domain/task.dart';

void main() {
  test('round-trips a recurring task', () {
    final t = Task(
      id: 't1',
      title: 'Water plants',
      kind: TaskKind.recurring,
      intervalDays: 3,
      dueAt: DateTime(2026, 6, 24),
      createdAt: DateTime(2026, 6, 1),
      status: TaskStatus.benched,
    );
    final doc = taskToFirestore(t);
    expect(doc['kind'], 'recurring');
    expect(doc['status'], 'benched');
    expect(doc['dueAt'], isA<Timestamp>());
    expect(taskFromFirestore('t1', doc), t);
  });

  test('round-trips a one-off task with null dates', () {
    final t = Task(id: 't2', title: 'Back up', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 3));
    final doc = taskToFirestore(t);
    expect(doc['kind'], 'one-off');
    expect(doc['intervalDays'], isNull);
    expect(doc['dueAt'], isNull);
    expect(taskFromFirestore('t2', doc), t);
  });

  test('throws on a bad kind string', () {
    expect(
      () => taskFromFirestore('x', {'title': 'a', 'kind': 'weekly', 'status': 'active', 'createdAt': Timestamp.fromDate(DateTime(2026))}),
      throwsFormatException,
    );
  });

  test('throws when recurring lacks a positive intervalDays', () {
    expect(
      () => taskFromFirestore('x', {'title': 'a', 'kind': 'recurring', 'status': 'active', 'intervalDays': 0, 'createdAt': Timestamp.fromDate(DateTime(2026))}),
      throwsFormatException,
    );
  });

  test('throws when a one-off carries intervalDays', () {
    expect(
      () => taskFromFirestore('x', {'title': 'a', 'kind': 'one-off', 'status': 'active', 'intervalDays': 5, 'createdAt': Timestamp.fromDate(DateTime(2026))}),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/firestore_mappers_test.dart`
Expected: FAIL — `firestore_mappers.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/data/firestore_mappers.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/firestore_mappers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/firestore_mappers.dart test/data/firestore_mappers_test.dart
git commit -m "feat(data): add Task<->Firestore mappers with defensive validation"
```

---

## Task 3: Firestore mappers — UserState ↔ doc

**Files:**
- Modify: `lib/data/firestore_mappers.dart` (append user mappers)
- Test: `test/data/firestore_mappers_test.dart` (append cases)

**Interfaces:**
- Produces: `Map<String, dynamic> userToFirestore(UserState u)`
- Produces: `UserState userFromFirestore(Map<String, dynamic> data)`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/data/firestore_mappers_test.dart` (and add the import `import 'package:justone/domain/user_state.dart';` at the top):

```dart
  test('round-trips a user with reminders and a date string', () {
    final u = UserState(
      timezone: 'Europe/London',
      target: 4,
      remindersWeekday: const ['08:00', '18:30'],
      remindersWeekend: const ['10:00'],
      onboardingComplete: true,
      streak: 5,
      bestStreak: 9,
      targetMetDays: 12,
      lifetimeDone: 40,
      bankedToday: true,
      doneToday: 2,
      rerolls: 1,
      lastActiveDate: DateTime(2026, 6, 24),
    );
    final doc = userToFirestore(u);
    expect(doc['lastActiveDate'], '2026-06-24');
    expect(doc['reminders'], {'weekday': ['08:00', '18:30'], 'weekend': ['10:00']});
    expect(userFromFirestore(doc), u);
  });

  test('userFromFirestore zero-pads and parses the date string', () {
    final u = userFromFirestore(userToFirestore(
      UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 1, 5)),
    ));
    expect(u.lastActiveDate, DateTime(2026, 1, 5));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/firestore_mappers_test.dart`
Expected: FAIL — `userToFirestore`/`userFromFirestore` not defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/data/firestore_mappers.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/firestore_mappers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/firestore_mappers.dart test/data/firestore_mappers_test.dart
git commit -m "feat(data): add UserState<->Firestore mappers"
```

---

## Task 4: FirestoreRepository — streams + batch commit

**Files:**
- Create: `lib/data/firestore_repository.dart`
- Test: `test/data/firestore_repository_test.dart`

**Interfaces:**
- Consumes: `taskToFirestore`/`taskFromFirestore`/`userToFirestore`/`userFromFirestore` (Tasks 2-3); `Repository` seam (Task 1); `TransitionResult` (domain).
- Produces: `class FirestoreRepository implements Repository { FirestoreRepository(FirebaseFirestore db, String uid); ... }` — caches the last emitted `UserState` in `_lastUser` for Task 5.

> **Implementation note (read before coding):** `watchUser`/`watchTasks` return Firestore's own `snapshots()` streams transformed with `.map`. The listening `StreamProvider` owns the subscription and cancels it when `repositoryProvider` is disposed (sign-out), so `dispose()` here is an intentional **no-op** (documented in code). This is the idiomatic Riverpod+Firestore lifecycle; it is not a defect.

- [ ] **Step 1: Write the failing test**

Create `test/data/firestore_repository_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/data/firestore_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/transitions.dart';
import 'package:justone/domain/user_state.dart';

UserState _user() => UserState(timezone: 'UTC', streak: 3, lifetimeDone: 10, lastActiveDate: DateTime(2026, 6, 24));
Task _task() => Task(id: 't1', title: 'A', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

void main() {
  test('watchUser maps the user doc', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(_user()));
    final repo = FirestoreRepository(db, 'u1');
    expect((await repo.watchUser().first).streak, 3);
  });

  test('watchTasks maps docs and filters archived/removed', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users/u1/tasks').doc('t1').set(taskToFirestore(_task()));
    await db.collection('users/u1/tasks').doc('t2').set(
        taskToFirestore(_task().copyWith(id: 't2', status: TaskStatus.archived)));
    final repo = FirestoreRepository(db, 'u1');
    final tasks = await repo.watchTasks().first;
    expect(tasks.map((t) => t.id), ['t1']);
  });

  test('commit writes changed task + user in one batch', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(_user()));
    await db.collection('users/u1/tasks').doc('t1').set(taskToFirestore(_task()));
    final repo = FirestoreRepository(db, 'u1');
    await repo.commit(TransitionResult(
      user: _user().copyWith(doneToday: 1),
      changedTasks: [_task().copyWith(status: TaskStatus.archived, completedAt: DateTime(2026, 6, 24))],
    ));
    expect((await db.doc('users/u1').get()).data()!['doneToday'], 1);
    expect((await db.doc('users/u1/tasks/t1').get()).data()!['status'], 'archived');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/firestore_repository_test.dart`
Expected: FAIL — `firestore_repository.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/data/firestore_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/task.dart';
import '../domain/transitions.dart';
import '../domain/user_state.dart';
import 'firestore_mappers.dart';
import 'repository.dart';

/// Firestore-backed [Repository] for a single signed-in user (Phase 3).
class FirestoreRepository implements Repository {
  FirestoreRepository(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  /// Last user value emitted from [watchUser]; the base for D9 increment deltas.
  UserState? _lastUser;

  DocumentReference<Map<String, dynamic>> get _userRef => _db.doc('users/$_uid');
  CollectionReference<Map<String, dynamic>> get _tasksRef => _db.collection('users/$_uid/tasks');

  @override
  Stream<UserState> watchUser() => _userRef.snapshots().where((s) => s.data() != null).map((snap) {
        final user = userFromFirestore(snap.data()!);
        _lastUser = user;
        return user;
      });

  @override
  Stream<List<Task>> watchTasks() => _tasksRef.snapshots().map((q) => q.docs
      .map((d) => taskFromFirestore(d.id, d.data()))
      .where((t) => t.status == TaskStatus.active || t.status == TaskStatus.benched)
      .toList());

  @override
  Future<void> commit(TransitionResult result) async {
    final batch = _db.batch();
    for (final task in result.changedTasks) {
      batch.set(_tasksRef.doc(task.id), taskToFirestore(task));
    }
    batch.set(_userRef, userToFirestore(result.user), SetOptions(merge: true));
    await batch.commit();
  }

  @override
  void dispose() {
    // No-op: watchUser/watchTasks return Firestore snapshot streams directly; the
    // listening StreamProviders cancel their subscriptions when repositoryProvider is
    // disposed (sign-out / account-switch). Present to satisfy the Repository seam,
    // which InMemoryRepository needs to close its StreamControllers.
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/firestore_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/firestore_repository.dart test/data/firestore_repository_test.dart
git commit -m "feat(data): add FirestoreRepository streams + batch commit"
```

---

## Task 5: FirestoreRepository — D9 increment diffing on commit

**Files:**
- Modify: `lib/data/firestore_repository.dart` (`commit`)
- Test: `test/data/firestore_repository_test.dart` (add a case)

**Interfaces:**
- Consumes/Produces: same `FirestoreRepository.commit` signature; now writes `lifetimeDone`/`targetMetDays` as `FieldValue.increment(delta)` where `delta = result.user.X - (_lastUser?.X ?? 0)`.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/data/firestore_repository_test.dart`:

```dart
  test('lifetimeDone is written as a server-relative increment, not absolute', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(_user())); // lifetimeDone: 10
    final repo = FirestoreRepository(db, 'u1');
    final sub = repo.watchUser().listen((_) {});
    await Future<void>.delayed(Duration.zero); // primes _lastUser at lifetimeDone 10
    await sub.cancel(); // freeze the base at 10 so the concurrent bump below is not tracked
    // Simulate another device bumping the server value to 100.
    await db.doc('users/u1').set({'lifetimeDone': 100}, SetOptions(merge: true));
    // Our commit computes delta from base(10) -> new(11) == +1.
    await repo.commit(TransitionResult(user: _user().copyWith(lifetimeDone: 11), changedTasks: const []));
    // increment(1) applied on top of 100 -> 101 (absolute would have written 11).
    expect((await db.doc('users/u1').get()).data()!['lifetimeDone'], 101);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/firestore_repository_test.dart`
Expected: FAIL — current `commit` writes `lifetimeDone` absolutely (result is 11, not 101).

- [ ] **Step 3: Update `commit`**

Replace the `commit` method body in `lib/data/firestore_repository.dart` with:

```dart
  @override
  Future<void> commit(TransitionResult result) async {
    final batch = _db.batch();
    for (final task in result.changedTasks) {
      batch.set(_tasksRef.doc(task.id), taskToFirestore(task));
    }
    // All user fields are absolute last-write-wins (D9) except the two additive
    // lifetime tallies, which use server-relative increments to survive the rare
    // two-devices-offline-same-day race.
    final base = _lastUser;
    final data = userToFirestore(result.user)
      ..remove('lifetimeDone')
      ..remove('targetMetDays');
    batch.set(_userRef, data, SetOptions(merge: true));
    batch.set(
      _userRef,
      {
        'lifetimeDone': FieldValue.increment(result.user.lifetimeDone - (base?.lifetimeDone ?? 0)),
        'targetMetDays': FieldValue.increment(result.user.targetMetDays - (base?.targetMetDays ?? 0)),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/firestore_repository_test.dart`
Expected: PASS (all cases, including the earlier `commit writes ... in one batch`).

- [ ] **Step 5: Commit**

```bash
git add lib/data/firestore_repository.dart test/data/firestore_repository_test.dart
git commit -m "feat(data): write D9 lifetime counters as Firestore increments"
```

---

## Task 6: Firebase instance providers + auth service + authProvider

**Files:**
- Create: `lib/auth/auth_service.dart`
- Create: `lib/auth/auth_providers.dart`
- Test: `test/auth/auth_providers_test.dart`

**Interfaces:**
- Produces: `firebaseAuthProvider = Provider<FirebaseAuth>`, `firestoreProvider = Provider<FirebaseFirestore>`, `authServiceProvider = Provider<AuthService>`, `authProvider = StreamProvider<User?>`.
- Produces: `abstract class AuthService { Future<void> signInWithGoogle(); Future<void> signOut(); }` and `class FirebaseAuthService implements AuthService`.

- [ ] **Step 1: Write the failing test**

Create `test/auth/auth_providers_test.dart`:

```dart
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/auth/auth_providers.dart';

void main() {
  test('authProvider emits the signed-in user from FirebaseAuth', () async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final container = ProviderContainer(overrides: [firebaseAuthProvider.overrideWithValue(auth)]);
    addTearDown(container.dispose);
    addTearDown(container.listen(authProvider, (_, __) {}).close);
    expect((await container.read(authProvider.future))?.uid, 'u1');
  });

  test('authProvider emits null when signed out', () async {
    final auth = MockFirebaseAuth(); // signed out
    final container = ProviderContainer(overrides: [firebaseAuthProvider.overrideWithValue(auth)]);
    addTearDown(container.dispose);
    addTearDown(container.listen(authProvider, (_, __) {}).close);
    expect(await container.read(authProvider.future), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/auth/auth_providers_test.dart`
Expected: FAIL — `auth_providers.dart` does not exist.

- [ ] **Step 3: Write the auth service**

Create `lib/auth/auth_service.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The auth boundary: Google Sign-In + Firebase credential exchange (D8).
abstract class AuthService {
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;
  bool _initialized = false;

  @override
  Future<void> signInWithGoogle() async {
    if (!_initialized) {
      await GoogleSignIn.instance.initialize();
      _initialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate(); // throws GoogleSignInException on cancel/error
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await _auth.signInWithCredential(credential);
  }

  @override
  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}
```

- [ ] **Step 4: Write the providers**

Create `lib/auth/auth_providers.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

/// Firebase singletons behind providers so tests can inject fakes.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final authServiceProvider =
    Provider<AuthService>((ref) => FirebaseAuthService(ref.watch(firebaseAuthProvider)));

/// The current signed-in user, or null. Drives the AuthGate.
final authProvider =
    StreamProvider<User?>((ref) => ref.watch(firebaseAuthProvider).authStateChanges());
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/auth/auth_providers_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/auth/auth_service.dart lib/auth/auth_providers.dart test/auth/auth_providers_test.dart
git commit -m "feat(auth): add Firebase instance providers, AuthService, authProvider"
```

---

## Task 7: Bootstrap — `ensureUserDoc` + `bootstrapProvider` (D13)

**Files:**
- Create: `lib/auth/bootstrap.dart`
- Test: `test/auth/bootstrap_test.dart`

**Interfaces:**
- Consumes: `userToFirestore` (Task 3); `firestoreProvider`/`authProvider` (Task 6); `nowProvider` (existing).
- Produces: `Future<void> ensureUserDoc(FirebaseFirestore db, String uid, {required DateTime now, required String timezone})` and `bootstrapProvider = FutureProvider<void>`.

- [ ] **Step 1: Write the failing test**

Create `test/auth/bootstrap_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/auth/bootstrap.dart';

void main() {
  test('creates a default user doc when missing', () async {
    final db = FakeFirebaseFirestore();
    await ensureUserDoc(db, 'u1', now: DateTime(2026, 6, 24, 9), timezone: 'Europe/London');
    final data = (await db.doc('users/u1').get()).data()!;
    expect(data['onboardingComplete'], false);
    expect(data['timezone'], 'Europe/London');
    expect(data['target'], 3);
    expect(data['rerolls'], 3);
    expect(data['lifetimeDone'], 0);
    expect(data['lastActiveDate'], '2026-06-24');
    expect(data['reminders'], {'weekday': ['08:00', '18:30', '21:00'], 'weekend': ['10:00', '20:00']});
  });

  test('only refreshes timezone when the doc already exists', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set({
      'timezone': 'UTC', 'target': 5, 'streak': 7, 'lifetimeDone': 99,
      'reminders': {'weekday': <String>[], 'weekend': <String>[]},
      'onboardingComplete': true, 'lastActiveDate': '2026-06-20',
    });
    await ensureUserDoc(db, 'u1', now: DateTime(2026, 6, 24), timezone: 'Asia/Tokyo');
    final data = (await db.doc('users/u1').get()).data()!;
    expect(data['timezone'], 'Asia/Tokyo'); // refreshed
    expect(data['streak'], 7); // untouched
    expect(data['lifetimeDone'], 99); // untouched
    expect(data['target'], 5); // untouched
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/auth/bootstrap_test.dart`
Expected: FAIL — `bootstrap.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/auth/bootstrap.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../app/providers.dart';
import '../data/firestore_mappers.dart';
import '../domain/user_state.dart';
import 'auth_providers.dart';

/// First-run bootstrap (D13): create `users/{uid}` with defaults if missing,
/// otherwise just refresh the timezone (D2). Idempotent.
Future<void> ensureUserDoc(
  FirebaseFirestore db,
  String uid, {
  required DateTime now,
  required String timezone,
}) async {
  final ref = db.doc('users/$uid');
  final snap = await ref.get();
  if (!snap.exists) {
    final defaults = UserState(
      timezone: timezone,
      target: 3,
      remindersWeekday: const ['08:00', '18:30', '21:00'],
      remindersWeekend: const ['10:00', '20:00'],
      onboardingComplete: false,
      lastActiveDate: DateTime(now.year, now.month, now.day),
    );
    await ref.set(userToFirestore(defaults));
  } else {
    await ref.set({'timezone': timezone}, SetOptions(merge: true));
  }
}

/// Runs [ensureUserDoc] for the signed-in user; the AuthGate awaits this before
/// rendering the app, so the UI never renders against a missing doc.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(authProvider).value?.uid;
  if (uid == null) return;
  final db = ref.watch(firestoreProvider);
  final now = ref.watch(nowProvider)();
  final tz = (await FlutterTimezone.getLocalTimezone()).identifier;
  await ensureUserDoc(db, uid, now: now, timezone: tz);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/auth/bootstrap_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/auth/bootstrap.dart test/auth/bootstrap_test.dart
git commit -m "feat(auth): add users/{uid} bootstrap (D13)"
```

---

## Task 8: Daily-reset trigger — `DailyResetScope` (D22)

**Files:**
- Create: `lib/app/daily_reset_scope.dart`
- Test: `test/app/daily_reset_scope_test.dart`

**Interfaces:**
- Consumes: `userProvider`/`tasksProvider`/`nowProvider`/`repositoryProvider` (existing); `dailyReset` (domain); `daysBetweenLocalDates` (`lib/domain/urgency.dart`).
- Produces: `class DailyResetScope extends ConsumerStatefulWidget { const DailyResetScope({super.key, required Widget child}); }`.

- [ ] **Step 1: Write the failing test**

Create `test/app/daily_reset_scope_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/daily_reset_scope.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';

ProviderContainer _containerWith(DateTime now, UserState user, List<Task> tasks) {
  final repo = InMemoryRepository(user: user, tasks: tasks);
  final c = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    nowProvider.overrideWithValue(() => now),
  ]);
  return c;
}

void main() {
  testWidgets('commits a reset when the local day has advanced', (tester) async {
    final container = _containerWith(
      DateTime(2026, 6, 24, 9),
      UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), doneToday: 2, bankedToday: true, streak: 5),
      [Task(id: 'b', title: 'B', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1), status: TaskStatus.benched)],
    );
    addTearDown(container.dispose);
    addTearDown(container.listen(userProvider, (_, __) {}).close);
    addTearDown(container.listen(tasksProvider, (_, __) {}).close);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DailyResetScope(child: SizedBox())),
    ));
    await tester.pumpAndSettle();

    final user = container.read(userProvider).requireValue;
    expect(user.doneToday, 0); // reset
    expect(user.lastActiveDate, DateTime(2026, 6, 24));
    final tasks = container.read(tasksProvider).requireValue;
    expect(tasks.single.status, TaskStatus.active); // un-benched
  });

  testWidgets('does nothing on the same local day', (tester) async {
    final container = _containerWith(
      DateTime(2026, 6, 24, 9),
      UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24), doneToday: 2),
      const [],
    );
    addTearDown(container.dispose);
    addTearDown(container.listen(userProvider, (_, __) {}).close);
    addTearDown(container.listen(tasksProvider, (_, __) {}).close);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DailyResetScope(child: SizedBox())),
    ));
    await tester.pumpAndSettle();

    expect(container.read(userProvider).requireValue.doneToday, 2); // untouched
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app/daily_reset_scope_test.dart`
Expected: FAIL — `daily_reset_scope.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/app/daily_reset_scope.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/transitions.dart';
import '../domain/urgency.dart' show daysBetweenLocalDates;
import 'providers.dart';

/// Runs the client-authoritative daily reset (D7) on cold start and every
/// resume-to-foreground (D22). Idempotent: a no-op when the local day is unchanged.
class DailyResetScope extends ConsumerStatefulWidget {
  const DailyResetScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DailyResetScope> createState() => _DailyResetScopeState();
}

class _DailyResetScopeState extends ConsumerState<DailyResetScope> with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-check whenever the user or task stream first delivers (or updates).
    ref.listenManual(userProvider, (_, __) => _maybeReset());
    ref.listenManual(tasksProvider, (_, __) => _maybeReset());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeReset());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeReset();
  }

  Future<void> _maybeReset() async {
    if (_busy) return;
    final user = ref.read(userProvider).value;
    final tasks = ref.read(tasksProvider).value;
    if (user == null || tasks == null) return;
    final now = ref.read(nowProvider)();
    if (daysBetweenLocalDates(user.lastActiveDate, now) == 0) return;
    _busy = true;
    try {
      await ref.read(repositoryProvider).commit(dailyReset(user, tasks, now));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app/daily_reset_scope_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/daily_reset_scope.dart test/app/daily_reset_scope_test.dart
git commit -m "feat(app): add DailyResetScope lifecycle reset trigger (D22)"
```

---

## Task 9: SignInScreen

**Files:**
- Create: `lib/ui/sign_in_screen.dart`
- Test: `test/ui/sign_in_screen_test.dart`

**Interfaces:**
- Consumes: `authServiceProvider` (Task 6); `Palette` (`lib/theme/palette.dart`).
- Produces: `class SignInScreen extends ConsumerStatefulWidget { const SignInScreen({super.key}); }`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/sign_in_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/auth_service.dart';
import 'package:justone/ui/sign_in_screen.dart';

class _StubAuthService implements AuthService {
  _StubAuthService(this._onSignIn);
  final Future<void> Function() _onSignIn;
  int calls = 0;
  @override
  Future<void> signInWithGoogle() {
    calls++;
    return _onSignIn();
  }
  @override
  Future<void> signOut() async {}
}

Future<void> _pump(WidgetTester tester, AuthService service) => tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

void main() {
  testWidgets('tapping the button calls signInWithGoogle', (tester) async {
    final service = _StubAuthService(() async {});
    await _pump(tester, service);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
  });

  testWidgets('shows an error and retry on a non-cancel failure', (tester) async {
    final service = _StubAuthService(() async => throw Exception('network'));
    await _pump(tester, service);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('failed'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget); // still retryable
  });

  testWidgets('a user-cancelled sign-in shows no error', (tester) async {
    final service = _StubAuthService(
      () async => throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await _pump(tester, service);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('failed'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/sign_in_screen_test.dart`
Expected: FAIL — `sign_in_screen.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/ui/sign_in_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../auth/auth_providers.dart';
import '../theme/palette.dart';

/// Minimal functional auth gate (D8). Phase 4 replaces this with the designed
/// welcome screen. On success, authStateChanges drives AuthGate forward; this
/// screen does not navigate.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _error = 'Sign-in failed. Please try again.';
      }
    } catch (_) {
      _error = 'Sign-in failed. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Just One', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 48),
            if (_loading)
              const CircularProgressIndicator()
            else
              FilledButton(onPressed: _signIn, child: const Text('Continue with Google')),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Palette.terracotta)),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/sign_in_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/sign_in_screen.dart test/ui/sign_in_screen_test.dart
git commit -m "feat(ui): add minimal Continue-with-Google sign-in screen"
```

---

## Task 10: AuthGate

**Files:**
- Create: `lib/auth/auth_gate.dart`
- Test: `test/auth/auth_gate_test.dart`

**Interfaces:**
- Consumes: `authProvider`/`bootstrapProvider`/`firebaseAuthProvider`/`firestoreProvider` (Tasks 6-7); `repositoryProvider`/`nowProvider` (existing); `SignInScreen` (Task 9); `DailyResetScope` (Task 8); `HomeRouter` (existing); `Palette`.
- Produces: `class AuthGate extends ConsumerWidget { const AuthGate({super.key}); }`.

- [ ] **Step 1: Write the failing test**

Create `test/auth/auth_gate_test.dart`:

```dart
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/auth/auth_gate.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/bootstrap.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/home_router.dart';
import 'package:justone/ui/sign_in_screen.dart';

void main() {
  testWidgets('shows the sign-in screen when signed out', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [firebaseAuthProvider.overrideWithValue(MockFirebaseAuth())],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('shows the home router when signed in and bootstrapped', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 24)),
      tasks: [Task(id: 'a', title: 'A', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 20), createdAt: DateTime(2026, 6, 1))],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => DateTime(2026, 6, 24, 9)),
        bootstrapProvider.overrideWith((ref) async {}), // skip the flutter_timezone plugin call
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeRouter), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/auth/auth_gate_test.dart`
Expected: FAIL — `auth_gate.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/auth/auth_gate.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/daily_reset_scope.dart';
import '../theme/palette.dart';
import '../ui/home_router.dart';
import '../ui/sign_in_screen.dart';
import 'auth_providers.dart';
import 'bootstrap.dart';

/// Top-level gate: signed-out -> SignInScreen; signed-in -> bootstrap -> app.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authProvider).when(
          loading: () => const _Splash(),
          error: (_, __) => const SignInScreen(),
          data: (user) {
            if (user == null) return const SignInScreen();
            return ref.watch(bootstrapProvider).when(
                  loading: () => const _Splash(),
                  // Bootstrap only fails offline on a brand-new account; network is
                  // present right after Google sign-in (spec §C). Show the splash;
                  // it retries when the provider is re-read.
                  error: (_, __) => const _Splash(),
                  data: (_) => const DailyResetScope(child: HomeRouter()),
                );
          },
        );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Palette.paper, child: SizedBox.expand());
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/auth/auth_gate_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/auth/auth_gate.dart test/auth/auth_gate_test.dart
git commit -m "feat(auth): add AuthGate (sign-in -> bootstrap -> app)"
```

---

## Task 11: Final wiring — `main.dart`, `repositoryProvider` swap, smoke test

This is the one task that flips the running app from the seeded in-memory repo to live Firebase. It changes `main.dart`, rewrites `repositoryProvider`, and rewrites the smoke test together so the suite stays green.

**Files:**
- Modify: `lib/app/providers.dart` (`repositoryProvider`, imports)
- Modify: `lib/main.dart`
- Modify: `test/app_smoke_test.dart`

**Interfaces:**
- Consumes: `firestoreProvider`/`authProvider` (Task 6); `FirestoreRepository` (Tasks 4-5); `AuthGate` (Task 10).
- Produces: `repositoryProvider` now builds `FirestoreRepository(firestore, uid)` from the signed-in uid; `main()` initializes Firebase and uses `AuthGate` as home.

- [ ] **Step 1: Rewrite the smoke test (failing)**

Replace the whole body of `test/app_smoke_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/auth/auth_providers.dart';
import 'package:justone/auth/bootstrap.dart';
import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/main.dart';
import 'package:justone/ui/home_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-in app boots into the daily loop via Firestore', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set(userToFirestore(
      UserState(timezone: 'UTC', target: 3, lastActiveDate: DateTime(2026, 6, 24)),
    ));
    await db.collection('users/u1/tasks').doc('t1').set(taskToFirestore(
      Task(id: 't1', title: 'Reply to landlord', kind: TaskKind.oneOff, dueAt: DateTime(2026, 6, 22), createdAt: DateTime(2026, 6, 1)),
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(db),
        nowProvider.overrideWithValue(() => DateTime(2026, 6, 24, 9)),
        bootstrapProvider.overrideWith((ref) async {}),
      ],
      child: const JustOneApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(HomeRouter), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget); // due task -> daily screen
  });
}
```

Add the missing imports the test references: `import 'package:justone/domain/task.dart';` and `import 'package:justone/domain/user_state.dart';`.

- [ ] **Step 2: Run the smoke test to verify it fails**

Run: `flutter test test/app_smoke_test.dart`
Expected: FAIL — `firestoreProvider` is not yet consulted by `repositoryProvider`, and `JustOneApp` still hosts `HomeRouter` directly without auth, so the chain doesn't resolve to a signed-in Firestore-backed daily screen.

- [ ] **Step 3: Rewrite `repositoryProvider`**

In `lib/app/providers.dart`, replace the import block and `repositoryProvider`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../data/firestore_repository.dart';
import '../data/repository.dart';
import '../domain/task.dart';
import '../domain/user_state.dart';

/// A source of "now" — overridable in tests so urgency/routing are deterministic.
typedef Clock = DateTime Function();

/// Firestore-backed repository scoped to the signed-in uid. Rebuilt (and the old
/// one disposed) when auth changes, so sign-out/account-switch swaps the data layer.
final repositoryProvider = Provider<Repository>((ref) {
  final uid = ref.watch(authProvider).value?.uid;
  final repo = FirestoreRepository(ref.watch(firestoreProvider), uid!);
  ref.onDispose(repo.dispose);
  return repo;
});

final userProvider = StreamProvider<UserState>((ref) => ref.watch(repositoryProvider).watchUser());

final tasksProvider =
    StreamProvider<List<Task>>((ref) => ref.watch(repositoryProvider).watchTasks());

final nowProvider = Provider<Clock>((ref) => DateTime.now);
```

(The `InMemoryRepository` import is dropped from this file; the class stays for tests, which override `repositoryProvider` directly. `InMemoryRepository.seeded()` remains for `tool/seed_emulator` in Task 12.)

- [ ] **Step 4: Rewrite `main.dart`**

Replace `lib/main.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_gate.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'ui/toast.dart';

/// Emulator on by default in debug; override for a real-device push test with
/// `--dart-define=USE_EMULATOR=false` (D18).
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: kDebugMode);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kUseEmulator) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  }
  runApp(const ProviderScopedApp());
}

/// Whole app incl. the Riverpod scope, so widget tests can pump [JustOneApp] directly.
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
          Positioned.fill(child: AuthGate()),
          ToastOverlay(),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS — the rewritten smoke test passes and all prior tests stay green (the providers/main changes are covered by provider overrides everywhere).

- [ ] **Step 6: Static analysis**

Run: `flutter analyze`
Expected: No issues. (Remove any now-unused imports the analyzer flags.)

- [ ] **Step 7: Commit**

```bash
git add lib/app/providers.dart lib/main.dart test/app_smoke_test.dart
git commit -m "feat(app): wire Firebase auth + FirestoreRepository as the live data layer"
```

---

## Task 12: Security rules, emulator config, dev seed & manual-check doc

Config, tooling, and documentation — no automated tests (the Dart fakes have no rules engine). Verified by `flutter analyze` and a manual emulator check.

**Files:**
- Modify: `firestore.rules`
- Modify: `firebase.json` (add `emulators` block)
- Create: `tool/seed_emulator.dart`
- Create: `docs/superpowers/phase-3-manual-rules-check.md`

- [ ] **Step 1: Write owner-isolation rules**

Replace `firestore.rules` with:

```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
      match /{document=**} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
    }
  }
}
```

- [ ] **Step 2: Add the emulators block to `firebase.json`**

Add this top-level key to `firebase.json` (alongside `firestore`/`functions`):

```json
  "emulators": {
    "auth": { "port": 9099 },
    "firestore": { "port": 8080 },
    "ui": { "enabled": true },
    "singleProjectMode": true
  }
```

- [ ] **Step 3: Write the dev seed script**

Create `tool/seed_emulator.dart`:

```dart
// Dev-only: seed the Firebase emulator with an onboarded user + sample tasks so
// the daily loop is hand-testable before Phase-4 onboarding exists.
//
// Run with the emulator up:
//   firebase emulators:start
//   flutter run -t tool/seed_emulator.dart -d <device>
//
// It signs in anonymously against the Auth emulator, writes users/{uid} with
// onboardingComplete:true and the InMemoryRepository.seeded() pool, then prints
// the uid. NOT shipped; not referenced from lib/.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);

  final cred = await FirebaseAuth.instance.signInAnonymously();
  final uid = cred.user!.uid;
  final seed = InMemoryRepository.seeded();
  final user = await seed.watchUser().first;
  final tasks = await seed.watchTasks().first;

  final db = FirebaseFirestore.instance;
  await db.doc('users/$uid').set(userToFirestore(user));
  for (final t in tasks) {
    await db.doc('users/$uid/tasks/${t.id}').set(taskToFirestore(t));
  }
  // ignore: avoid_print
  print('Seeded emulator user: $uid (${tasks.length} tasks)');
}
```

- [ ] **Step 4: Write the manual rules-check doc**

Create `docs/superpowers/phase-3-manual-rules-check.md`:

```markdown
# Phase 3 — Manual owner-isolation rules check (D12)

The Dart test fakes have no rules engine, so verify `firestore.rules` by hand
against the emulator whenever the rules change. Expected: a user can read/write
only their own `users/{uid}` tree.

## Steps
1. `firebase emulators:start` (serves Auth :9099, Firestore :8080, UI).
2. Open the Emulator UI → Firestore. Create `users/alice/tasks/t1` and `users/bob/tasks/t1`.
3. In the Auth emulator, add two users; note alice's uid.
4. Using the Rules Playground (Firestore tab → "Rules playground"):
   - **Allowed:** authenticated as alice, `get`/`update` on `users/alice` and
     `users/alice/tasks/t1` → all green.
   - **Denied:** authenticated as alice, `get`/`update` on `users/bob` and
     `users/bob/tasks/t1` → all red (permission denied).
   - **Denied:** unauthenticated, any path → red.
5. If any expectation fails, the rules are wrong — fix and re-run.
```

- [ ] **Step 5: Verify analysis**

Run: `flutter analyze`
Expected: No issues (including `tool/seed_emulator.dart`).

- [ ] **Step 6: Commit**

```bash
git add firestore.rules firebase.json tool/seed_emulator.dart docs/superpowers/phase-3-manual-rules-check.md
git commit -m "feat(security): owner-isolation rules + emulator config, seed & manual check"
```

---

## Final verification (after all tasks)

- [ ] `flutter test` — full suite green (78 prior + new VM tests).
- [ ] `flutter analyze` — clean.
- [ ] **Manual smoke (one-time, before declaring Phase 3 done):** `firebase emulators:start`, seed with `tool/seed_emulator.dart`, `flutter run` on a device with `--dart-define=USE_EMULATOR=true` (default in debug); sign in, confirm the daily card, complete/skip/remove a task and confirm the writes land in the Emulator UI; background past local midnight (or set the device clock forward) and confirm the reset fires on resume.
- [ ] Run the manual rules check in `docs/superpowers/phase-3-manual-rules-check.md`.
- [ ] Use superpowers:finishing-a-development-branch to complete the branch.
