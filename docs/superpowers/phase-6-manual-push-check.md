# Phase 6 — manual push check (not automatable, D18)

Real FCM delivery + Cloud Scheduler cannot be emulated. Run this once against the
real project (`just-one-db69c`) on a physical Android device before relying on nudges.

## Setup
1. `flutter run --dart-define=USE_EMULATOR=false` on a physical device, sign in,
   finish onboarding, and tap **"Turn on reminders"** (grant the OS prompt).
2. Confirm a doc appeared at `users/{uid}/devices/{token}` in the Firestore console.
3. Deploy the function: `firebase deploy --only functions` (provisions the
   "every 15 minutes" Cloud Scheduler job automatically).

## Delivery
4. In Settings, set a reminder time ~2 minutes out (weekday/weekend to match today).
   Make sure today is **not** banked (don't complete a task).
5. Background or kill the app. Within the next 15-minute scan boundary, confirm a
   notification arrives titled **"Clearing"** with opaque body text (no task name).

## Conditional suppression
6. Reopen the app and complete one task (banks the streak). Confirm that subsequent
   reminder times today produce **no** further notification.

## Dead-token cleanup
7. Sign out / uninstall to invalidate the token, leave a reminder pending, and after
   a scan confirm the stale `devices/{token}` doc is deleted.

## Escalation
8. With three reminder times configured and an unsecured day, confirm the final beat
   uses the warmer real-stakes copy ("...streak ends if today stays empty...").
