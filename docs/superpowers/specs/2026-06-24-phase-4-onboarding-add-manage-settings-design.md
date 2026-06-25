# Phase 4 — Onboarding + Add / Manage / Settings (Design Spec)

**Status:** Locked (brainstormed 2026-06-24).
**Goal:** Build the first-run onboarding wizard, the add/edit (enrich) flow, the manage-pool
screen, the settings screen, and the designed welcome screen — wiring first-run routing off
`onboardingComplete` (D13). All writes go through the existing pure-transition → `commit`
(`WriteBatch`) seam from Phases 1–3. No Firebase notifications/permissions work — that is Phase 6.

This spec implements roadmap **Phase 4** and backend decisions **D6, D8, D11, D13, D17, D23**
(and touches the Phase-3 carry-over cleanups). The product spec (`docs/design/HANDOFF.md`), the
locked prototype (`docs/design/Chore App Designs.dc.html`), and the backend decisions
(`docs/design/backend-decisions.md`) are the source of truth for *what it does* and *how it
looks*; this spec records *how Phase 4 wires them up*.

---

## Global Constraints

These bind every task. Exact values are authoritative.

- **No new runtime dependencies.** Everything needed is already in `pubspec.yaml`. Date/time
  display is formatted by hand (as `firestore_mappers._dateToString` already does); **no `intl`,
  no `uuid`.** Task IDs come from the repository seam (§C), not a package.
- **The `Repository` interface stays the only data seam.** No Firebase imports anywhere in
  `lib/` outside `lib/data/firestore_*.dart`, `lib/auth/`, and `lib/main.dart`. Domain, UI, and
  controllers must not learn that Firestore exists.
- **Every write is a pure transition committed via `commit(TransitionResult)`** — the Phase 1–3
  pattern. No new write methods on `Repository` except ID allocation (§C). No direct Firestore
  writes from controllers or UI.
- **`now` always via `nowProvider`** (the `Clock` seam) — never `DateTime.now()` in domain,
  controllers, or screens. Task-ID allocation is likewise injected (via the repository, §C) so
  it stays deterministic in tests.
- **The pure domain is never modified to suit Firestore.** Serialization and the D9 increment
  diffing stay in the data layer.
- **Firestore field names are canonical** per `backend-decisions.md` (§"Consolidated Firestore
  data model"). `urg`/`meta`/`screen` are **never** persisted (D6); `dueAt` is a nullable
  timestamp; `lastActiveDate` is a `'YYYY-MM-DD'` string.
- **Google Sign-In only, mandatory (D8).** Apple/email appear in the welcome UI as visibly
  deferred (disabled), not wired.
- **Restraint holds on the daily card.** No counters/badges/meta on the daily screen; the
  manage list is where per-task labels live.
- **Keep files under ~1,000 lines** (project rule); factor shared widgets out.
- **Testing is Dart-fakes-only** (`fake_cloud_firestore` + `firebase_auth_mocks` in plain
  `flutter test`), per Phase 3. No device/emulator in any automated test.

---

## Scope boundary with Phase 6 (explicit)

Phase 4 **writes the reminder schedule** (the D17 `reminders` map) from the settings screen and
seeds defaults at onboarding — that is all. It does **not** request the runtime notification
permission, does **not** register FCM tokens, and does **not** add the settings "re-enable
notifications" path. Those, plus the Cloud Function, are **Phase 6** (roadmap). Onboarding ends
at "Start Just One" → the daily loop, with no permission prompt.

---

## A. Routing & navigation wiring

### A1. Onboarding gate in `routeHome` (D13)

Extend the pure `routeHome` (`lib/domain/routing.dart`) so its **first** decision is:

```dart
if (!state.onboardingComplete) return AppScreen.onboardTarget;
```

before the pool-empty / target / selection logic. `onboardTarget` is the single "show the
onboarding wizard" signal. `onboardAdd` remains in the `AppScreen` enum but is **internal wizard
state** of the onboarding widget, not a value `routeHome` ever returns. Everything else in
`routeHome` is unchanged.

Rationale: keeps first-run routing pure and unit-testable, and the onboarding flow rides the same
stream-driven `HomeRouter` derivation as the rest of the home loop. When the seed commits and
`onboardingComplete` flips true, the user stream re-emits and `routeHome` falls through to
`daily`/`cleared`/`emptyPool`/`targetHit` naturally.

### A2. `HomeRouter` cases (`lib/ui/home_router.dart`)

- `onboardTarget` → render `OnboardingFlow` (full-screen).
- `daily`/`cleared`/`emptyPool`/`targetHit` → unchanged.
- Replace the four `PlaceholderScreen` pushes (currently `_open(context, 'Manage'/'Add'/'Stats')`
  in `home_router.dart`, `daily_screen.dart`, `cleared_screen.dart`, `empty_pool_screen.dart`)
  with the real navigation below. `PlaceholderScreen` is **kept** only for `Stats` (Phase 5).

### A3. Navigation model

- **`manage` and `settings` are full-screen `Navigator` pushes** (`MaterialPageRoute`), matching
  the existing push pattern. manage ← daily menu (top-left) and cleared "Review pool" and
  emptyPool has its own Add CTA. settings ← manage gear (top-right).
- **`add` and `enrich` are modal bottom sheets** (`showModalBottomSheet`, scrim + rise), per the
  prototype, shown over daily or manage:
  - FAB (daily / manage) and emptyPool "Add a chore" → **AddSheet** (title only).
  - AddSheet "Add to pool" → creates the task, then immediately opens **EnrichSheet** for it
    (matches prototype: quick-add then optional enrichment). "Cancel" dismisses without creating.
  - manage row tap → **EnrichSheet** directly for that task (edit).
  - manage trash icon → confirm dialog → `remove`.

---

## B. Domain layer (pure, TDD'd) — `lib/domain/`

All new logic is pure functions returning `TransitionResult`, plus value mappings. New file
`lib/domain/edits.dart` (builders + mappings); a label helper extends the urgency module.

### B1. Deadline chip ↔ `dueAt`

Forward (chip → `dueAt`), anchored on the local calendar date of `now`:

| Chip | `dueAt` |
|---|---|
| No deadline | `null` |
| Today | today 00:00 (local) |
| Tomorrow | today + 1 day |
| This week | today + 7 days |
| Next week | today + 14 days |
| Pick a date | the chosen date (00:00 local) |

*Decision:* "This week"/"Next week" are the **+7 / +14** ladder from today — a simple,
predictable convenience feeding the continuous urgency curve; "Pick a date" covers precision.
(Not calendar-week-aware by design.)

Reverse (for edit pre-selection), `dueAt` → selected chip: `null`→No deadline; ==today→Today;
==today+1→Tomorrow; ==today+7→This week; ==today+14→Next week; any other non-null →"Pick a date"
carrying that date.

### B2. Repeat chip ↔ `kind` + `intervalDays`

Forward:

| Chip | `kind` | `intervalDays` |
|---|---|---|
| One-off | `oneOff` | `null` |
| Every 3 days | `recurring` | 3 |
| Weekly | `recurring` | 7 |
| Fortnightly | `recurring` | 14 |
| Monthly | `recurring` | 30 |
| Custom (N × unit) | `recurring` | N × {days:1, weeks:7, months:30} |

Custom picker: `N` clamped 1–99, unit ∈ {days, weeks, months}; month ≈ 30 days (consistent with
"Monthly"=30). Reverse: `null`→One-off; 3/7/14/30 → the matching preset; any other →"Custom"
decomposed to the largest exact unit (÷30 if divisible, else ÷7 if divisible, else days).

### B3. Deadline × Repeat interaction

The enrich sheet represents the task's **full desired state**; Save writes exactly what the chips
say. A recurring task with "No deadline" keeps `dueAt = null` — it surfaces at the 0.35 undated
baseline (`urgencyOf`) until its first completion, after which `complete()` sets the real cadence
(`dueAt = completedAt + intervalDays`). No special "force `dueAt = today`" rule is needed.

### B4. Pure builders → `TransitionResult`

- `seedOnboarding(UserState state, {required int target, required List<Task> tasks, required DateTime now})`
  → `user = state.copyWith(target, onboardingComplete: true, lastActiveDate: dateOnly(now))`,
  `changedTasks = tasks`. (Reminders are already seeded at bootstrap; not re-written here. D23.)
- `addTask(UserState state, Task task)` → `user = state` (unchanged), `changedTasks = [task]`.
- `editTask(UserState state, Task task)` → same shape; `task` carries the edited fields with its
  existing `id`/`createdAt`/`status`/`completedAt` preserved.
- `updateSettings(UserState state, {int? target, List<String>? weekday, List<String>? weekend})`
  → `user = state.copyWith(...)`, `changedTasks = const []`.
- `remove` (exists) serves manage's delete.

`addTask`/`editTask` returning the unchanged user is intentional: `commit` re-writes the user doc
via merge with zero-delta increments (D9) — harmless and consistent with accepted last-write-wins.

### B5. `manageMeta(Task task, DateTime now)` (presentation)

Manage-list label only (daily card stays meta-free): recurring → recurrence label ("Every 3
days" / "Weekly" / "Fortnightly" / "Monthly" / "Every N days|weeks|months"); one-off → existing
`metaOf(task, now)` (due/overdue/no-deadline). Pure, in the urgency/labels module.

### B6. Task construction helper

A pure helper assembles a new/edited `Task` from `{id, title, deadlineChip+pickedDate,
repeatChip+customN+customUnit, createdAt, now}` using B1/B2 — used by `PoolController` so the
chip→field mapping is unit-tested independently of the UI.

---

## C. Repository: task-ID allocation (the only seam change)

Add one method to `Repository`:

```dart
String newTaskId();
```

- `FirestoreRepository`: `return _tasksRef.doc().id;` (client-side auto-id, no network).
- `InMemoryRepository`: an incrementing counter (`'t${_n++}'` or similar) — deterministic in
  tests.

New `Task`s are built with this id, then committed through the existing merge-by-id `commit`
(which already *adds* unknown ids — see `InMemoryRepository.commit` / `FirestoreRepository`'s
`batch.set` on `_tasksRef.doc(task.id)`). No other `Repository` changes. `dispose`/`watchUser`/
`watchTasks`/`commit` are untouched.

Exposed to UI/controllers via the providers as today (controllers read `repositoryProvider`).
Optionally a thin `idProvider` is unnecessary — `newTaskId()` already lives on the injected repo
and is overridable through the in-memory fake in tests.

---

## D. Controllers (action layers) — `lib/app/`

Thin, mirroring `DailyController`: read snapshot → call pure builder → fire toast → `commit`.

- **`OnboardingController.finish({required int target, required List<String> titles})`**
  builds N `Task`s (one-off, no deadline, `createdAt = now`, ids from `newTaskId()`), calls
  `seedOnboarding`, commits one batch (D23). Empty/whitespace titles dropped; de-duplicated.
- **`PoolController`**: `.add(...)` / `.edit(task, ...)` (build Task via B6, commit) /
  `.remove(task)` (toast `Deleted "<title>"`, matching prototype).
- **`SettingsController`**: `.setTarget(int)` (clamp 1–6), `.setReminders(weekday, weekend)`
  (each 0–3 entries, sorted "HH:mm" strings) → `updateSettings` → commit.

Each gets a `*Provider` reading `repositoryProvider` + `toastProvider.notifier` + `nowProvider`,
like `dailyControllerProvider`.

---

## E. UI screens & components — `lib/ui/`

Recreated idiomatically from the locked prototype (lift exact colours/sizes/spacing from
`Chore App Designs.dc.html`; do not port JS). Type/colour tokens come from the existing theme.

- **`WelcomeScreen`** — replaces `SignInScreen`. Wordmark + cream tick mark + styled "Continue
  with Google" (live); "Continue with Apple" / "Continue with email" shown **disabled** (D8
  future). On success, `authStateChanges` drives `AuthGate` forward (no manual nav). See §F for
  the `AuthService` cleanup that lets this drop the `google_sign_in` import.
- **`OnboardingFlow`** — one `ConsumerStatefulWidget` owning step state (`target`, `step`,
  `titles`, draft):
  - Step 1 "How much is enough?": target stepper 1–6 with the dot row; "Continue".
  - Step 2 "What's on your plate?": text field + Add; suggestion chips (Dishes, Laundry, Water
    the plants, Reply to emails, Take the bins out, Make the bed) toggle into the list; removable
    list rows; back arrow → step 1; "Start Just One" → `OnboardingController.finish`.
- **`AddSheet`** — bottom sheet: "New chore" eyebrow, big title input ("What needs doing?"),
  Cancel / "Add to pool".
- **`EnrichSheet`** — bottom sheet: shows title; **Deadline** chip row; **Repeat** chip row;
  custom-repeat sub-panel (− N + with days/weeks/months segmented control) revealed when Custom
  is selected; "Pick a date" opens `showDatePicker` (themed); Back / Save. Pre-selects chips via
  B1/B2 reverse maps when editing.
- **`ManageScreen`** — "Your pool" header (back ‹, gear); list of non-archived/non-removed tasks,
  each a card: urgency dot (colour by `urgencyOf` band), title, `manageMeta`, trash icon (→
  confirm dialog → `remove`); FAB → AddSheet; gear → SettingsScreen.
- **`SettingsScreen`** — "Reminders" header (back ‹); **Daily target** stepper row; **Weekdays /
  Weekends** segmented tabs selecting which reminder array is edited; editable reminder rows
  (each: time picker via `showTimePicker`, remove); "Add a reminder" up to 3 for the active
  group; "Signed in · sync on" + **Sign out** (→ `AuthService.signOut()`); wordmark + version
  footer. Writes the full D17 `reminders` map.
- **Shared widgets** factored out to keep files small: `TargetStepper`, `ChoiceChipTile`,
  `BottomSheetScaffold` (drag handle + rounded top + scrim/rise), `ConfirmDialog`.

---

## F. Phase-3 carry-over cleanups (folded in here)

Per the Phase-3 final review (roadmap §"Deferred to Phase 4+"):

- Move `GoogleSignInException` cancel-handling **behind `AuthService`** so the new
  `WelcomeScreen` (and all of `lib/ui/`) no longer imports `google_sign_in`. `AuthService`
  exposes a sign-in that swallows the user-cancel case and surfaces a simple failure otherwise.
- **Harden `AuthService.signOut()`** so it does not call `GoogleSignIn.signOut()` when
  `initialize()` never ran (settings "Sign out" is the first real caller).
- Remove the dangling `(D18)` comment reference in `main.dart`.

These are small and naturally land with the welcome/settings work; they are in-scope.

---

## G. Error handling

- Writes hit Firestore's local cache instantly (offline-safe, D23), so the UI advances
  optimistically — **no commit spinners**. Stream re-emission updates the screen.
- Empty/whitespace titles: AddSheet "Add to pool" and onboarding "Add" no-op (trim first).
- Target clamps **1–6** everywhere (stepper buttons disable at bounds). Reminder arrays clamp
  **0–3** per group and stay sorted ascending "HH:mm".
- Delete is guarded by the confirm dialog (destructive, irreversible — sets `status: removed`).
- Sign-out goes through hardened `AuthService.signOut()`; `repositoryProvider` tear-down already
  swaps the data layer on auth change (Phase 3).

---

## H. Testing (Dart-fakes-only)

- **Domain (pure):** B1/B2 forward **and** reverse maps (incl. Custom decomposition and
  non-preset dates → "Pick a date"); `seedOnboarding`/`addTask`/`editTask`/`updateSettings`
  results; `manageMeta` for each kind/band; B6 task assembly; `routeHome` returns `onboardTarget`
  iff `!onboardingComplete` and is unchanged otherwise.
- **Repository:** `newTaskId()` returns distinct ids (both impls); onboarding seed commits in one
  batch — N task docs created + `onboardingComplete` flipped + `target`/`lastActiveDate` written —
  via `fake_cloud_firestore`; add/edit/remove/settings round-trip through `commit` and re-emit.
- **Widget:** welcome sign-in; onboarding flow (set target, add via field + chips, remove, finish
  → lands on populated `daily`); AddSheet→EnrichSheet→task appears in manage; EnrichSheet edit
  changes deadline/repeat; manage delete confirm; settings target + reminder add/edit/remove
  write the expected D17 arrays; first-run routing (`onboardingComplete:false` → onboarding).
- Test files mirror the existing layout under `test/domain`, `test/app`, `test/data`, `test/ui`.

---

## I. Out of scope (Phase 4)

- All notification/permission/FCM work and the settings re-enable path → **Phase 6**.
- The stats screen → **Phase 5** (`PlaceholderScreen` for Stats stays).
- Apple/email sign-in (D8) — UI placeholders only.
- Wizard partial-resume (D23: none — restart the short wizard if it dies before commit).
