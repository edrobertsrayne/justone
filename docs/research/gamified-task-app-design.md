# Gamified Task App — Design Decisions

A working design record for a gamified **chore** app. The core idea: instead of staring at a prioritised list, the app **pushes you one task at a time** each day and you simply do it or skip it. Selection is weighted by time pressure so that what surfaces is already biased toward what's becoming due.

**Status:** Stack and UX settled. Engine *mechanics* (the weighting curve, exact streak-grace rules) deferred to a later session.

**Guiding ethos:** calm, zen, decision-free. The app's distinctiveness is restraint — it shows one thing, nudges a few times at most, then respects your "no". Knowing when to stay quiet is the product.

---

## 1. Core concept

- A daily, push-driven loop designed to **drive a streak actively**, not let one build passively.
- Removes decision-making: you are shown **one task at a time**; the only choice is *do it or not*.
- Scoped deliberately as a **chore tool, not a detailed task-management tool**. Short, simple tasks; quick entry.
- **Single pool** of tasks (no home/work split — see §10).
- Personal project first, but **cloud-backed and multi-device (phone + tablet) from v1**. A public multi-user release is a plausible later step and is now much closer to reach (auth + sync already present).

---

## 2. Stack (locked)

| Layer | Choice | Rationale |
|---|---|---|
| Client | **Flutter** | Mobile-only (no web frontend), which is Flutter's sweet spot; first-class Firebase integration (FlutterFire); mature local-DB, offline and notification stories. |
| Backend | **Firebase** | First-party-blessed for Flutter; **Firestore** gives turnkey offline-first sync across devices; **Firebase Auth**; **Cloud Functions + Cloud Scheduler** for the per-user daily nudge; **FCM** for reliable push. Google lock-in accepted as a worthwhile trade for cohesion. |
| Data store | **Firestore** | Persistence + automatic multi-device sync with an offline local cache. The pool is small (dozens of tasks), so selection is a code operation over a loaded candidate set, not a heavy query — NoSQL is fine here. |
| Push | **FCM (server-sent)** | Delivered via Google Play Services, **whitelisted at system level on all Android OEMs**, so it isn't suppressed by Samsung/Xiaomi/etc. battery-killers the way on-device alarms are. This reliability is the decisive reason for server-scheduled push. |
| Scheduling | **Cloud Functions + Cloud Scheduler** | A periodic function finds users whose nudge time has arrived and whose streak isn't yet secured today, and sends the FCM push. |
| Selection engine | **Dart module, client-side** | Runs on-device when the app opens, against the synced Firestore cache. Because notifications are *opaque* (§6), selection need not run server-side at notification time. |

- **Mobile-first** because the daily nudge must reach the user via push, not rely on a website being open. No web frontend.
- **Why not local-only?** A local SQLite + export/import design was considered. Rejected because a cloud backend solves three wants at once — lost-phone **backup**, **phone+tablet** use, and **OEM-proof push reliability** (local alarms get killed on aggressive OEMs; FCM does not) — and de-risks an eventual public release.
- **Why Firebase over Supabase?** Best-in-class offline sync for Flutter and tight FCM/Auth cohesion. Supabase (Postgres, self-hostable) was the alternative; its edge — avoiding lock-in — was judged less valuable here than turnkey sync + push.

---

## 3. The daily loop (locked)

The central screen shows **one task card at a time**. No visible list, no manual prioritising, no ordering decisions. The card is **zen**: the task itself, plus **one ambient urgency cue** (e.g. a subtle warmer accent the more overdue it is) and nothing else. A subtle pressure hint was found to increase the likelihood of acting on the served task. All other metadata lives in the management screen.

**Gestures**

| Gesture | Action | Counts toward target? | Costs a reroll? | Effect |
|---|---|---|---|---|
| Swipe right | **Done** | ✅ Yes | — | Logs completion. One-off → archived; recurring → rescheduled (today + interval). |
| Swipe left | **Skip** | ❌ No | ✅ Yes | Benched until tomorrow; cannot be re-rolled again the same day. Stays in pool. |
| Long-press (secondary) | **Remove from pool** | ❌ No | ❌ No | Housekeeping for irrelevant tasks. Distinct from the swipes. Safety valve so the loop never dead-ends. |

- **Done vs Remove are semantically opposite**: only *Done* advances anything. If Remove counted, the streak would be gameable.
- **Rerolls limited** (~3/day, exact count tuned later). Skip consumes one.

---

## 4. Daily screen — information & states (locked)

**Fully zen — no ambient information on the daily screen.** No day-progress pips, no visible reroll counter, no persistent streak count.

- **Reroll state is revealed reactively only:** no counter; when you attempt the skip that would exceed the limit, the card gently says it's your last one (or that you're out).
- **Streak is shown only at the target-hit moment** (and carried by notifications — see §6). It does not sit on the daily screen.

**Three distinct success/empty screens** — same calm tone, different meaning:

1. **Target hit ("done for today").** Streak banks immediately with a satisfying reveal → "you've done enough, see you tomorrow." Tasks may still remain. Includes a **low-key, optional "keep going?"** — bonus tasks are pure upside, never put the banked streak at risk.
2. **Cleared pool ("all done").** Nothing left to serve → a quiet **win-state** ("you're on top of things"), not an error.
3. **First-run / empty pool (new user).** A designed onboarding screen with a single call-to-action pointing at the **FAB** ("add your first chore"). Minimal — not a heavy guided walkthrough.

---

## 5. Streak & reward model (locked — mechanics deferred)

**Decoupled into two tiers**, which dissolves the hard-fail/soft-landing dilemma:

- **Streak = showing up.** Completing **≥1 task** keeps the chain alive. A low, humane floor; a reset only happens on a genuine **zero day**.
- **Target = doing well.** Hitting **N tasks** (e.g. 3) is a **separate, additive reward**.

**Hard rule — only one losable thing.** The consistency streak is the *only* thing that can be lost. The target reward must be **accumulating and never losable** (a tally of full days / XP / badges — *not* a second fragile "perfect streak"), or it would smuggle back the dread the design removes.

- Because the floor is so forgiving, streak-break rules are low-stakes — a token grace for real-life gaps may be enough, or none. Deferred to the mechanics session.
- "Completed day" for the *reward* tier is strict (target = N). The streak tier's bar is ≥1.

---

## 6. Notifications (locked)

Notifications exist to nudge you over the **streak floor** (your first task), not to chase the target. **Once the daily activity is done, no further pushes that day** — completion must never feel "busy".

- **Mechanism: server-scheduled FCM.** A Cloud Function (driven by Cloud Scheduler) reads each user's reminder schedule and current streak state from Firestore, and sends the push if the streak isn't yet secured. Server-side state makes the streak count and the "secured → suppress later reminders" logic straightforward, and FCM delivery is OEM-reliable.
- **Content: opaque.** The push motivates and carries **streak status** but does **not** name the task; the task is revealed only on opening the app (selection runs client-side then). Protects the reveal and prevents lock-screen pre-screening (a free skip bypassing the reroll limit). *Flagged to revisit after real use* — revealing the task lowers friction to act.
- **Cadence: user-controlled, up to 3 reminder times**, with sensible defaults so it works on day one. Separate **weekday vs weekend** defaults. Typical shape: morning nudge, early-evening nudge, late-evening beat. Weekends later and looser.
- **Conditional, not fixed pings.** Each reminder fires *only if the streak isn't yet secured*; securing it suppresses the rest that day.
- **Escalation: calm recurrence + one restrained final beat.** Reminders 1–2 are gentle and near-identical; the **final** one surfaces the real stakes ("your streak ends if today stays empty"). **Ceiling on intensity = a calm statement of real stakes** — never guilt, all-caps, or alarms.

---

## 7. Task model & capture (locked)

**Capture: frictionless quick-add via a FAB.** Title only → task created at baseline → back to your day. Optional **enrichment** afterwards (a confirmation/edit sheet) to add a **deadline** and/or **recurrence/cadence**. Enrichment is progressive, never mandatory; defaults are safe (one-off, no deadline = baseline weight) so the engine always has valid values.

**Recurrence: rolling interval only.** "Every N days since last completed." Done → next target date = today + interval. One-off tasks: Done → archived. Fixed-calendar cadences ("bins every Tuesday") are **out of scope** — better served by a calendar reminder; possible v2 with deterministic surfacing.

**Weighting: time pressure is the *only* lever.** All tasks carry **equal baseline weight**; the sole differentiator is **due-date pressure / recurrence cadence**. A task with no deadline and no cadence sits at baseline and surfaces via random draw — the original "randomly select a chore" inspiration.

**Task states:** `active` / `skipped-till-tomorrow` / `done-today` / `due-in-future` / `archived`.

---

## 8. Management screen (locked)

A **deliberately secondary, edit-only utility surface** — not a first-class tab. The daily swipe screen is home.

- **You cannot *complete* a task from the list** — doing a task lives exclusively on the swipe surface, keeping a single sacred "do it" path.
- Fully capable for grooming: add, edit, set deadline/recurrence, remove, see last-done.
- **One obvious tap away, not buried** — enrichment is where the engine gets its time-pressure signal, so tasks must not calcify at baseline.

---

## 9. Auth & multi-device (v1)

- **Firebase Auth** with a sign-in screen.
- **Multi-device from day one** (phone + tablet) via Firestore offline-first sync: the pool, streak, target and history are shared and reconcile automatically across devices, working offline and syncing when connected.
- Cloud persistence makes **backup** inherent — a lost or reset phone no longer loses data.
- Already-auth'd + synced means a public multi-user release is closer to "turn it on" than a rebuild.

---

## 10. Decisions reversed from the original vision

Recorded deliberately, with reasoning:

- **Eisenhower matrix — dropped entirely.** *Urgency* is the same axis as a due date (time-to-act), expressed worse → double-counting, so urgency now *emerges* from time pressure rather than being declared. *Importance* is genuinely orthogonal but subjective, prone to drifting to "high", and low-variance in a chore pool → dropped for v1. Net: one honest, factual lever (time pressure). (Possible future: an optional "star/boost" for important deadline-less tasks — opt-in, not v1.)
- **Home/Work separate pools — dropped (settled).** Predicated on the tool doing *work task management*, which the chore-tool framing disclaims. **Single pool, single streak, single target** — committed deliberately to reflect the simplicity the whole design pursues, not left as an open question. Compartmentalisation is explicitly a non-goal for this tool.

---

## 11. Deferred / open

**Engine mechanics (next session)**
- The **due-date pressure curve**: how draw probability rises with overdue-ness / approaching cadence.
- **Reroll count** tuning (~3).
- **Streak grace** mechanism, if any (low-stakes given the forgiving floor).
- Form of the **additive reward** (full-day tally / XP / badges) — accumulating, never losable.
- Exact **default reminder times** for weekday/weekend.

**Revisit after real use**
- Opaque vs task-revealing notifications.
- Whether an optional **importance boost** is ever needed.
- **Multi-device concurrency** edge cases (e.g. acting on phone and tablet the same day) — likely negligible for personal use; revisit if it bites.

**Later / public release**
- Points-based scoring as a possible v2.
- Fixed-calendar cadence support (v2, deterministic surfacing).
- Hardening Auth, Firestore security rules, and abuse/scale concerns for genuine multi-user.
