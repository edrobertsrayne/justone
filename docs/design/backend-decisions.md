# Backend Implementation Decisions (Flutter + Firebase)

Working record from the backend grilling session (2026-06-22). Guiding principle:
**simplest implementation that functions as desired; YAGNI.**

---

## D1 — Daily reset: client-authoritative, server lazy-reads
The **client** owns the daily reset (runs on app-open by comparing `lastActiveDate` to the
local date; recomputes urgency, advances recurrence, clears `benched`, resets daily counters).
The **notification function** does NOT write a reset — when it reads a stale user doc it simply
*treats* `bankedToday`/`doneToday` as cleared-for-today for its "should I nudge?" decision.
Single writer, correct even on days the app was never opened.

## D2 — Local day / timezone
Store one IANA timezone string (e.g. `"Europe/London"`) on `users/{uid}`, captured from the
device (`flutter_timezone`) and refreshed on app open. Reminder times stored as wall-clock
strings (e.g. `"08:00"`), interpreted in that tz (library handles DST). Travel = updates next
app open; acceptable wrinkle.

## D3 — Notification scheduling
Cloud Scheduler fires the notification function **every 15 minutes**. Each run scans all user
docs, computes each user's local wall-clock from their tz, and sends FCM if a reminder time
falls in this window AND the streak isn't yet secured. No Cloud Tasks, no per-user scheduling,
no cancellation logic (banked → next run simply doesn't send).
- **Future iteration:** revisit **Cloud Tasks** for precise per-user reminder scheduling once
  scale / accuracy warrants it.

## D4 — FCM device tokens
Subcollection `users/{uid}/devices/{deviceId}`, each doc `{ token, platform, updatedAt }`.
Client writes/updates its own device doc on app open and on `onTokenRefresh`. Function sends to
every device token; on a `messaging/registration-token-not-registered` error it deletes that
device doc. Multi-token is a real requirement (phone + tablet both nudge). No extra dedupe/last-seen.

## D5 — Notification idempotency + escalation
Track `lastNotified: { date, count }` on the user doc. Each 15-min run: if `lastNotified.date`
≠ user's local today, treat count as 0; send the next un-sent reminder whose time has passed;
after sending write `count+1`. Idempotent (count only advances on a real send). **Escalation
copy is chosen server-side** by reminder index (last configured time → real-stakes copy);
notification text is owned by the Cloud Function, not the client.

## D6 — Urgency is computed, not stored
Store only raw inputs per task: `dueAt` (nullable timestamp), `intervalDays` (nullable int),
`createdAt`. `urg` (0–1) and `meta` (display label) are **derived client-side at serve time**
from `now` vs those inputs — never persisted. Pool is small (dozens), loaded whole, sorted in
Dart; no `orderBy(urg)` needed. Eliminates stale-urgency bugs and removes urgency-rewriting
from the daily reset.

## D7 — Daily reset writes user-doc counters + un-bench only
Reset touches NO task fields except `benched → active`. It writes user-doc fields
(`bankedToday=false`, `targetDismissed=false`, `doneToday=0`, `rerolls=default`,
`lastActiveDate=today`) and un-benches all benched tasks. No per-task urg/due rewrite (urg
computed per D6; recurring `dueAt` only moves on completion). **Supersedes** HANDOFF §4's
"advance recurring urg/due dates" line. Benched tasks need no `benchedDate` — next app-open
reset un-benches them regardless of elapsed days.

## D8 — Auth providers
**Google Sign-In only for v1**, mandatory (no anonymous auth — backup/sync requires a real
account on day one). Email/password deferred as a known-cheap later add (Firebase handles
hashing + hosted reset/verification emails; overhead is only client UX/error states — add it
at public release or when sign-in shouldn't be Google-tied). Apple Sign-In added when an iOS
app ships (Apple requires it if other social logins are offered).

## D9 — Counter writes / multi-device concurrency
Use `FieldValue.increment(1)` for purely-additive lifetime tallies (`lifetimeDone`,
`targetMetDays`) — free correctness. For today-counters and streak (`doneToday`, `bankedToday`,
`streak`, `rerolls`) accept **last-write-wins**; build NO conflict-resolution engine. Worst case
from the rare two-devices-offline-same-day race is an off-by-one that self-heals next day —
not worth CRDT complexity for a personal app.

## D10 — Flutter state management
**Riverpod (v2)** with `StreamProvider`s over the `users/{uid}` doc and the `tasks` collection
(UI rebuilds automatically as Firestore syncs offline→online). Ephemeral `screen` value held in
a `StateProvider`/`NotifierProvider`, never persisted. The selection engine (compute `urg`, pick
max) is a **pure Dart function** fed by the tasks stream — unit-testable with no Firebase.

## D11 — Complete-task mutation: client-side WriteBatch
The "complete a task" logic (archive/reset task, `doneToday+1`, conditional streak-bank on first
completion, conditional `targetMetDays++` on exact target hit) runs **client-side in a single
`WriteBatch`** — not a Cloud Function (must work offline) and not a Firestore transaction (the
conditional reads are already in memory from the live Riverpod stream). Writes task-doc +
user-doc atomically.
- **Anti-cheat is a permanent NON-GOAL** (not merely deferred): there will never be a leaderboard
  or any multi-user comparison; the app is purely personal motivation, so client-trusted streak
  math has no abuse cost. This collapses the "validate streak math in rules/functions" branch.

## D12 — Firestore security rules: owner-isolation only
Single pattern — signed-in users may read/write only their own `users/{uid}` tree (recursive
wildcard covers `tasks` + `devices` subcollections). No field validation, no schema/transition
enforcement, no streak-math checks (per D11), no custom rate limits (Firebase has built-in abuse
protection). The notification Cloud Function uses the Admin SDK and bypasses rules. Correct and
future-proof for public release in the only way that matters (data isolation).

## D13 — User-doc bootstrap + first-run detection
Create `users/{uid}` **client-side** right after first successful sign-in (`get()` → if missing,
write defaults incl. `timezone`, `target`, zeroed counters). No Auth `onCreate` Cloud Function
trigger (one less deploy artifact; triggers don't fire offline). Detect first-run via an explicit
`onboardingComplete: false` flag flipped true when the batch-seed wizard finishes — **not** by
inferring from an empty pool (an established account with an empty pool must route to `emptyPool`,
not re-run onboarding, per HANDOFF §1). Routing keys off the flag, not pool emptiness.

## D14 — Notification permission + token registration timing
Request the runtime notification permission (Android 13+/iOS) at the **end of onboarding**,
preceded by a one-line in-app rationale screen (not on cold welcome screen — early asks get
reflexively denied and denial is sticky). Register the FCM token (`getToken()` → write device
doc per D4, wire `onTokenRefresh`) **only after grant**. If denied, skip registration and offer
a **prominent** re-enable path in `settings` — the app is effectively useless without the nudge,
so the re-enable affordance must be easy to find, not buried.

## D15 — FCM message type: notification-payload
Nudges are sent as FCM **`notification`-type messages** (optional small `data` blob for
deep-linking, e.g. open the daily screen) — NOT data-only. The OS renders `notification` messages
even when the app is force-killed, preserving the OEM-kill resilience FCM was chosen for; data-only
messages can be dropped when the app is killed, defeating the purpose. Opacity is preserved: the
server puts only streak-status/escalation text (known server-side per D5) in the payload; the task
name never leaves Firestore until the app opens.

## D16 — Cloud Functions runtime
**TypeScript, Firebase Functions v2**, single `functions/` directory with one scheduled function
using `onSchedule("every 15 minutes", ...)` (provisions Cloud Scheduler on deploy — no manual
job). Chosen as the path of least resistance for a newcomer (most Firebase docs/examples are TS)
and for Admin-SDK type safety on Firestore field names. This is the one non-Dart part of the
project (Cloud Functions can't run Dart); duplicated field-names/reminder-logic are small.

## D17 — Reminder schedule schema
Single map on the user doc, the contract between the Flutter settings screen (writer) and the TS
function (reader):
```
reminders: {
  weekday: ["08:00", "18:30", "21:00"],   // 0–3 sorted wall-clock strings
  weekend: ["10:00", "20:00"]             // 0–3, independent
}
```
Wall-clock strings interpreted in the user's `timezone` (D2); array length = count (0–3, empty =
none); **escalation index = array index** (last → real-stakes copy per D5); weekday vs weekend
chosen by local day-of-week at send time. Seed sensible defaults at onboarding so it works day one.

## D18 — Environments
Develop against the local **Firebase Emulator Suite** (Auth + Firestore + Functions — free,
disposable, keeps test runs away from real streak data) + a **single real `justone-prod`
project** for real push on a device (FCM/Cloud Scheduler can't be meaningfully emulated). **No**
separate cloud dev project until the emulator stops sufficing. Don't develop against prod with
real data.

## D19 — Testing
Test scope is **owned by the TDD skill at build time** — not pre-scoped here. (Note: D10/D11
already isolate the selection engine and state transitions as pure Dart, which keeps them
test-friendly when TDD drives them out.)

## D20 — Server FCM reaffirmed over client-side local notifications
Explicitly reconsidered replacing server push with on-device `flutter_local_notifications`
(`zonedSchedule` + cancel-on-bank), which would delete the entire Cloud Functions/Scheduler/
FCM-token/server-reset stack — the biggest available simplification. **Rejected; keeping server
FCM.** Decisive reason: for a streak app, "app has been idle a while" is *both* the condition
that makes a nudge necessary *and* the condition under which aggressive-OEM battery-killers drop
local `AlarmManager` alarms — so local delivery fails exactly when it's most needed, whereas FCM
(via Play Services) does not. Server FCM also carries unchanged to public release. The extra
build complexity is accepted as worth it.

## D21 — Offline-completion vs server-nudge edge: accept and document
Known accepted limitation: if the user completes their first task **offline** and doesn't
reconnect before a reminder time, the 15-min scan sees stale `bankedToday=false` in Firestore and
sends a redundant (opaque, gentle) nudge for something already done. Self-corrects on sync; worst
case the user opens to a "target hit / cleared" screen. NOT mitigated — any fix reintroduces the
on-device-logic complexity FCM was chosen to avoid. Document, don't solve.

## D22 — Daily-reset trigger
Run the client reset check on **both cold start and every resume-to-foreground**
(`WidgetsBindingObserver` → `AppLifecycleState.resumed`). The check is idempotent: it compares
`lastActiveDate` to local date and no-ops when equal, so firing on every resume is free except
the first resume after midnight. Closes the "app left foregrounded/backgrounded across midnight"
gap (common on a tablet) that a cold-start-only reset would miss.

## D23 — Onboarding batch-seed write
Write the whole seed in **one `WriteBatch`**: all N task docs + user-doc updates (`target`,
`reminders` defaults, `onboardingComplete:true`, `lastActiveDate=today`) committed together.
Atomic flip means routing (D13) never sees "onboarded but no tasks" or vice-versa; offline-safe
(commits to local cache instantly, lands on a populated daily screen). Suggestion-chip picks and
typed entries are just more task docs in the batch. **No partial-resume** of the wizard — if the
app dies before commit, the user simply restarts the short wizard (not worth persisting partial
state).

---

## Consolidated Firestore data model (canonical)
Derived from D2, D4, D6, D13, D17, D23. `screen` and computed `urg`/`meta` are **never** stored.

```
users/{uid}
  # identity / config
  timezone           string   // IANA, e.g. "Europe/London" (D2), refreshed on app open
  target             int      // daily target 1–6, default 3
  reminders          map      // { weekday: ["08:00",...0–3], weekend: [...0–3] }  (D17)
  onboardingComplete bool     // first-run gate (D13)
  # streak / progress
  streak             int
  bestStreak         int
  targetMetDays      int      // FieldValue.increment (D9)
  lifetimeDone       int      // FieldValue.increment (D9)
  # today state (last-write-wins; reset client-side per D7)
  bankedToday        bool
  targetDismissed    bool
  doneToday          int
  rerolls            int      // default 3
  lastActiveDate     string   // local date, drives daily-reset rollover (D7/D22)
  # notification bookkeeping (server-written)
  lastNotified       map      // { date, count } idempotency + escalation (D5)

users/{uid}/tasks/{taskId}
  title       string
  kind        'one-off' | 'recurring'
  intervalDays int?    // recurrence rule (recurring only); meta derived, not stored (D6)
  dueAt       timestamp?      // set on completion = completedAt + intervalDays; nullable
  createdAt   timestamp
  completedAt timestamp?
  status      'active' | 'benched' | 'archived' | 'removed'
  # NOTE: urg + meta are COMPUTED client-side at serve time, never persisted (D6)

users/{uid}/devices/{deviceId}
  token       string          // FCM registration token (D4)
  platform    string
  updatedAt   timestamp
```

**Security:** owner-isolation only (D12). **Functions** use Admin SDK, bypass rules.

## Still open / not yet grilled (minor, client-side)
- Notification-tap deep-link routing specifics (open to daily screen via the `data` blob, D15).
- Exact engine *mechanics* (urgency curve, reroll count, streak grace) — deferred by design
  (`gamified-task-app-design.md` §11), not a backend concern.
