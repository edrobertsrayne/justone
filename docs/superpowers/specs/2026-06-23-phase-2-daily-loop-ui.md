# Phase 2 — Daily-loop UI (Design Spec)

**Status:** approved design, ready to plan.
**Depends on:** Phase 1 domain core + design system (merged to `main`).
**Source of truth for look/behaviour:** `docs/design/HANDOFF.md` §1–§7 and the interactive
prototype `docs/design/Chore App Designs.dc.html` (the `sc-if` screen blocks + the JS at
lines ~1500–1850). Exact tokens below are lifted from there.

## Goal

Build the playable daily loop — the swipeable daily card plus the `cleared` / `emptyPool` /
`targetHit` screens and toasts — driven by the Phase-1 domain engine against an **in-memory fake
repository**. No Firebase, no auth, no onboarding yet.

## Non-goals (deferred, on purpose)

- **No auth / `welcome` / onboarding.** `HomeRouter` assumes a signed-in, onboarded user and
  starts at `routeHome`. Auth + onboarding gating layer on in Phase 3/4.
- **No daily-reset trigger.** The fake repo seeds an already-current "today" state; cold-start /
  resume `dailyReset` wiring is Phase 3. (`dailyReset` itself exists and is tested.)
- **No Firestore.** `InMemoryRepository` only; `FirestoreRepository` is Phase 3.
- **No real `add` / `manage` / `settings` / `stats` bodies.** Their routes are wired to
  `PlaceholderScreen` ("… — coming soon"); Phase 4/5 swap the bodies.
- **No `enrich` sheet, no suggestion chips, no recurrence editing** (Phase 4).

---

## A. Architecture — the seam

A `Repository` abstraction is the only thing Phase 3 must reimplement.

```dart
abstract class Repository {
  Stream<UserState> watchUser();
  Stream<List<Task>> watchTasks();
  Future<void> commit(TransitionResult result);
}
```

`commit` applies a Phase-1 `TransitionResult`: replace the stored `UserState` with `result.user`,
merge `result.changedTasks` into the task list **by `id`** (a changed task replaces the one with the
same id; tasks not in the list are untouched), then re-emit both streams.

`InMemoryRepository implements Repository`:
- Holds a mutable `UserState` and `List<Task>`, seeded at construction.
- Exposes them through broadcast streams that **replay the latest value to new subscribers**
  (seed value emitted immediately on `listen`), so `StreamProvider`s have data on first build.
- A default factory seeds a realistic pool for running the app by hand (see §G). Tests construct it
  with an explicit `UserState` + `List<Task>` for determinism.

The task list stores tasks of every `status`; `selectTask` / `routeHome` do the filtering. Archived
and removed tasks stay in the list (they just stop being served), mirroring Firestore.

### File structure (each file one responsibility, all well under 1k lines)

```
lib/
  data/
    repository.dart            abstract Repository
    in_memory_repository.dart  fake impl + default seed
  app/
    providers.dart             repositoryProvider, userProvider, tasksProvider,
                               nowProvider, dailyControllerProvider
    daily_controller.dart      complete / skip / remove / keepGoing actions + toast dispatch
  ui/
    home_router.dart           watches (user, tasks, now) -> routeHome -> screen
    daily_screen.dart          chrome (manage / TODAY / stats) + FAB + SwipeCard host
    swipe_card.dart            custom gesture/physics card + halo + hint labels
    cleared_screen.dart
    empty_pool_screen.dart
    target_hit_screen.dart
    placeholder_screen.dart    generic "coming soon" (manage / stats / add)
    toast.dart                 top-anchored auto-dismiss overlay
  main.dart                    ProviderScope + MaterialApp(buildAppTheme()) + HomeRouter
```

---

## B. State flow — screen fully derived

- `repositoryProvider` — exposes the `Repository`; overridden per environment (live = the seeded
  `InMemoryRepository`; tests = an explicitly seeded one).
- `userProvider` (`StreamProvider<UserState>`) / `tasksProvider` (`StreamProvider<List<Task>>`) —
  read the repo streams.
- `nowProvider` (`Provider<DateTime>`) — the clock seam. Live: `DateTime.now()`. Tests override to a
  fixed instant so urgency/routing/`metaOf` are deterministic.
- `HomeRouter` reads all three, calls the **pure** `routeHome(user, tasks, now)`, and renders the
  matching screen. There is **no ephemeral `screen` state** — `daily` / `cleared` / `emptyPool` /
  `targetHit` all fall straight out of `routeHome`, exactly as `screen` was spec'd client-only
  (HANDOFF §3). `routeHome` is the routing authority; it supersedes the prototype's inline
  `urg > 0.04` checks (which the Phase-1 `dueThreshold = 0.30` fix corrected).
- `dailyController` (a `Notifier` exposing async actions) holds **no screen state**. Each action
  reads the current `(user, tasks, now)` snapshot, calls the Phase-1 transition, awaits
  `repo.commit`, and fires any toast. The stream re-emit then re-derives the screen.

### Actions (`daily_controller.dart`)

| Action | Domain call | Toast |
|---|---|---|
| `complete(task)` | `complete(user, task, now)` | "Day streak secured for today" **iff** it banked (`!user.bankedToday` before the call) |
| `skip(task)` | guard `user.rerolls > 0`; if 0 → **no commit**, just toast; else `skip(user, task)` | rerolls 0 → "You're out of skips until tomorrow"; the skip that lands on 0 → "That was your last skip for today" |
| `remove(task)` | `remove(user, task)` | — |
| `keepGoing()` | `keepGoing(user)` | "Bonus round — your streak is safe" |

`skip` must never call the domain `skip()` with `rerolls == 0` (it asserts `> 0`). The controller
guards and short-circuits to the spring-back + toast path.

---

## C. The daily card (`swipe_card.dart`)

Serves **one** task: `selectTask(tasks, now)` (highest-urgency active; tie-break by `dueAt`
nulls-last, then `createdAt`). The card shows the task **title only** — no meta, no counters, no
badges. The halo is the sole urgency cue (HANDOFF §2, §7).

### Visual tokens (lifted from prototype)

- **Title:** `Newsreader` 500, 40.4px, line-height 1.16, letter-spacing −.015em, colour `#2b2824`,
  vertically centred, horizontal padding 30px. Use `TypeScale` (40.4 is a ladder step) + `serif`.
- **Halo:** a single blurred ellipse anchored below the card bottom. `mix(u)` is exactly
  `Palette.haloColor(u)` (calm `rgb(95,140,99)` → urgent `rgb(196,104,63)`). Geometry, as functions
  of `u = urgencyOf(servedTask, now)`:
  - size `sz = 340 + u*160` (px); width `sz`, height `sz*0.86`, fully rounded
  - blur radius ~62px, opacity `0.12 + u*0.5`, colour `haloColor(u)`
  - anchored centre-bottom, offset ~130px below the card's bottom edge
  - the halo grows, warms, and brightens with urgency; animate changes over ~.55s.
- **Chrome (top bar, ~52px from top):** left = manage button (40×40, white, rounded 13px, hamburger
  glyph, `#8a847a`); centre = "TODAY" overline (`Nunito Sans` 700, 9.8px, letter-spacing .2em,
  uppercase, `#c2bcae`); right = stats button (same chip, bar-chart icon). manage → `manage`
  placeholder, stats → `stats` placeholder.
- **FAB:** bottom-right, 56×56, rounded 19px, `#2b2824`, cream `+`. → `add` placeholder.
- **Hint labels** (revealed under drag): "✓ Done" pill top-left, bg `#5f8c63`, white text; "Skip ✕"
  pill top-right, bg `#6f8099`, white text. Both `Nunito Sans` 800, 11.1px, letter-spacing .12em,
  uppercase, rounded 20px. Opacity scales 0→1 with horizontal drag distance (Done = drag right,
  Skip = drag left).

### Gesture / physics (custom `GestureDetector` + `AnimationController`)

- Card follows the finger on horizontal drag with a slight tilt; vertical movement is mostly ignored.
- **Release past the commit threshold** (a fraction of card width, tuned to feel like the prototype):
  fling the card off-screen in the drag direction, then fire the action — right = `complete`,
  left = `skip`.
- **Release under threshold:** spring back to centre (`AnimationController`, ease-out curve
  ~cubic-bezier(.2,.8,.3,1), ~.25s).
- **Skip with `rerolls == 0`:** treat as under-threshold — spring back and toast "You're out of
  skips until tomorrow" (the card is **not** hard-disabled; it refuses on release).
- **Long-press → Remove:** a deliberate, separate gesture (~1100ms hold). While holding, show a
  centred "Hold to remove" affordance; completing the hold fires `remove`. Releasing early cancels.
- Between screens use a simple cross-fade (`AnimatedSwitcher`); richer choreography is polish, out of
  scope.

---

## D. Rest screens & toasts

All three use paper background, centred column, `Newsreader` headline + `Nunito Sans` body. Copy and
tokens are verbatim from the interactive prototype.

- **`emptyPool`** — sage ring glyph; headline "Your pool\nis empty" (`Newsreader` 500, 28.4px);
  body "Nothing to do, and nothing hanging over you. Add a chore whenever one turns up."
  (`Nunito Sans` 400, 15.8px, `#8f8a80`); CTA **"Add a chore"** (ink pill, cream text) → `add`
  placeholder.
- **`cleared`** — breathing sage-dot glyph; headline "You're on top of\nthings"; body "Nothing left
  in the pool. Enjoy the quiet."; CTA **"Review pool"** (outline pill, `#6f6a60`) → `manage`
  placeholder. **No "Keep going" / re-serve here** — `cleared` is terminal for the day; the only
  exit is reviewing the pool (decision confirmed in brainstorm).
- **`targetHit`** — row of `target`-count sage dots; "Daily target met" (`Newsreader` 500, 28.4px,
  `#5f8c63`); a two-stat card: **streak** ("Day streak / showed up", `Newsreader` 40.4px `#5f8c63`)
  and **targetMetDays** ("On target / hit full goal", `Newsreader` 40.4px `#2b2824`); body "You've
  done enough for today."; CTA **"Keep going!"** (outline pill) → `keepGoing()` → back to `daily`
  (serves any remaining due tasks; when they run out → `cleared`). This is the **one** place the
  streak number surfaces in the loop (HANDOFF "The reveal").

**Toasts (`toast.dart`):** top-anchored pill (`top` ≈ 100px, centred), bg `#2b2824`, cream text
(`Nunito Sans` 600, 12.4px), rounded 13px, slide-in from top, auto-dismiss (~2s). One at a time
(a new toast replaces the current). The four messages are listed in §B.

---

## E. App entry (`main.dart`)

`runApp(ProviderScope(child: JustOneApp()))`. `JustOneApp` is a `MaterialApp` with
`theme: buildAppTheme()` and `home: HomeRouter()`. Navigation to placeholder screens uses the
standard `Navigator` (`MaterialApp` routes / `Navigator.push`), so Phase 4/5 replace destinations
without touching the daily screen. The default Flutter counter `main.dart` and `test/widget_test.dart`
are replaced.

---

## F. Testing (TDD throughout)

- **`InMemoryRepository`:** `commit` replaces the user, merges `changedTasks` by id (changed task
  replaces same-id, others untouched, archived/removed retained), and re-emits; new subscribers get
  the latest value immediately.
- **`dailyController`:** banking toast fires only on the first completion of the day; `skip` with
  `rerolls == 0` does not commit and toasts "out of skips"; the skip landing on 0 toasts "last skip";
  `remove` commits removal; `keepGoing` sets `targetDismissed` and toasts "Bonus round".
- **`HomeRouter`:** renders `daily` / `cleared` / `emptyPool` / `targetHit` for the matching seeded
  `(user, tasks, now)` (drive routing through real `routeHome`, fixed `now`).
- **`SwipeCard`:** shows the served task's title and **no** counters/meta; hint labels reveal under
  drag (`WidgetTester.drag`); drag-right past threshold completes, drag-left past threshold skips,
  under-threshold springs back (no commit), long-press removes; with `rerolls == 0` a left fling
  springs back and toasts.
- **`targetHit` flow:** "Keep going!" returns to `daily` and shows the bonus toast.
- **Screens:** `emptyPool` Add CTA and `cleared` Review-pool CTA navigate to their placeholders.

Theme-dependent widget tests call `TestWidgetsFlutterBinding.ensureInitialized()` (google_fonts), as
in Phase 1.

---

## G. Default seed (manual run only; tests inject their own)

`UserState`: `target = 3`, `rerolls = 3`, `streak = 4`, `bestStreak = 4`, `doneToday = 0`,
`bankedToday = false`, `targetDismissed = false`, `onboardingComplete = true`,
`lastActiveDate = today (local)`. Tasks: ~5 entries seeded relative to `DateTime.now()` so the loop is
demonstrable — a couple of recurring chores due today (`dueAt ≈ now`, varied `intervalDays`), one
overdue recurring (drives a warm halo), one undated one-off, one future-dated one-off (not yet due).
At least one task must read as due (`urgencyOf > dueThreshold`) so the app opens on `daily`.

---

## Global constraints (carried into the plan)

- **No Firebase imports** anywhere in `lib/` this phase (data layer is in-memory only).
- `now` is always passed into domain calls — never `DateTime.now()` inside `lib/domain`; UI obtains
  `now` from `nowProvider`.
- Halo colour is `Palette.haloColor` — do not re-derive the calm/urgent interpolation.
- Daily screen carries **no** counters, badges, meta, or streak numbers — halo is the only ambient
  signal. The streak number appears only on `targetHit`.
- `routeHome` / `selectTask` / `isDue` from Phase 1 are the routing + selection authority; do not
  reintroduce the prototype's `urg > 0.04` cutoff.
- Files under ~1000 lines; YAGNI.
- Exact colour/type tokens as quoted above (from the prototype).
