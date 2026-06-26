# Just One — Implementation Roadmap

The product spec (`docs/design/HANDOFF.md`) and backend decisions
(`docs/design/backend-decisions.md`, D1–D23) are **locked and already grilled**. This file
records the *sequencing* of the build — it is too large for one spec, so it's decomposed into
phases. **Each phase gets its own spec → plan → implementation cycle** (via the brainstorming /
writing-plans flow). Specs land in `docs/superpowers/specs/`.

Starting point (2026-06-22): default Flutter counter app with the correct dependencies already in
`pubspec.yaml` (firebase_core/auth, cloud_firestore, messaging, google_sign_in, riverpod,
flutter_timezone), a configured `firebase_options.dart`, and untouched `firestore.rules` /
`functions/` templates.

## Phases

| # | Phase | Scope | Status |
|---|---|---|---|
| 1 | **Domain core + design system** | Pure-Dart immutable models (`Task`, `UserState`), the urgency curve + `meta` derivation, the selection engine (highest-urg active task), the screen-routing pure function, and the state-transition functions (complete / skip / remove / daily-reset) returning intended writes. Plus the design system: colour tokens, halo colour interpolation, the major-second type scale, `Newsreader`/`Nunito Sans` text styles, `ThemeData`. **No Firebase, no UI. Fully TDD.** | **✅ Complete** (merged to `main`, 48 tests green) |
| 2 | **Daily-loop UI** | The daily card (swipe-right Done, swipe-left Skip, long-press Remove, finger-following physics, hint labels, halo), plus `cleared` / `emptyPool` / `targetHit` screens and toasts. Driven by the Phase-1 engine against an **in-memory fake repository** (no Firebase yet). | **✅ Complete** (merged to `main`, 78 tests green) |
| 3 | **Firebase wiring** | Google Sign-In, `users/{uid}` bootstrap on first sign-in (D13), Firestore `StreamProvider`s over user doc + tasks (D10), the real repository, complete-task `WriteBatch` (D11), client-authoritative daily reset on cold-start + resume (D7/D22), owner-isolation security rules (D12). Swap the fake repo for the real one. | **✅ Complete** (merged to `main`, 101 tests green) |
| 4 | **Onboarding + add / manage / settings** | First-run wizard (`onboardTarget` + `onboardAdd` batch seed in one `WriteBatch`, D23), the `add`/edit screen (title, deadline, recurrence), the `manage` pool screen, and `settings` (target, reminder schedule per D17). First-run routing via `onboardingComplete` (D13). | **✅ Complete** (150 tests green) |
| 5 | **Stats screen** | The streak hero — the one deliberately loud surface in the app. | **✅ Complete** (154 tests green) |
| 6 | **Notifications** | Cloud Function (TypeScript, Functions v2, `onSchedule("every 15 minutes")`, D16) scanning user docs and sending FCM per timezone/reminder window with idempotency + escalation (D3/D5/D17); FCM token registration in a `devices` subcollection (D4); runtime permission flow at end of onboarding with a settings re-enable path (D14); notification-type payloads (D15). | **✅ Complete** (169 Flutter tests + 18 functions tests green) |

## Decisions captured during Phase-1 brainstorm (2026-06-22/23)

- **First slice = Phase 1** (domain core + design system) — foundation everything sits on; resolves
  the urgency curve.
- **Urgency curve (built in Phase 1):** a single sigmoid in *normalised lateness*. `d = (now − dueAt)`
  in days; normaliser `N = intervalDays` for recurring, `N = 7` for a one-off with a deadline;
  `r = d / N`; `urg = 0.04 + 0.94 · sigmoid(2r)`. Due-now ≈ 0.51, one cycle overdue ≈ 0.87, badly
  overdue → ~0.96. **The "due / cleared" threshold is `dueThreshold = 0.30`** (a public const in
  `urgency.dart`) — it must sit *strictly above* the 0.04 floor, because the sigmoid only approaches
  the floor and never reaches it, so the original `urg > 0.04` cutoff made `cleared` unreachable
  (bug found and fixed in Phase 1). `0.30` ≈ the urgency a recurring task hits ~half an interval
  before due, so that's when it starts surfacing. All constants tunable + TDD'd.
- **Undated one-off tasks:** surface as gently-due-now with a constant low-band urgency (~0.35) —
  always rank below anything with a real deadline, but keep appearing, so `cleared` is reached only
  when the actionable pool is genuinely empty.
- **Day-one seed:** seeded recurring chores get `dueAt = today` so onboarding lands on a populated
  daily card.

## Decisions captured during Phase-2 (2026-06-23)

- **Architecture seam:** a 3-method `Repository` (`watchUser` / `watchTasks` / `commit(TransitionResult)`)
  backed by `InMemoryRepository` now; Phase 3 swaps in a `FirestoreRepository` behind the same
  interface. Riverpod (manual providers, no codegen): `StreamProvider`s over the repo, a `Clock`
  (`nowProvider`) seam so urgency/routing are deterministic in tests, a `ToastController`, and a
  `DailyController` action layer. Screens are derived **purely** from `routeHome` (no ephemeral
  screen state). Custom `GestureDetector` + `AnimationController` card (no swipe package).
- **`cleared` has no "Keep going" / re-serve** — it's terminal for the day; the only exit is
  "Review pool" → manage. "Keep going" lives only on `targetHit`.
- **Deferred to Phase 3 (carried from the Phase-2 review):** add `dispose`/`close` to the
  `Repository` interface (close `InMemoryRepository`'s StreamControllers) for Firestore-listener
  parity; add a double-tap/in-flight guard to `DailyController.complete` once commits have real
  latency; when building the long-press hold-ring, **replace** the `SwipeCard`'s shared
  `GestureDetector` (separate the long-press recognizer from the horizontal drag) so a drifting
  long-press can't be captured by the drag recognizer and drop `onRemove`.

## Decisions captured during Phase-3 (2026-06-24)

- **Repository swap behind the seam:** `FirestoreRepository(db, uid)` implements the unchanged
  3-method `Repository`; `repositoryProvider` reads the signed-in uid from `authProvider` and is
  rebuilt+disposed on auth change (sign-out/account-switch swaps the data layer). The entire
  Phase-2 UI/controllers/domain are untouched. `Repository.dispose()` was added (Phase-2 carry-over);
  on `FirestoreRepository` it is an intentional **no-op** — `watchUser`/`watchTasks` return Firestore
  `snapshots()` streams directly, so the listening `StreamProvider` owns cancellation.
- **D9 increment diffing lives in the repository, not the domain:** `commit` writes `lifetimeDone`/
  `targetMetDays` as `FieldValue.increment(result.user.X − _lastUser.X)` (base = last `watchUser`
  emission) and every other user field absolute last-write-wins, all in one `WriteBatch` (D11). The
  pure transitions still return absolute values. Correct across lagged-base + concurrent-write
  (cross-device test proves lost-update safety).
- **Daily reset (D22) via `DailyResetScope`** — a `WidgetsBindingObserver` wrapping the signed-in
  subtree; runs the pure `dailyReset` on cold-start + every resume, commits only when the local day
  advanced (`_busy` re-entrancy guard). It **normalizes `now` to a calendar date** before the call so
  `lastActiveDate` stays a midnight `DateTime`, consistent with bootstrap/mappers/`seeded()`.
- **Testing is Dart-fakes-only (no device/emulator in CI):** `fake_cloud_firestore` +
  `firebase_auth_mocks` in plain `flutter test`. Owner-isolation rules (D12) are **not** covered by
  automated tests (the fakes have no rules engine) — verified by the documented manual emulator check
  in `docs/superpowers/phase-3-manual-rules-check.md`. First-run sign-in (onboardingComplete:false,
  empty pool) routes to `emptyPool` → placeholder; the real onboarding wizard is Phase 4.
- **Deferred to Phase 4+ (from the Phase-3 final review):** move the `GoogleSignInException` cancel
  handling behind `AuthService` when the designed welcome screen lands, so `lib/ui/` drops the
  `google_sign_in` import; harden `signOut()` (currently calls `GoogleSignIn.signOut()` even if
  `initialize()` never ran); the `(D18)` comment in `main.dart` is a dangling ref. **Before first
  deploy/device run:** run the manual rules check, and do the one-time manual device smoke
  (`firebase emulators:start` → `tool/seed_emulator.dart` → `flutter run` → verify daily card,
  complete/skip/remove writes land, and the reset fires on resume past local midnight).

## Decisions captured during Phase-4 (2026-06-25)

- **Single `saveTask` builder, not `addTask`/`editTask`:** add and edit share one pure builder in
  `lib/domain/edits.dart` (DRY) — edit passes through the existing `id`/`status`/`createdAt`/
  `completedAt`, add seeds fresh ones via `newTaskId()`.
- **`newTaskId()` is the only `Repository` seam addition this phase:** client-side id allocation for
  new pool tasks, implemented identically on `InMemoryRepository` and `FirestoreRepository`; no other
  interface changes were needed.
- **This/Next-week deadline chips = `+7`/`+14` days** from `now`, via the same DST-safe
  year/month/day constructor as the other `dueAtFor` cases.
- **Reminders are fully editable in Settings (D17)** — not just the initial onboarding choice; the
  settings screen reads/writes the same weekday + time-of-day arrays as onboarding.
- **Phase-3 carry-overs closed:** the designed welcome screen landed; `GoogleSignInException`
  cancel-handling moved behind `AuthService`; `signOut()` now guards on `_initialized` before calling
  `GoogleSignIn.signOut()`.
- **`ManageScreen` filters active/benched itself:** `InMemoryRepository.watchTasks` does not
  status-filter (unlike `FirestoreRepository`, which filters archived/removed at the query level), so
  the screen applies its own active/benched split to keep both repositories visually consistent.

## Decisions captured during Phase-5 (2026-06-25)

- **Stats is a pushed route, not a `routeHome` screen:** reached via the daily bar-chart button as a
  `MaterialPageRoute` (same pattern as manage/settings). `AppScreen.stats` stays unreferenced by the
  router, consistent with manage/settings.
- **`poolCount` excludes archived + removed** (active + benched), matching the prototype and
  `routeHome`'s pool-empty definition — derived from `tasksProvider`, not stored.
- **Built static, matching the prototype.** **Deferred follow-up:** revisit a gentle entrance
  animation for the stats hero (streak count-up or hero fade/scale-in), evaluated on-device — the
  handoff calls this "the one loud moment" but the prototype markup carries the weight through
  composition, not motion.
- **`PlaceholderScreen` removed** — the stats button was its last caller.

## Decisions captured during Phase-6 (2026-06-26)

- **One spec, both halves** — client FCM plumbing + the Cloud Function shipped together.
- **Tap just opens the app** — no deep-link/`data` routing; `routeHome` already lands on
  daily/cleared. (Closes the "still open" deep-link item: v1 = none.)
- **Catch-up jumps to the latest passed beat** — `decideNotification` sends only the most-
  escalated passed reminder and covers the skipped ones (no backfill burst); a refinement of
  D5's literal "next un-sent".
- **Device doc id = the FCM token** — no local-id dependency; token rotation + the server's
  dead-token cleanup self-heal transient duplicates.
- **Streak-0 copy variant** — the final beat uses start-framing when there's no streak to lose.
- **`MessagingService` seam** (mirrors `AuthService`) + one new `Repository.upsertDevice` —
  the only seam additions; `firebase_messaging` never runs in `flutter test`.
- **Functions switched to CommonJS** — dropped the scaffold's NodeNext/ESM for friction-free
  jest + build; Functions v2 runs CJS fine.
- **Server logic is pure** (`decideNotification` + `runScan` with injected `ScanDeps`) and
  fully unit-tested; only the Admin-SDK wiring in `index.ts` is verified by build + the
  documented manual device check (D18).
- **Settings re-enable card does not open OS settings programmatically** — `firebase_messaging`
  has no such API and we avoided a new dependency; the card re-prompts and, on permanent denial,
  instructs the user to enable in system settings.

## Still genuinely open (from research §11 / backend "still open")

- Final tuning of the urgency curve constants, reroll count (≈3), default reminder times, streak
  grace (none for v1).
