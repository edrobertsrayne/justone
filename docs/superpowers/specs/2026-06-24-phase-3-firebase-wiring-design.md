# Phase 3 — Firebase Wiring (Design Spec)

**Status:** Locked (brainstormed 2026-06-24).
**Goal:** Replace `InMemoryRepository` with a Firestore-backed implementation behind the
existing `Repository` seam, gated by mandatory Google Sign-In, with a client-authoritative
daily reset and owner-isolation security rules. The entire Phase-2 UI is reused unchanged.

This spec implements roadmap Phase 3 and backend decisions **D2, D7, D8, D9, D10, D11, D12,
D13, D18, D22**. The product spec (`docs/design/HANDOFF.md`) and backend decisions
(`docs/design/backend-decisions.md`) are locked; this spec records *how Phase 3 wires them up*.

---

## Global Constraints

These bind every task. Exact values are authoritative.

- **No new runtime dependencies.** All Firebase packages are already in `pubspec.yaml`:
  `firebase_core ^4.11.0`, `firebase_auth ^6.5.4`, `cloud_firestore ^6.6.0`,
  `google_sign_in ^7.2.0`, `flutter_riverpod ^3.3.2`, `flutter_timezone ^5.1.0`. Two **dev**
  dependencies are added for VM testing: `fake_cloud_firestore` and `firebase_auth_mocks` —
  pin to versions compatible with `cloud_firestore 6.6.0` / `firebase_auth 6.5.4` (verify at
  plan time, like the `google_sign_in` surface). **No device/emulator is used by any automated
  test.**
- **The `Repository` interface is the only seam.** No Firebase imports anywhere in `lib/`
  outside `lib/data/firestore_*.dart`, `lib/auth/`, and `lib/main.dart`. Domain, UI, and the
  Phase-2 controllers must not learn that Firestore exists.
- **`now` always via `nowProvider`** (the `Clock` seam) — never `DateTime.now()` in domain,
  controllers, or the reset trigger.
- **The pure domain is never modified to suit Firestore.** Serialization, the D9 increment
  diffing, and validation live in the data layer, not in `lib/domain/`.
- **Google Sign-In only, mandatory (D8).** No anonymous auth, no email/password in this phase.
- **Owner-isolation only for rules (D12).** No field/schema/transition validation in rules.
- **Develop against the Firebase Emulator Suite (D18)** for *running the app by hand* and the
  one-time manual rules check — never against `just-one-db69c` prod with real data. Emulator
  wiring is compile-time gated and on by default in debug. Automated tests use Dart fakes, not
  the emulator.
- **`google_sign_in` 7.x is instance-based** (`GoogleSignIn.instance` + `authenticate()`),
  *not* the old `GoogleSignIn().signIn()`. Pin code to 7.2.0's surface (see §B).
- **Firestore field names are canonical** per the data model in `backend-decisions.md`
  (§"Consolidated Firestore data model"). `lastActiveDate` is a `'YYYY-MM-DD'` **string** on the
  wire; `urg`/`meta`/`screen` are **never** persisted (D6).

---

## A. Firebase init & emulator wiring — `lib/main.dart`

`main()` becomes `async`:

```dart
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
if (kUseEmulator) {
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
}
runApp(const ProviderScopedApp());
```

- `const kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: kDebugMode)` —
  emulator on by default in debug, overridable for a real-device push test (D18).
- On the Android emulator, `localhost` reaches the host loopback via the emulator's managed
  network; the run instructions document the `10.0.2.2` alternative if needed.
- `JustOneApp`'s `home:` changes from `HomeRouter` to `AuthGate`. The `ToastOverlay` stays in
  the same `Stack`.

## B. Auth layer — `lib/auth/`

**`auth_service.dart`** — `AuthService`, the only place that touches `google_sign_in` +
credential exchange:

```dart
// One-time, before first authenticate():
await GoogleSignIn.instance.initialize();
// Sign in:
final account = await GoogleSignIn.instance.authenticate();      // throws GoogleSignInException on cancel/error
final idToken = account.authentication.idToken;                  // 7.x exposes idToken here
final cred = GoogleAuthProvider.credential(idToken: idToken);
await FirebaseAuth.instance.signInWithCredential(cred);
// Sign out:
await GoogleSignIn.instance.signOut();
await FirebaseAuth.instance.signOut();
```

- `signInWithGoogle()` returns normally on success, rethrows a typed failure the screen can
  show. User-cancelled (`GoogleSignInExceptionCode.canceled`) is swallowed (no-op, back to the
  screen); other failures surface as an inline error.
- `signOut()` is provided for the Phase-4 settings screen; not surfaced in any Phase-3 UI.

**`auth_providers.dart`**
- `authServiceProvider = Provider<AuthService>((ref) => AuthService());`
- `authProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());`

**`auth_gate.dart`** — `AuthGate` (ConsumerWidget) watches `authProvider`:
- loading → paper splash (`ColoredBox(Palette.paper)`),
- `data(null)` → `SignInScreen`,
- `data(User)` → `bootstrapProvider` gate (§C) → on done, the signed-in shell
  (`DailyResetScope` wrapping `HomeRouter`).

**`lib/ui/sign_in_screen.dart`** — minimal functional gate (paper aesthetic): centered app
name "Just One", a single **Continue with Google** button, a loading state while signing in,
and an inline error message + retry on failure. Not the final HANDOFF welcome — Phase 4 owns
that. No counters, no branding work.

## C. Bootstrap (D13) — `lib/auth/bootstrap.dart`

`ensureUserDoc(FirebaseFirestore db, String uid, {required DateTime now, required String timezone})`:

- `get users/{uid}`. If **missing**, `set` defaults: `timezone`, `target: 3`,
  `reminders: {weekday: ['08:00','18:30','21:00'], weekend: ['10:00','20:00']}` (D17 defaults),
  `onboardingComplete: false`, all counters zeroed,
  `rerolls: 3`, `bankedToday/targetDismissed: false`, `doneToday: 0`,
  `lastActiveDate: <today as 'YYYY-MM-DD'>`, `streak/bestStreak/targetMetDays/lifetimeDone: 0`.
- If **present**, update only `timezone` (refresh on every app open, D2) — never clobber
  counters.
- Idempotent; safe to run on every sign-in.
- `bootstrapProvider = FutureProvider<void>` keyed off the current uid; reads `nowProvider` and
  `flutter_timezone`. `AuthGate` awaits it before rendering the app, so the UI never renders
  against a missing/half-written doc.

**Phase-3 first-run behaviour:** a freshly bootstrapped account has `onboardingComplete: false`
and **zero tasks**. Phase 3 does **not** route on `onboardingComplete` (that is Phase 4). With
an empty pool, `routeHome` naturally returns `emptyPool`, so a fresh sign-in lands on the
existing **emptyPool** screen; its "Add a chore" button hits the existing Phase-2
`PlaceholderScreen`. No routing changes in this phase. To exercise the daily loop before Phase 4
exists, seed tasks into the emulator with `tool/seed_emulator` (§H).

## D. Repository swap — `lib/data/firestore_repository.dart` + `lib/app/providers.dart`

`FirestoreRepository implements Repository`, constructed `(FirebaseFirestore db, String uid)`:

- `watchUser()` → `db.doc('users/$uid').snapshots()` mapped via `userFromFirestore`. The repo
  caches the **last emitted** `UserState` (for D9 diffing in `commit`).
- `watchTasks()` → `db.collection('users/$uid/tasks').snapshots()` mapped via
  `taskFromFirestore`. Archived/removed tasks are filtered out (only `active`/`benched` reach
  the domain; the selection engine already ignores the rest, but filtering keeps the stream
  small).
- `commit(TransitionResult result)` → a single `WriteBatch` (D11):
  - each `result.changedTasks` doc: `batch.set(taskRef, taskToFirestore(task))`,
  - the user doc: `batch.set(userRef, userToFirestore(result.user), SetOptions(merge: true))`
    for all fields **except** the two D9 counters, which are written as
    `FieldValue.increment(result.user.X - lastEmitted.X)` (see §F).
  - `await batch.commit()` (lands in the local cache instantly offline; syncs later).
- `dispose()` → cancels the two snapshot subscriptions.

`providers.dart` changes:
- `firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);`
- `repositoryProvider` is rewritten:
  ```dart
  final repositoryProvider = Provider<Repository>((ref) {
    final uid = ref.watch(authProvider).value?.uid;           // guard: only built when signed in
    final repo = FirestoreRepository(ref.watch(firestoreProvider), uid!);
    ref.onDispose(repo.dispose);
    return repo;
  });
  ```
  (The provider is only read from inside the signed-in subtree, so `uid` is non-null there. Use
  `AsyncValue.value` — `valueOrNull` does not exist in flutter_riverpod 3.3.2; `.value` returns
  null without throwing. The Phase-2 HomeRouter learning applies verbatim.) On sign-out/account-switch Riverpod disposes the old repo
  (closing its Firestore listeners) and builds a fresh one for the new uid.
- `InMemoryRepository.seeded()` is **removed from `repositoryProvider`**; the class stays for
  the 78 VM tests and gains a `dispose()` that closes its two `StreamController`s.

**Seam change:** add `void dispose();` to `abstract class Repository`. Both implementations
provide it. (Discharges the Phase-2 carry-over.)

## E. Serialization — `lib/data/firestore_mappers.dart` (pure)

Four pure top-level functions, no Firebase plugin calls beyond the `Timestamp`/`DocumentSnapshot`
types they translate (kept type-only so they unit-test in the VM):

- `Map<String, dynamic> userToFirestore(UserState u)`
- `UserState userFromFirestore(Map<String, dynamic> data)`
- `Map<String, dynamic> taskToFirestore(Task t)`
- `Task taskFromFirestore(String id, Map<String, dynamic> data)`

They own every representation gap:
- **Enums ↔ strings:** `TaskKind.oneOff ↔ 'one-off'`, `TaskKind.recurring ↔ 'recurring'`;
  `TaskStatus.{active,benched,archived,removed} ↔ '{active,benched,archived,removed}'`.
- **`Timestamp` ↔ `DateTime`** for `dueAt`, `createdAt`, `completedAt` (nullable preserved).
- **`lastActiveDate`:** `DateTime ↔ 'YYYY-MM-DD'` string (data model stores a string).
- **`reminders`:** the wire map `{weekday: [...], weekend: [...]}` ↔ `remindersWeekday` /
  `remindersWeekend` lists.
- **Defensive validation (Phase-1 carry-over):** `taskFromFirestore` validates invariants
  explicitly (recurring ⇒ positive `intervalDays`; one-off ⇒ null `intervalDays`) and throws a
  descriptive `FormatException` on violation, since `assert`s are stripped in release. The repo
  surfaces a malformed doc as a stream error rather than silently corrupting domain state.

The two D9 increment fields are still emitted by `userToFirestore` (used by bootstrap/tests),
but `commit` overrides them with `FieldValue.increment(delta)` at write time (§F).

## F. D9 additive-counter handling

`lifetimeDone` and `targetMetDays` are written with `FieldValue.increment` (lost-update-safe
across devices, D9); every other user field is absolute last-write-wins (D9 accepts this for
today-counters and streak). The pure `complete()` transition returns **absolute** values, so the
repository derives the delta from its own last-emitted snapshot:

```dart
final base = _lastUser;                 // cached from watchUser(); the snapshot the transition was computed from
final data = userToFirestore(result.user)
  ..remove('lifetimeDone')
  ..remove('targetMetDays');
batch.set(userRef, data, SetOptions(merge: true));
batch.set(userRef, {
  'lifetimeDone': FieldValue.increment(result.user.lifetimeDone - (base?.lifetimeDone ?? 0)),
  'targetMetDays': FieldValue.increment(result.user.targetMetDays - (base?.targetMetDays ?? 0)),
}, SetOptions(merge: true));
```

`increment(delta)` applies relative to the server value, so a lagged base is still correct —
the delta is computed from the same snapshot the transition consumed. The domain stays pure.
Edge: before the first `watchUser` emission `base` is null and the delta falls back to the
absolute value (correct for a just-bootstrapped zeroed doc).

## G. Daily-reset trigger (D22) — `lib/app/daily_reset_scope.dart`

`DailyResetScope` (ConsumerStatefulWidget + `WidgetsBindingObserver`) wraps the signed-in
subtree (between `AuthGate` and `HomeRouter`).

- **Cold start** (`initState` → post-frame) and every **resume**
  (`didChangeAppLifecycleState(AppLifecycleState.resumed)`): read the current user + tasks from
  `userProvider`/`tasksProvider` and `nowProvider`, run the pure
  `dailyReset(user, tasks, now())`, and `repository.commit(result)` **only when it is not a
  no-op** (i.e. `daysBetweenLocalDates(user.lastActiveDate, now) != 0`, equivalently
  `result.changedTasks` non-empty or the user changed).
- Skips entirely while either stream is still loading (no value yet).
- Idempotent by `dailyReset`'s own `gap == 0` guard, so firing on every resume is free except
  the first resume after local midnight (D22).
- Registers the observer in `initState`, removes it in `dispose`.

## H. Security rules, emulator config & dev seed

**`firestore.rules`** — replace the temporary open rule with owner-isolation (D12):

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

The recursive `{document=**}` covers `tasks` + (future) `devices`. **Verified by a documented
one-time manual check** against the Firestore emulator (the Dart fakes have no rules engine, so
rules are not automatically covered — see Testing). Record the check steps in
`docs/superpowers/` so they are repeatable when rules change in a later phase.

**`firebase.json`** — add an `emulators` block (auth :9099, firestore :8080, ui enabled) so
`firebase emulators:start` serves Auth + Firestore locally for running the app by hand and for
the manual rules check.

**`tool/seed_emulator.dart`** — a small standalone script (run against the emulator) that writes
one onboarded user (`onboardingComplete: true`) plus a handful of sample tasks mirroring the old
`InMemoryRepository.seeded()` pool, so the daily loop is hand-testable before Phase 4 onboarding
exists. Debug/dev tooling only; not shipped, not referenced from `lib/`.

## Testing

**One runner: `flutter test` on the Dart VM — no device, no emulator.** Firebase-facing code is
exercised through in-memory Dart fakes (`fake_cloud_firestore`, `firebase_auth_mocks`), which
implement the real `cloud_firestore`/`firebase_auth` API surface without platform channels.
`FirestoreRepository`, `ensureUserDoc`, and `DailyResetScope` all take their
`FirebaseFirestore` / auth dependencies by injection, so a test passes a fake instance.

- **Existing 78 tests stay green** (they use `InMemoryRepository`, which is retained).
- **Pure mappers** (`firestore_mappers.dart`): round-trip each model, enum/Timestamp/date-string
  conversions, reminders map shape, and the defensive validation throwing on malformed task docs.
- **`FirestoreRepository`** (via `fake_cloud_firestore`): `watchUser`/`watchTasks` emit on doc
  changes; `commit` writes the task doc(s) **and** user doc in one batch; the two D9 fields land
  as increments (assert two successive commits accumulate, and that a lagged base still yields
  the correct server value).
- **Daily reset** (`DailyResetScope` decision logic, via fakes): a doc with a stale
  `lastActiveDate` produces exactly one reset commit (counters cleared, benched→active, streak
  rule honoured); same-local-day is a no-op.
- **Bootstrap** (`ensureUserDoc`, via fakes): missing doc → defaults written once; existing doc
  → only `timezone` refreshed, counters untouched.
- **Auth/gate** (via `firebase_auth_mocks`): `AuthGate` shows `SignInScreen` when signed out and
  the app shell when signed in; sign-in success/cancel/failure paths on `SignInScreen`.

**Not automatically covered — owner-isolation rules (D12).** The fakes have no rules engine.
Rules are verified by the documented one-time manual emulator check (§H): sign in as user A,
confirm own-tree read/write succeeds and user B's tree is denied. Acceptable because the rule is
four lines and static; re-run the check only when rules change.

**Fidelity caveat.** A fake is not the real Firestore — server timestamps, real index
requirements, and some `FieldValue` edge cases are not exercised. Mitigated by keeping the
mappers pure and exhaustively tested, and by a one-time manual smoke test of the running app
against the real emulator on a device before declaring Phase 3 done.

## Error handling

- **Sign-in cancelled** → no-op, stay on `SignInScreen`. **Sign-in failed** → inline error +
  retry. No other auth states in this phase.
- **Firestore offline** → rely on built-in offline persistence; the UI shows the last cached
  state and `commit` queues to the local cache. No bespoke retry/queue UI (YAGNI; D11/D21).
- **Malformed doc** → `taskFromFirestore` throws `FormatException`; surfaces as a stream error
  (the existing `AsyncValue.error` path in the UI), not silent corruption.
- **D21 offline-nudge edge** is an accepted, documented limitation — not mitigated here.

## Out of scope (later phases)

- Onboarding wizard, `add`/`manage`/`settings`, first-run routing on `onboardingComplete`
  (Phase 4).
- FCM token registration / `devices` subcollection, notification permission flow (Phase 6).
- Stats screen (Phase 5).
- The polished HANDOFF welcome screen (Phase 4 replaces the minimal `SignInScreen`).

## File summary

| File | Change |
|------|--------|
| `lib/main.dart` | Firebase init + emulator wiring; `home: AuthGate` |
| `lib/auth/auth_service.dart` | new — Google Sign-In + credential exchange |
| `lib/auth/auth_providers.dart` | new — `authProvider`, `authServiceProvider` |
| `lib/auth/auth_gate.dart` | new — auth + bootstrap gate |
| `lib/auth/bootstrap.dart` | new — `ensureUserDoc` (D13) + `bootstrapProvider` |
| `lib/ui/sign_in_screen.dart` | new — minimal Continue-with-Google gate |
| `lib/data/firestore_repository.dart` | new — `Repository` impl + WriteBatch + D9 diffing |
| `lib/data/firestore_mappers.dart` | new — pure doc↔model serialization + validation |
| `lib/data/repository.dart` | modify — add `void dispose()` |
| `lib/data/in_memory_repository.dart` | modify — implement `dispose()`; drop from prod wiring |
| `lib/app/providers.dart` | modify — `firestoreProvider`; `repositoryProvider` from uid |
| `lib/app/daily_reset_scope.dart` | new — `WidgetsBindingObserver` reset trigger (D22) |
| `firestore.rules` | modify — owner-isolation (D12) |
| `firebase.json` | modify — add `emulators` block |
| `tool/seed_emulator.dart` | new — dev-only emulator seed (hand-testing) |
| `pubspec.yaml` | modify — add `fake_cloud_firestore` + `firebase_auth_mocks` dev deps |
| `test/data/firestore_mappers_test.dart` | new — pure mapper tests (VM) |
| `test/data/firestore_repository_test.dart` | new — repo via `fake_cloud_firestore` (VM) |
| `test/auth/bootstrap_test.dart` | new — `ensureUserDoc` via fakes (VM) |
| `test/auth/auth_gate_test.dart` | new — gate + sign-in via `firebase_auth_mocks` (VM) |
| `test/app/daily_reset_scope_test.dart` | new — reset decision logic via fakes (VM) |
| `docs/superpowers/phase-3-manual-rules-check.md` | new — repeatable owner-isolation check steps |
