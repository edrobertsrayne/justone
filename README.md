# Just One

A one-task-a-day chore app. It surfaces the single chore that matters most right now and mutes
everything else — the whole product personality is **restraint**. Built with Flutter + Firebase
(Cloud Firestore, Firebase Auth) and Riverpod.

This README focuses on **running the app locally against the Firebase Emulator Suite** for
hand-testing. For the product spec see `docs/design/HANDOFF.md`; for the build sequencing and
architecture decisions see `docs/IMPLEMENTATION-ROADMAP.md` and `docs/design/backend-decisions.md`.

---

## Prerequisites

| Tool | Notes |
|------|-------|
| **Flutter SDK** | Dart `^3.13` (see `pubspec.yaml` `environment:`). `flutter --version` should show a recent stable. |
| **Firebase CLI** | `npm i -g firebase-tools`. Provides the Emulator Suite. |
| **Java JDK 11+** | Required by the Firestore emulator. |
| A device/emulator to run on | Android emulator, iOS simulator, or `-d chrome` for web. |

The Firebase project is **`just-one-db69c`** (`.firebaserc`). You don't need access to it for
emulator-based local testing — the emulator runs entirely offline.

One-time install of Dart deps:

```bash
flutter pub get
```

---

## How the emulator wiring works

`lib/main.dart` points the app at the local emulators automatically **in debug builds**:

```dart
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: kDebugMode);
// ...
if (kUseEmulator) {
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
}
```

So `flutter run` (a debug build) talks to the emulator with no flags. Ports (from `firebase.json`):

| Service | Port |
|---------|------|
| Auth | `9099` |
| Firestore | `8080` |
| Emulator UI | `4000` (default) |

To force a build to talk to the **real** `just-one-db69c` project instead, pass
`--dart-define=USE_EMULATOR=false` (needed for real Google Sign-In and push — see the limitation
below).

---

## Run it locally against the emulator

### 1. Start the emulators

In one terminal, from the repo root:

```bash
firebase emulators:start
```

This serves Auth (`:9099`), Firestore (`:8080`), and the Emulator UI at <http://localhost:4000>.
Leave it running.

### 2. Seed a user and launch into the daily loop (recommended)

The normal app entry point uses **real Google Sign-In**, which does not route through the Auth
emulator (Google OAuth is a live service — see the limitation below). For pure local testing there
is a dev-only entry point that signs in **anonymously** against the Auth emulator and writes a
ready-made, already-onboarded pool of sample chores, so you land straight on the daily card:

```bash
# in a second terminal, with the emulators still running
flutter run -t tool/seed_emulator.dart -d <device>
```

It prints the seeded `uid` and a handful of tasks. You can now exercise the daily loop, add/edit
(the `+` FAB), manage the pool (top-left menu), and settings (the gear in Manage). Inspect the
written data live in the Emulator UI at <http://localhost:4000/firestore>.

`tool/seed_emulator.dart` is **dev-only** — it is never shipped and nothing in `lib/` references it.

### 3. (Alternative) Run the full app, including first-run onboarding

```bash
flutter run -d <device>
```

This boots the real entry point (`lib/main.dart`) → welcome screen → first-run onboarding wizard →
daily loop. See the Google Sign-In limitation immediately below.

---

## Limitation: Google Sign-In vs. the Auth emulator

The welcome screen's **"Continue with Google"** uses the `google_sign_in` plugin, which obtains a
token from **live Google OAuth** — that handshake does not go through the Auth emulator. So the
full first-run flow (welcome → onboarding) is best exercised against the **real** project on a real
device:

```bash
flutter run --dart-define=USE_EMULATOR=false -d <device>
```

(This requires the platform Firebase config to be present — `android/app/google-services.json` is
committed; iOS needs its `GoogleService-Info.plist`.)

For everyday local development against the emulator, prefer the **seed entry point** (step 2),
which bypasses Google by using anonymous auth — it's the fast path to a populated, interactive app.

---

## Running the tests

The test suite is **Dart-fakes-only** (`fake_cloud_firestore` + `firebase_auth_mocks`) and needs
**no emulator or device**:

```bash
flutter test
flutter analyze
```

---

## Verifying the security rules

The Dart fakes have no rules engine, so the owner-isolation rules (`firestore.rules`) are checked
**by hand against the emulator** whenever they change. Follow the step-by-step in
`docs/superpowers/phase-3-manual-rules-check.md` (uses the Emulator UI's Rules Playground).

---

## Not yet wired up

- **Push notifications / reminders.** The `functions/` directory (TypeScript Cloud Functions) and
  the FCM token registration / runtime permission flow are **Phase 6** and not implemented yet. The
  settings screen currently only *writes* the reminder schedule; nothing sends reminders. FCM and
  Cloud Scheduler can't be meaningfully emulated, so that work is verified on a real device against
  `just-one-db69c`.

---

## Project layout

```
lib/
  domain/   pure Dart: models, urgency curve, selection, routing, transitions, edits
  data/     Repository seam + Firestore/in-memory implementations + mappers
  app/      Riverpod providers + action controllers (daily/onboarding/pool/settings)
  auth/     Firebase Auth boundary, bootstrap, AuthGate
  ui/       screens + widgets (welcome, onboarding, daily, manage, settings, sheets)
  theme/    colour tokens, type scale, ThemeData
tool/       dev-only scripts (seed_emulator.dart)
functions/  Cloud Functions (Phase 6 — not active)
docs/       design spec, backend decisions, implementation roadmap, plans/specs
```
