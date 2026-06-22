# Just One — Developer Handoff (Flutter + Firebase)

A one-task-a-day chore app. The whole product personality is **restraint**: it surfaces the single
task that matters most right now and mutes everything else. Build to that principle — no badges,
counters, or streak numbers on the daily screen; the card's only ambient signal is *warmth* (a halo
whose colour/intensity encodes urgency).

The interactive reference is `Chore App Designs.dc.html` (open in a browser) — a **high-fidelity** HTML
prototype showing intended look and behaviour, **not** production code to copy. Recreate it idiomatically
in Flutter (don't port the JS). All design dead-ends (rejected icons, palette options, alternative
directions) have been removed — **everything left in the file is the design to build.** The file also
contains the locked brand mark and the urgency / notification specs.

---

## 1. Screens / navigation

Single-screen-at-a-time model driven by one `screen` value. Screens:

| screen | When shown | Purpose |
|---|---|---|
| `welcome` | First launch / signed out | Wordmark + sign-in (any provider) |
| `onboardTarget` | First run, after sign-in | Set daily target (1–6) |
| `onboardAdd` | First run | Batch-seed the pool from typed entries + suggestion chips |
| `daily` | Default home | Serves the single highest-urgency due task as a swipeable card |
| `cleared` | Pool non-empty but nothing currently *due* | Calm "done enough, see you tomorrow" rest screen + *Keep going* |
| `emptyPool` | Pool has zero tasks | Quiet empty state + **Add a chore** CTA (routes to `add`, NOT onboarding) |
| `targetHit` | First time daily target is met today | Celebration + *Keep going* (bonus round) |
| `add` | FAB / Add a chore / edit | Create or edit a task (title, deadline, recurrence) |
| `manage` | Manage pool | List/edit/remove all tasks |
| `settings` | Settings | Target, notifications |
| `stats` | Stats | Streak hero — the one deliberately loud moment in the app |

**Onboarding decision (confirmed):** onboarding runs **only on first run** (batch seed). When an
established account's pool runs dry you land on `emptyPool` with a single **Add a chore** CTA — do
**not** re-run the onboarding wizard. (Optional future nicety: a secondary "browse suggestions" link
on the very first time a pool empties.)

---

## 2. The daily card — interaction

The home card serves **one** task: the active task with the highest `urg` (urgency 0–1).

- **Swipe right → Done.** Completes the task.
- **Swipe left → Skip** (a "reroll"). Benches the task for today; limited to `rerolls` per day (default 3).
- **Long-press → Remove** from the pool entirely.
- Card follows the finger; "Done"/"Skip" hint labels reveal under the drag.
- Swipe physics + reactive limits: when skips run out, the skip affordance is disabled (toast warns on last skip).

### Urgency → halo
`urg` (0 = calm, 1 = urgent) maps to a halo colour interpolated between calm green `rgb(95,140,99)`
and urgent terracotta `rgb(196,104,63)` (see `mix(u)` in the prototype). This single cue replaces all
"overdue" labels on the daily screen.

---

## 3. State model

Per-user state (current prototype shape — map to Firestore, see §5):

```
screen            string   // ephemeral UI state, NOT persisted
target            int      // daily target, 1–6 (default 3)
streak            int      // current consecutive-day streak
bestStreak        int
targetMetDays     int      // lifetime count of days target was reached
bankedToday       bool     // has today's streak been secured (first task done)
targetDismissed   bool     // has the user tapped "Keep going" after hitting target today
doneToday         int      // tasks completed today
lifetimeDone      int
rerolls           int      // skips remaining today (default 3)
tasks             Task[]
```

```
Task {
  id        // unique
  title     string
  urg       float    // 0–1 urgency, drives serving order + halo
  meta      string   // human label e.g. "2 days overdue", "due tomorrow", "every 7 days"
  kind      'one-off' | 'recurring'
  rec?      string   // recurrence rule for recurring, e.g. "every 3 days" / "every 14 days"
  status    'active' | 'benched' | 'archived' | 'removed'
}
```

`status` semantics: `active` = eligible to serve · `benched` = skipped today (returns tomorrow) ·
`archived` = completed one-off (gone) · `removed` = pulled from pool by user.

---

## 4. Core logic rules

**Complete a task (Done):**
1. `doneToday += 1`; `lifetimeDone += 1`.
2. One-off → `status:'archived'`. Recurring → stays `active`, `urg` reset to ~0.03, `meta:'done today'`.
3. **Banking the day streak:** the *first* task completed each day sets `bankedToday=true` and
   `streak += 1` (update `bestStreak`). Toast: "Day streak secured for today".
4. **Target met:** when `doneToday >= target`:
   - On the exact hit (`doneToday === target`) increment `targetMetDays`.
   - Show the `targetHit` celebration **only if `targetDismissed` is false**. Otherwise fall through
     to the normal daily/cleared flow. ← *recent fix: the celebration shows once per day.*
5. Else if no active task has `urg > 0.04` → screen `cleared`.

**Keep going** (from `targetHit` or `cleared`): set `targetDismissed=true`, return to `daily`.
Toast: "Bonus round — your streak is safe". Subsequent completions today route straight to daily/cleared.

**Skip:** task → `benched`; `rerolls -= 1`; if pool now has nothing due → `cleared`. Toast on last skip.

**Remove:** task → `removed`; if nothing due → `cleared`.

**Daily reset (build this — prototype seeds it via onboarding):** at the start of a new local day,
reset `bankedToday=false`, `targetDismissed=false`, `doneToday=0`, `rerolls=` default; un-bench
benched tasks; advance recurring-task `urg`/due dates per their `rec` rule.

**Empty vs cleared (important distinction):**
- `cleared` = tasks remain but none are due → warm rest screen.
- `emptyPool` = zero tasks → empty state with Add CTA.

---

## 5. Firebase mapping (suggested)

**Auth:** Firebase Auth (the welcome screen's "any button" stands in for real providers — Apple/Google/email).

**Firestore:**
```
users/{uid}
  target, streak, bestStreak, targetMetDays, lifetimeDone
  bankedToday, targetDismissed, doneToday, rerolls
  lastActiveDate            // for the daily-reset rollover
users/{uid}/tasks/{taskId}
  title, urg, meta, kind, rec, status, createdAt, completedAt, dueAt
```
- `screen` is **client-only** UI state — never persist it.
- Do the **daily reset** on app open by comparing `lastActiveDate` to the local date (and/or a
  Cloud Function scheduled per timezone) — recompute recurring due dates, clear `benched`, reset the
  daily counters.
- Recurrence: store `rec` as a structured rule (`intervalDays`) rather than the display string; the
  `meta` text is presentation, derive it.

**Notifications (FCM):** pushes nudge you over the *floor* (your first task of the day), never chase
the target. Each fires **only if** the relevant condition still holds at send time (e.g. don't send
"do your first task" if it's already banked). Escalating, conditional — see the lock-screen mock in
the prototype.

---

## 6. Visual system

- **Type families:** `Newsreader` (serif — display, headings, task titles, numerals) + `Nunito Sans` (UI / body / labels).
- **Type scale:** a **major-second modular scale, ratio 1.125, base 14px**. Steps (px):
  `8.7 · 9.8 · 11.1 · 12.4 · `**`14`**` · 15.8 · 17.7 · 19.9 · 22.4 · 25.2 · 28.4 · 31.9 · 35.9 · 40.4 · 45.5 · 51.1 · 57.5 · 64.7 · 72.8`.
  14px is body; step **down** for secondary text / labels / captions, **up** for headings, the target/streak numerals, and the clock. Overlines/eyebrows are 9.8–11.1px uppercase, ~700 weight, letter-spacing .14–.22em. Line-height: ~1.5–1.65 for body, ~1–1.2 for headings. Every size in the prototype already snaps to this ladder — read sizes off the markup directly.
- **Paper / ink:** background `#f3f1ec`, ink `#2b2824`, muted text `#8f8a80` / `#5c574e`.
- **Accent green:** `#5f8c63` family; urgent terracotta `#c2683f`/`rgb(196,104,63)`.
- **Device frame** corners, halo gradients, dot rows, and button styling are all spec'd inline in the
  prototype markup — lift exact values from `Chore App Designs.dc.html` (the daily / cleared / emptyPool /
  targetHit screen blocks in the interactive-prototype section).
- **App icon (locked) — "Sage knockout":** a sage dot `#5f8c63` with the checkmark knocked out in paper
  `#efeae0` as a single playful sweep. Two platform builds, both in the file's *"Sage knockout — the mark"* section:
  **Android / adaptive** = the sage dot centred with breathing room on a `#efeae0` tile (survives circular &
  adaptive-icon masking); **iOS** = full-bleed sage tile with the cream tick. The same tick sweep marks the
  welcome screen, the auth screen, and the notification badges — keep it consistent. Wordmark: **Just One**
  (Newsreader, 500).

---

## 7. Build notes

- Replicate behaviour and visual spec from the prototype; it is the source of truth for *what it does*
  and *how it looks*. It is React/HTML — re-implement idiomatically in Flutter, don't port the JS.
- Hit targets ≥ 44px. Keep the daily screen free of counters/badges — restraint is the product.
- Keep the two empty states distinct (`cleared` vs `emptyPool`).
- The streak/stats screen is the only intentionally loud surface — give it weight.

---

## 8. Files in this bundle

- `Chore App Designs.dc.html` — the high-fidelity interactive reference. **Open it in a browser** to
  click through onboarding → daily loop, and to read exact colours/sizes/spacing off the markup. It is a
  self-contained HTML prototype (it loads its sibling `support.js`); it is a *design reference*, not code
  to ship — recreate it in Flutter.
- `support.js` — runtime needed only so the HTML reference renders in a browser. **Not** part of the app;
  do not port it.
- `README.md` — this document. Self-sufficient spec; the HTML is the visual source of truth.

No external image/font assets are required beyond the two Google Fonts (`Newsreader`, `Nunito Sans`); the
icon and all imagery are drawn in markup/SVG and described in §6.
