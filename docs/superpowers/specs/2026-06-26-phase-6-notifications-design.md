# Phase 6 — Notifications (design)

**Status:** approved, ready for implementation plan
**Date:** 2026-06-26
**Roadmap:** Phase 6 (final phase) of `docs/IMPLEMENTATION-ROADMAP.md`

The nudge layer. A scheduled Cloud Function scans user docs and pushes **escalating, opaque,
conditional** reminders that get the user over the *floor* (their first task of the day) — never
chasing the target, never naming the task, and suppressed the moment the streak is secured. Plus
the client plumbing: FCM token registration, a runtime-permission flow at the end of onboarding,
and a prominent re-enable path in Settings.

This is the one non-Dart part of the project (Cloud Functions can't run Dart). It is delivered as
**one phase covering both halves** — the Flutter client and the TypeScript function — because they
share a contract (the user-doc schema) and neither is useful alone.

## Source of truth / locked decisions

The backend grilling already locked most of the "what". This spec records the *how* and resolves
the few genuinely-open items. Governing decisions in `docs/design/backend-decisions.md`:

- **D1** — function never writes the daily reset; reads a stale doc as cleared-for-today.
- **D2** — IANA `timezone` on the user doc; reminders are wall-clock strings interpreted in it.
- **D3** — Cloud Scheduler fires every 15 minutes; scan all users; no Cloud Tasks, no cancellation.
- **D4** — FCM tokens in `users/{uid}/devices/{deviceId}`; dead-token cleanup on send error.
- **D5** — `lastNotified: {date, count}` idempotency + escalation; copy chosen server-side by index.
- **D14** — request permission at the **end of onboarding** behind a one-line rationale; register
  the token only after grant; prominent re-enable path in Settings if denied.
- **D15** — FCM **notification-type** messages (survive OEM kill); opaque (no task name in payload).
- **D16** — TypeScript, Functions v2, single `onSchedule("every 15 minutes", ...)`.
- **D17** — `reminders: { weekday: [...0-3], weekend: [...0-3] }`, sorted wall-clock strings;
  escalation index = array index; weekday/weekend by local day-of-week.
- **D18** — develop against the emulator; FCM/Scheduler can't be meaningfully emulated.
- **D20** — server FCM reaffirmed over on-device local notifications.
- **D21** — accept-and-document the offline-completion redundant-nudge edge.

Visual/copy source of truth: the lock-screen mock in `docs/design/Chore App Designs.dc.html`
(lines 1448–1474) and the "Notifications & sign-in" block.

## Decisions resolved in this brainstorm (2026-06-26)

1. **One spec, both halves** — client FCM plumbing + the Cloud Function together (matches the
   roadmap treating Phase 6 as one phase).
2. **Notification tap just opens the app** — no deep-link / `data`-routing. Opening already lands on
   `daily`/`cleared` via the existing `routeHome`. (Closes the "still open" deep-link item: v1 = none.)
3. **Catch-up = jump to the latest passed beat** — when several reminder times have already passed
   with nothing sent (rare: new install / function downtime), send only the most-escalated passed
   beat once and mark the rest covered, rather than backfilling a burst. A refinement of D5's literal
   "next un-sent reminder"; the normal case (one beat becomes due per run) is unchanged.
4. **Device doc id = the FCM token** — no new local-storage dependency. Token rotation plus the
   server's already-required dead-token cleanup (D4) self-heals any transient duplicate doc. Slight,
   accepted deviation from D4's "updates its own device doc" wording.
5. **Streak-0 copy variant** — the final "real stakes" beat can't say "your N-day streak ends" when
   there is no streak. At `streak == 0` the final beat uses warm "today's still open" framing instead.

---

## Part A — Client (Dart / Flutter)

### A1. `MessagingService` seam

`firebase_messaging` cannot run under `flutter test`, so wrap it behind a seam (mirroring the
existing `AuthService` pattern). New file `lib/notifications/messaging_service.dart`:

```dart
abstract class MessagingService {
  Future<bool> requestPermission();        // OS prompt; true = authorized
  Future<NotifPermission> permissionStatus(); // granted | denied | notDetermined
  Future<String?> getToken();              // current FCM token (null if unavailable)
  Stream<String> get onTokenRefresh;       // token rotations
}
```

- Real impl `FirebaseMessagingService` wraps `FirebaseMessaging.instance` (`requestPermission()`,
  `getNotificationSettings()`, `getToken()`, `onTokenRefresh`). `requestPermission()` covers both
  iOS and Android 13+ — **no `permission_handler` dependency**.
- A `messagingServiceProvider` exposes it; tests override it with a `FakeMessagingService`.
- `NotifPermission` is a small local enum mapped from `AuthorizationStatus` /
  `Settings.authorizationStatus` (`authorized`/`provisional` → granted; `denied` → denied;
  `notDetermined` → notDetermined). "Permanently denied" is inferred as `denied` after a prompt has
  already been shown (drives the Settings deep-link-to-OS-settings affordance).

### A2. `Repository.upsertDevice` — the only new seam method

Add **one** method to the `Repository` interface (the same way `newTaskId()` was Phase 4's only
addition):

```dart
Future<void> upsertDevice({
  required String token,
  required String platform,
  required DateTime now,
});
```

- `FirestoreRepository`: writes `users/{uid}/devices/{token}` = `{ token, platform, updatedAt: now }`
  (doc id = token, decision 4), `SetOptions(merge: true)`.
- `InMemoryRepository`: store devices in a map for test assertions.
- A `firestore_mappers` helper `deviceToFirestore(...)` keeps field names in one place.
- **No `deleteDevice` on the client** — only the server prunes dead tokens (D4). Keep the seam minimal.

Security rules already cover `devices` via the existing recursive `users/{uid}/{document=**}`
wildcard — **no rules change** this phase.

### A3. Registration controller

`lib/notifications/registration_controller.dart` — wires token lifecycle in the signed-in subtree:

- `registerIfGranted(now)`: if `permissionStatus() == granted`, `getToken()` → `repo.upsertDevice`.
  Called on app open (signed-in startup) so the doc's `updatedAt` refreshes and a server-pruned doc
  is re-added.
- Subscribes to `onTokenRefresh` → `upsertDevice` for the lifetime of the signed-in session.
- `requestAndRegister(now)`: `requestPermission()`; on grant → `getToken()` → `upsertDevice`;
  returns the resulting permission state. Used by both the onboarding step and Settings.
- Hosted by a `NotificationScope` widget wrapping the signed-in subtree (sibling pattern to the
  existing `DailyResetScope`): calls `registerIfGranted` once on init and owns the refresh
  subscription. It does **not** request permission (that is user-initiated).

### A4. Onboarding permission step (D14)

Extend the wizard (`lib/ui/onboarding_flow.dart`) from 2 steps to **3**: target → add → **rationale**.

- Step 3 is a calm one-line rationale ("Reminders are the whole point — a gentle nudge so today
  doesn't slip. You can change or silence them anytime."), with:
  - Primary **"Turn on reminders"** → `requestAndRegister(now)` → then `finish()` (commits the seed
    batch, flips `onboardingComplete`, routes to daily).
  - Secondary **"Not now"** → `finish()` straight through (no permission prompt; re-enable lives in
    Settings).
- Permission is requested **before** the `onboardingComplete` flip, so the OS dialog appears over
  the calm wizard, not over the daily card. Whatever the grant outcome, onboarding always completes
  (denial never blocks the app).
- The existing `_finish()` (seed-batch commit via `OnboardingController`) is unchanged; the new step
  only gates *when* it is called and whether a permission request precedes it.

### A5. Settings re-enable path (D14)

In `lib/ui/settings_screen.dart`, when `permissionStatus() != granted`, show a **prominent** card at
the top (not buried) — accent-framed, e.g. "Reminders are off · turn them on":

- If status is `notDetermined`/`denied` (prompt not yet exhausted): tap → `requestAndRegister`.
- If permanently denied (prompt already shown, still `denied`): tap → open OS app-settings (via the
  messaging service / an `openAppSettings` affordance) so the user can flip it manually.
- When granted, the card is absent and the existing reminder editor is the whole screen.

The reminder schedule editor itself already exists (Phase 4) and is unchanged — it writes the same
`weekday`/`weekend` arrays the function reads.

---

## Part B — Server (TypeScript, Functions v2)

Single `functions/` directory (D16). One scheduled function plus a pure decision core.

### B1. `decideNotification` — the pure core

`functions/src/decide.ts`, a pure function with no Firestore/FCM I/O — the bulk of the logic and the
bulk of the tests (mirrors the Dart `domain/transitions` philosophy):

```ts
type DecideInput = { user: UserDoc; now: Date };
type Decision = { send: false } | { send: true; index: number; title: string; body: string; count: number };
function decideNotification(input: DecideInput): Decision;
```

Logic:

1. **Local time** — derive the user's local wall-clock `HH:mm`, local date string, and day-of-week
   from the IANA `timezone` using the **built-in `Intl.DateTimeFormat`** with `timeZone` (DST-correct,
   **zero extra dependencies** — no luxon/moment-timezone).
2. **Stale-doc → cleared (D1)** — if `lastActiveDate` ≠ local today, treat `bankedToday=false` and
   `count=0` (the day rolled over server-side without an app open).
3. **Secured? (suppress)** — if the streak is secured for the local today (fresh doc &&
   `bankedToday == true`), return `{ send: false }`. Doing one task suppresses the rest.
4. **Pick the array** — `weekend` vs `weekday` by local day-of-week (Sat/Sun = weekend).
5. **Passed beats** — `passedCount` = number of reminder times ≤ local now. If `passedCount == 0` →
   `{ send: false }`.
6. **Jump-to-latest (decision 3)** — effective sent `count` = `lastNotified.count` if
   `lastNotified.date == localToday` else 0. If `passedCount > count`, send the **latest passed**
   beat: `index = passedCount - 1`, and return `count: passedCount` (covers the skipped earlier beats
   so they don't backfill). Otherwise `{ send: false }`.
7. **Copy** — chosen by `index` and `user.streak` (see B3).

### B2. Scheduled handler — the thin I/O shell

`functions/src/index.ts`:

- `onSchedule("every 15 minutes", ...)` (provisions Cloud Scheduler on deploy — no manual job).
- `now = new Date()` once per run. Query the `users` collection. For each user doc, call
  `decideNotification`. On `send: false`, skip.
- On `send: true`: read the `devices` subcollection; send an FCM **notification-type** message
  (`{ notification: { title, body } }`, no task name — D15) to each device token. Use
  `messaging.sendEach(...)` per-token so individual failures are isolated.
  - On a `messaging/registration-token-not-registered` (or `invalid-argument`) error for a token,
    **delete** that `devices/{token}` doc (D4).
  - If **every** token failed/deleted (no live device), **do not** advance `lastNotified` (nothing
    was delivered; nothing to be idempotent about).
- After at least one successful send, write `lastNotified: { date: localToday, count }` on the user
  doc (`count` from the decision).
- Admin SDK bypasses rules (D12). `setGlobalOptions`/function options keep `maxInstances` bounded.

### B3. Copy (server-owned, opaque, escalating)

Templates parameterized by escalation `index` and `streak`, lifted from the prototype lock-screen
mock. Title is constant ("Clearing"); body escalates:

- **Gentle beats** (every index except the last configured one): warm, low-stakes — e.g.
  "Morning. One small thing keeps your {streak}-day streak going." / "Still here whenever you are.
  The streak's yours to keep." None names the task.
- **Final beat** (last index in the active array): real stakes, calm — e.g. "Your {streak}-day
  streak ends if today stays empty. One task is all it takes."
- **Streak-0 variant (decision 5)** — when `streak == 0` there is nothing to lose, so the
  `{streak}-day streak` phrasings are replaced with start-framing — gentle: "A small first task and
  today's done." / final: "Today's still open. One task is all it takes." Never guilt, never all-caps,
  never an alarm tone.

Exact strings finalized at implementation time against the prototype; the contract here is
*index × streak → {title, body}*, all owned server-side.

---

## Data contract (unchanged schema)

The function reads the canonical user doc (`docs/design/backend-decisions.md`, consolidated model).
Fields it consumes: `timezone`, `reminders`, `streak`, `bankedToday`, `lastActiveDate`,
`lastNotified`. Fields it writes: `lastNotified`. Devices: reads tokens, deletes dead ones. **No new
fields, no schema migration.** Field names are duplicated from the Dart `firestore_mappers` into a
small TS `fields.ts` / typed `UserDoc` — the one accepted cross-language duplication (D16).

## Testing

- **`decideNotification` (jest, the bulk):** local-time derivation across timezones + DST; weekday vs
  weekend selection; `passedCount` boundaries (just-before / just-after a reminder time);
  jump-to-latest with multiple passed beats; idempotency (same run twice → second is `send:false`);
  stale-doc-as-cleared (D1); secured-suppression; streak-0 copy; empty reminder array → never sends.
- **I/O shell (`firebase-functions-test` + Firestore emulator):** per-user fan-out; `lastNotified`
  advance only on delivery; dead-token doc deletion on the registration-not-registered error; no
  `lastNotified` advance when all tokens are dead.
- **Client (`flutter test`, `FakeMessagingService`):** `registerIfGranted` upserts only when granted;
  `onTokenRefresh` upserts; `requestAndRegister` grant→upsert and deny→no-write; onboarding step
  routes through `finish()` on both "Turn on" and "Not now"; Settings shows the re-enable card iff
  not granted and hides it when granted; `upsertDevice` writes the right `devices/{token}` shape
  (`firestore_repository` + `in_memory_repository` tests).
- **Cannot be emulated (D18):** real FCM push + Cloud Scheduler firing. Covered by a **documented
  manual device smoke test** — a new `docs/superpowers/phase-6-manual-push-check.md` (sibling to the
  Phase-3 manual rules check): deploy the function to `justone-prod`, register a real device token,
  set a reminder a couple of minutes out, leave the streak unsecured, and confirm the notification
  arrives (and that completing a task before the next run suppresses the following beat).

## Out of scope (YAGNI / deferred)

- **Deep-link routing** on tap (decision 2 — v1 opens the app, nothing more).
- **Cloud Tasks** per-user precise scheduling (D3 explicitly defers).
- **The offline-completion redundant-nudge edge** (D21 — document, don't solve).
- **Anti-cheat / streak validation server-side** (D11 — permanent non-goal).
- **`permission_handler` dependency** — `firebase_messaging.requestPermission()` covers both platforms.
- A stable per-install device id beyond the token (decision 4).

## File map

New:
- `lib/notifications/messaging_service.dart` (seam + real impl + `NotifPermission`)
- `lib/notifications/registration_controller.dart`
- `lib/notifications/notification_scope.dart` (signed-in-subtree host)
- `functions/src/decide.ts`, `functions/src/fields.ts` (typed `UserDoc` + copy templates)
- `docs/superpowers/phase-6-manual-push-check.md`
- tests mirroring each of the above.

Changed:
- `lib/data/repository.dart` (+`upsertDevice`), `firestore_repository.dart`,
  `in_memory_repository.dart`, `firestore_mappers.dart` (+`deviceToFirestore`)
- `lib/ui/onboarding_flow.dart` (3rd step), `lib/ui/settings_screen.dart` (re-enable card)
- the signed-in startup wiring (mount `NotificationScope` alongside `DailyResetScope`)
- `functions/src/index.ts` (the scheduled handler replaces the scaffold)
