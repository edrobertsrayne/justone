# Phase 1 — Domain Core + Design System (spec)

Part of the [6-phase roadmap](../../IMPLEMENTATION-ROADMAP.md). This is the first slice: the
pure-Dart heart of **Just One** plus its design tokens. **No Firebase, no UI, no widgets** (beyond a
`ThemeData`). Everything here is deterministic and unit-testable, built test-first (D19).

Source of truth for behaviour: `docs/design/HANDOFF.md` (§3, §4, §6) and
`docs/design/backend-decisions.md` (D6, D7, D9, D10, D11, the canonical data model). Where this spec
adds detail beyond those (the urgency curve, undated-task handling), that detail was decided in the
Phase-1 brainstorm and is recorded in the roadmap.

## Goals

- A correct, tunable **urgency function** and `meta` label derivation (the one part the prototype
  left unspecified).
- A **selection engine** (which single task to serve) and a **screen-routing** function.
- **State-transition functions** for complete / skip / remove / keep-going / daily-reset that are
  pure (return intended writes; commit happens in Phase 3).
- A **design system**: colour tokens, halo interpolation, type scale, `ThemeData`.

## Non-goals (later phases)

- Firestore (de)serialization, repositories, streams, auth, `WriteBatch` commit → Phase 3.
- Any screen, widget, or gesture → Phase 2+.
- Cloud Functions, FCM, `lastNotified` writes → Phase 6. (`lastNotified` is *modelled* here as a
  read-only field but never written by the client.)

---

## Module layout

All under `lib/domain/` and `lib/theme/`. Each file one clear purpose, well under the 1k-line limit.

```
lib/domain/
  task.dart            // Task model + TaskKind, TaskStatus enums
  user_state.dart      // UserState (+ nested Config / Progress / Today value types)
  urgency.dart         // urgencyOf(task, now) -> double; metaOf(task, now) -> String
  selection.dart       // selectTask(tasks, now); isDue(task, now)
  routing.dart         // AppScreen enum; routeScreen(state, tasks, now)
  transitions.dart     // pure transition functions returning a TransitionResult
lib/theme/
  palette.dart         // colour tokens + haloColor(u)
  type_scale.dart      // modular scale + named TextStyles
  app_theme.dart       // ThemeData assembled from the above
```

---

## A. Domain models

Immutable value classes with `copyWith` and value equality (hand-written or via a small approach —
no codegen dependency unless trivially worth it). **No Firebase imports.**

### `Task`

| field | type | notes |
|---|---|---|
| `id` | `String` | unique |
| `title` | `String` | |
| `kind` | `TaskKind` | `oneOff` \| `recurring` |
| `intervalDays` | `int?` | required for `recurring`, null for `oneOff` |
| `dueAt` | `DateTime?` | recurring: last completion + interval (seeded = today). one-off: optional deadline. null = undated one-off |
| `createdAt` | `DateTime` | |
| `completedAt` | `DateTime?` | last completion |
| `status` | `TaskStatus` | `active` \| `benched` \| `archived` \| `removed` |

`urg` and `meta` are **NOT** fields — computed by module B (D6).

**Invariants** (asserted in a factory constructor, exercised by tests): `recurring ⇒ intervalDays != null && intervalDays > 0`; `oneOff ⇒ intervalDays == null`.

### `UserState`

Grouped for clarity; flattened to the single user doc in Phase 3.

- **Config:** `timezone (String)`, `target (int, 1–6, default 3)`, `reminders` (map: `weekday`/`weekend` → `List<String>` wall-clock, 0–3 each), `onboardingComplete (bool)`.
- **Progress:** `streak`, `bestStreak`, `targetMetDays`, `lifetimeDone` (all `int`).
- **Today:** `bankedToday (bool)`, `targetDismissed (bool)`, `doneToday (int)`, `rerolls (int, default 3)`, `lastActiveDate (DateTime`, local-date granularity).
- **Server-only (read, never written here):** `lastNotified` (`{date, count}`) — modelled as optional, ignored by all Phase-1 logic.

`copyWith` at the top level and per group.

---

## B. Urgency curve + meta

### `double urgencyOf(Task task, DateTime now)` → `[0, 1]`

A single **sigmoid in normalised lateness**, plus a special case for undated one-offs.

1. **Undated one-off** (`dueAt == null`): return a constant **`0.35`** (low actionable band). Always
   below any genuinely-due task, but `> 0.04` so it keeps surfacing and never gets stuck. (Decision:
   "surfaces, low priority".)
2. **Has `dueAt`** (recurring, or one-off with deadline):
   - `d = now.difference(dueAt).inDays` as a fractional day count (use hours/24 for smoothness).
   - `N = (kind == recurring) ? intervalDays : 7`  (one-off deadline pressure builds over the final week).
   - `r = d / N`.
   - `urg = 0.04 + 0.94 * sigmoid(2 * r)`, where `sigmoid(x) = 1 / (1 + exp(-x))`.
   - Clamp to `[0, 1]`.

**Tunable constants** (named, in one place, so TDD can adjust): floor `0.04`, span `0.94`, steepness
`2`, one-off horizon `7`, undated baseline `0.35`.

**Behaviour table (anchors the tests):**

| case | r | urg (approx) |
|---|---|---|
| recurring, half a cycle early | −0.5 | ~0.30 |
| due today | 0 | ~0.51 |
| one cycle overdue | +1 | ~0.87 |
| two cycles overdue | +2 | ~0.96 |
| far from due (r = −3) | −3 | ~0.042 (→ below the cleared threshold) |
| undated one-off | — | 0.35 (constant) |

Note the floor is `0.04` and the "cleared" threshold is `urg > 0.30` (`dueThreshold`). The sigmoid
*approaches* the floor from above but never reaches it, so the threshold must sit strictly above the
floor or `cleared` is unreachable. `0.30` ≈ the urgency a recurring task reaches ~half an interval
before due, so that is when it starts surfacing; a task far from due (r ≈ −3 → ~0.042) falls below
`0.30` and counts as *not due* (correctly yields `cleared`). The value is tunable. Verify the boundary
explicitly in tests.

### `String metaOf(Task task, DateTime now)`

Presentation label derived from the same inputs (D6 — never stored):

- `completedAt` is today → `"done today"`.
- Recurring, not yet due → `"due in N days"` / `"due tomorrow"` / `"due today"`.
- Overdue (recurring or one-off) → `"N days overdue"` / `"1 day overdue"`.
- One-off with future deadline → `"due in N days"` / `"due tomorrow"`.
- Undated one-off → `"no deadline"`.
- (Recurring cadence, e.g. `"every 7 days"`, is shown on the manage/add screens — Phase 4 — not
  derived here; `metaOf` is the daily-card label. Keep this function focused on the daily label.)

Day-boundary math uses local civil days, not 24h windows ("tomorrow" depends on the calendar date).
A small `daysBetweenLocalDates(a, b)` helper, unit-tested across DST and month boundaries.

---

## C. Selection + routing

### `bool isDue(Task task, DateTime now)` → `urgencyOf(task, now) > 0.30` (`dueThreshold`)

### `Task? selectTask(Iterable<Task> tasks, DateTime now)`

From tasks with `status == active`, return the one with the highest `urgencyOf`. Ties → earlier
`dueAt` (nulls last) → earlier `createdAt`. Deterministic. Returns `null` if no active task.

### `enum AppScreen { welcome, onboardTarget, onboardAdd, daily, cleared, emptyPool, targetHit, add, manage, settings, stats }`

The full enum lives here (it's domain vocabulary), but Phase 1 only *computes* the home-loop subset.

### `AppScreen routeHome(UserState state, List<Task> tasks, DateTime now)`

Encodes HANDOFF §4 routing for the post-auth, onboarded home loop:

1. No tasks at all (none with status `active`/`benched`, i.e. pool empty) → `emptyPool`.
2. `doneToday >= target && !targetDismissed` → `targetHit`.
3. No active task is due (`selectTask` is null **or** its urg ≤ 0.30) → `cleared`.
4. Otherwise → `daily`.

Auth/onboarding gating (`welcome`, `onboard*`) is layered on top in Phases 3/4 and is out of scope
here. `routeHome` assumes a signed-in, onboarded user.

---

## D. State transitions (pure)

Each transition takes the current `UserState` and the target `Task` (where relevant) plus `now`, and
returns:

```
class TransitionResult {
  final UserState user;
  final List<Task> changedTasks;   // single-element for complete/skip/remove;
                                   // empty for keepGoing; many for dailyReset
  // (Phase 3 commits user + changedTasks in one WriteBatch, D11.)
}
```

A single result type covers every transition (`complete`/`skip`/`remove` change one task,
`keepGoing` changes none, `dailyReset` un-benches many). No I/O, no clocks-of-their-own (always take
`now`). All TDD'd against the HANDOFF §4 rules.

### `complete(state, task, now)`
1. `doneToday += 1`, `lifetimeDone += 1`.
2. one-off → `task.status = archived`, `completedAt = now`.
   recurring → stays `active`, `completedAt = now`, `dueAt = now + intervalDays` (D6/D7: due advances
   only on completion).
3. **Bank streak** — if `!bankedToday`: `bankedToday = true`, `streak += 1`,
   `bestStreak = max(bestStreak, streak)`.
4. **Target** — if `doneToday == target` (exact hit): `targetMetDays += 1`. (The `targetHit` screen
   itself is produced by `routeHome`, not here.)

### `skip(state, task, now)`
`task.status = benched`; `rerolls -= 1`. (Guard `rerolls > 0` is enforced by the caller/UI; the
function asserts it. "Last skip" toast is a Phase-2 UI concern.)

### `remove(state, task)`
`task.status = removed`.

### `keepGoing(state)`
`targetDismissed = true`. (Returns no task change.)

### `dailyReset(state, tasks, now)` (D7)
Triggered when `lastActiveDate`'s local date ≠ `now`'s local date.
- User doc: `bankedToday = false`, `targetDismissed = false`, `doneToday = 0`,
  `rerolls = default (3)`, `lastActiveDate = now`.
- Tasks: every `benched` task → `active`. **No** task urg/due rewrite (urg is computed; recurring
  `dueAt` moved only on completion).
- Idempotent: if local dates already equal, returns the input unchanged (no-op) — safe to call on
  every resume (D22). `changedTasks` holds the un-benched tasks.

**Streak-break note:** v1 has **no streak-grace** (research §11). The streak counts consecutive local
days each with ≥1 completion. At reset (new local day detected), it zeroes iff
**`!bankedToday || gap >= 2`** — i.e. the day being left ended with no completion, or a full
intermediate day was skipped entirely. (A `gap == 1` day that *was* banked continues the streak.)
This is the one piece of streak logic that lives in `dailyReset`; covered by explicit tests
(consecutive banked day, opened-but-not-completed day, multi-day gap).

---

## E. Design system

Pure constants + a `ThemeData`; **no custom widgets**.

### `palette.dart`
- `paper #f3f1ec`, `ink #2b2824`, `mutedStrong #5c574e`, `muted #8f8a80`, `accent #5f8c63`,
  `terracotta #c2683f`, icon-cream `#efeae0`.
- `Color haloColor(double u)` — linear interpolate `rgb(95,140,99)` (calm) ↔ `rgb(196,104,63)`
  (urgent) by `u` clamped `[0,1]` (the prototype's `mix(u)`). Tested at u=0, 0.5, 1.

### `type_scale.dart`
- The major-second ladder (ratio 1.125, base 14) as named constants. Helpers for the documented
  roles (body 14, captions/labels stepping down, headings/numerals stepping up, overlines 9.8–11.1
  uppercase ~700, letter-spacing .14–.22em).
- Named `TextStyle`s pairing the ladder with the right family: `Newsreader` (serif — display,
  headings, task titles, numerals) and `Nunito Sans` (UI/body/labels). Fonts via the `google_fonts`
  package (add to `pubspec`) — simpler than bundling `.ttf`s.

### `app_theme.dart`
- A single `ThemeData` (paper scaffold, ink text, accent green seed) assembled from palette +
  type_scale, so Phase 2 screens inherit it. Light theme only (the paper aesthetic is fixed; no dark
  mode in v1 — YAGNI).

---

## Testing (TDD — D19)

Test-first, pure-Dart `flutter_test`, no Firebase. Priority coverage:

- **urgency:** the behaviour table above + the 0.04 boundary + undated constant + DST-safe day math.
- **meta:** each branch (done today / overdue / due soon / undated).
- **selection:** highest-urg pick, tie-breaking, empty pool, all-benched.
- **routing:** each of the four `routeHome` outcomes incl. the `targetHit`-once-per-day case
  (`targetDismissed` interaction).
- **transitions:** complete (one-off vs recurring; first-of-day banking; exact-target `targetMetDays`
  bump; non-exact no bump), skip, remove, keepGoing, and dailyReset (no-op same day; un-bench;
  counter reset; streak continuation vs break across a skipped day vs a multi-day gap).
- **palette:** `haloColor` endpoints + midpoint.

## Open / deferred

- Final urgency constants (steepness, horizon, undated baseline) — tunable; revisit after real use
  (research §11). The contract and test anchors are fixed; the numbers may move.
- `default rerolls = 3` is assumed; a settings control for it is not in v1.
